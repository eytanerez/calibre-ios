import CalibreDesign
import CalibreKit
import SwiftUI

/// One negotiation, both sides of it. Route: `.offer(offerID)`. Works for
/// the buyer (sent) and the seller (received) — actions adapt to whose turn
/// it is.
struct OfferDetailScreen: View {
    let offerID: String

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var model: OfferDetailModel?

    var body: some View {
        Group {
            if let model {
                OfferDetailContent(model: model)
            } else {
                loadingSkeleton
            }
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Offer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let created = OfferDetailModel(
                offerID: offerID,
                catalog: services.catalog,
                commerce: services.commerce,
                userID: session.user?.id,
                toasts: toasts,
                router: router
            )
            model = created
            await created.load()
        }
    }

    private var loadingSkeleton: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                ListingMiniCardSkeleton()
                Rectangle().frame(height: 90).shimmer()
                Rectangle().frame(height: 90).shimmer()
            }
            .padding(Space.margin)
        }
    }
}

private struct OfferDetailContent: View {
    @Bindable var model: OfferDetailModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            switch model.phase {
            case .loading:
                VStack(spacing: Space.l) {
                    ListingMiniCardSkeleton()
                    Rectangle().frame(height: 90).shimmer()
                    Rectangle().frame(height: 90).shimmer()
                }
                .padding(Space.margin)
            case .failed(let message):
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "We couldn't load this offer",
                    message: message,
                    actionTitle: "Try again",
                    action: { Task { await model.load() } }
                )
                .padding(.top, Space.xxl)
            case .ready:
                if let offer = model.offer {
                    content(offer)
                }
            }
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .refreshable { await model.load(quiet: true) }
    }

    @ViewBuilder
    private func content(_ offer: Offer) -> some View {
        let presentation = offerStatusPresentation(for: offer, viewerIsSeller: model.viewerIsSeller)

        VStack(alignment: .leading, spacing: Space.l) {
            OfferListingMiniCard(offer: offer, thumbURL: model.thumbURL)

            HStack(spacing: Space.s) {
                StatusBadge(presentation.text, tone: presentation.tone)
                if let deadline = offerLiveDeadline(for: offer) {
                    CountdownChip(until: deadline)
                }
                Spacer()
            }

            if let holdCaption = model.holdCaption {
                HStack(spacing: Space.s) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12, weight: .medium))
                    Text(holdCaption)
                        .font(CalibreType.caption)
                }
                .foregroundStyle(Color.calibre.mutedForeground)
            }

            if !offer.negotiationHistory.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Eyebrow("Negotiation")
                    VStack(spacing: Space.m) {
                        ForEach(offer.negotiationHistory.indices, id: \.self) { index in
                            let entry = offer.negotiationHistory[index]
                            TimelineRow(
                                side: entry.by == "buyer" ? .buyer : .seller,
                                heading: model.heading(for: entry, at: index),
                                amount: PriceFormatter.format(entry.amount.value, currency: offer.currency),
                                message: entry.message,
                                date: entry.at ?? offer.createdAt ?? .now,
                                isFirst: index == 0,
                                isLast: index == offer.negotiationHistory.count - 1
                            )
                        }
                    }
                }
                .padding(.top, Space.s)
            }

            if let error = model.actionError {
                InlineErrorLine(message: error)
            }

            actions(offer)
                .padding(.top, Space.s)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.m)
        .padding(.bottom, Space.xxl)
        .animation(Motion.easeFast, value: model.actionError)
        .animation(Motion.easeMedium, value: model.showCounterForm)
    }

    // MARK: - Actions

    @ViewBuilder
    private func actions(_ offer: Offer) -> some View {
        let isSeller = model.viewerIsSeller

        VStack(spacing: Space.m) {
            switch offer.status {
            case .countered where !isSeller:
                acceptButton(
                    offer,
                    title: "Accept \(PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency))"
                )
                counterAndDecline(offer)

            case .pendingSeller where isSeller:
                acceptButton(offer, title: "Accept offer")
                counterAndDecline(offer)

            case .pendingSeller:
                Button {
                    model.confirmingCancel = true
                } label: {
                    BusyLabel(title: "Cancel offer", busy: model.acting)
                        .foregroundStyle(Color.calibre.destructive)
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
                .disabled(model.acting)

            case .acceptedPendingPayment where !isSeller:
                Button {
                    Haptics.shared.play(.press)
                    model.payNow()
                } label: {
                    Text("Pay now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))

                Button {
                    model.confirmingBackOut = true
                } label: {
                    Text("Back out")
                        .foregroundStyle(Color.calibre.destructive)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibreGhost)

            case .countered where isSeller:
                waitingCaption("Waiting on the buyer to respond to your counter.")

            case .acceptedPendingPayment where isSeller:
                waitingCaption("The listing is reserved while the buyer completes payment.")

            case .paid:
                if let orderID = offer.orderId {
                    Button {
                        model.openOrder(orderID)
                    } label: {
                        Text("View the order")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))
                }

            default:
                EmptyView()
            }
        }
        .confirmationDialog(
            model.acceptDialogTitle,
            isPresented: $model.confirmingAccept,
            titleVisibility: .visible
        ) {
            Button("Accept") {
                Task { await model.respond(.accept(message: nil)) }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(model.acceptDialogMessage)
        }
        .confirmationDialog(
            "Decline this offer?",
            isPresented: $model.confirmingDecline,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                Task { await model.respond(.decline(message: nil)) }
            }
            Button("Keep it open", role: .cancel) {}
        }
        .confirmationDialog(
            "Cancel your offer?",
            isPresented: $model.confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel offer", role: .destructive) {
                Task { await model.cancel() }
            }
            Button("Keep it open", role: .cancel) {}
        } message: {
            Text("Your $250 hold is released when the offer is withdrawn.")
        }
        .confirmationDialog(
            "Back out of this purchase?",
            isPresented: $model.confirmingBackOut,
            titleVisibility: .visible
        ) {
            Button("Back out", role: .destructive) {
                Task { await model.cancel() }
            }
            Button("Keep the deal", role: .cancel) {}
        } message: {
            Text("You agreed to buy this watch. If you back out now, Calibre may charge the $250 hold on your card.")
        }
    }

    private func acceptButton(_ offer: Offer, title: String) -> some View {
        Button {
            Haptics.shared.play(.press)
            model.confirmingAccept = true
        } label: {
            BusyLabel(title: title, busy: model.acting)
        }
        .buttonStyle(.calibre(.primary, fullWidth: true))
        .disabled(model.acting)
    }

    @ViewBuilder
    private func counterAndDecline(_ offer: Offer) -> some View {
        if model.showCounterForm {
            counterForm(offer)
        } else {
            HStack(spacing: Space.m) {
                Button {
                    withAnimation(Motion.easeMedium) {
                        model.showCounterForm = true
                    }
                } label: {
                    Text("Counter")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))

                Button {
                    model.confirmingDecline = true
                } label: {
                    Text("Decline")
                        .foregroundStyle(Color.calibre.destructive)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
            }
        }
    }

    private func counterForm(_ offer: Offer) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CalibreTextField(
                "Your counter",
                text: $model.counterAmountText,
                placeholder: "0",
                error: model.counterAmountError
            ) {
                Text(offer.currency)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .keyboardType(.decimalPad)

            CalibreTextField(
                "Message (optional)",
                text: $model.counterMessage,
                placeholder: "Add a note with your number"
            )
            .onChange(of: model.counterMessage) { _, value in
                if value.count > 1_000 {
                    model.counterMessage = String(value.prefix(1_000))
                }
            }

            HStack(spacing: Space.m) {
                Button {
                    Haptics.shared.play(.press)
                    Task { await model.sendCounter() }
                } label: {
                    BusyLabel(title: "Send counter", busy: model.acting)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.parsedCounterAmount == nil || model.acting)

                Button("Never mind") {
                    withAnimation(Motion.easeMedium) {
                        model.showCounterForm = false
                    }
                }
                .buttonStyle(.calibreGhost)
            }
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .offset(y: -6)))
    }

    private func waitingCaption(_ text: String) -> some View {
        Text(text)
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// State + actions for one offer.
@MainActor
@Observable
final class OfferDetailModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    let offerID: String
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let userID: String?
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let router: AppRouter

    var phase: Phase = .loading
    private(set) var offer: Offer?
    private(set) var thumbURL: URL?

    var actionError: String?
    private(set) var acting = false

    var showCounterForm = false
    var counterAmountText = ""
    var counterMessage = ""

    var confirmingAccept = false
    var confirmingDecline = false
    var confirmingCancel = false
    var confirmingBackOut = false

    init(
        offerID: String,
        catalog: CatalogStore,
        commerce: CommerceStore,
        userID: String?,
        toasts: ToastCenter,
        router: AppRouter
    ) {
        self.offerID = offerID
        self.catalog = catalog
        self.commerce = commerce
        self.userID = userID
        self.toasts = toasts
        self.router = router
    }

    var viewerIsSeller: Bool {
        guard let offer else { return false }
        return offerViewerIsSeller(offer, userID: userID)
    }

    func load(quiet: Bool = false) async {
        if !quiet { phase = .loading }
        do {
            let offer = try await commerce.offer(id: offerID)
            self.offer = offer
            phase = .ready
            if thumbURL == nil, let listing = try? await catalog.listing(id: offer.listingId) {
                thumbURL = listing.images.first?.url
            }
        } catch {
            if !quiet {
                phase = .failed(friendlyMessage(error))
            }
        }
    }

    // MARK: Copy

    func heading(for entry: NegotiationEntry, at index: Int) -> String {
        let isViewer = (entry.by == "buyer" && !viewerIsSeller) || (entry.by == "seller" && viewerIsSeller)
        let isOpening = index == 0
        if isViewer {
            return isOpening ? "You offered" : "You countered"
        }
        let counterpart = entry.by == "buyer" ? buyerName : "The seller"
        return isOpening ? "\(counterpart) offered" : "\(counterpart) countered"
    }

    private var buyerName: String {
        offer?.buyer?.username ?? "The buyer"
    }

    var holdCaption: String? {
        guard let hold = offer?.hold else { return nil }
        if hold.capturedAt != nil { return "$250 deposit charged" }
        if hold.releasedAt != nil { return "$250 hold released" }
        if hold.authorizedAt != nil || hold.status == "requires_capture" {
            return "$250 hold authorized · released after payment"
        }
        return nil
    }

    var acceptDialogTitle: String {
        viewerIsSeller ? "Accept this offer?" : "Accept the counteroffer?"
    }

    var acceptDialogMessage: String {
        guard let offer else { return "" }
        let amount = PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency)
        if viewerIsSeller {
            return "The listing is reserved and \(buyerName) has 24 hours to pay \(amount)."
        }
        return "You're agreeing to buy this watch for \(amount). Payment is due within 24 hours."
    }

    // MARK: Actions

    func respond(_ action: CommerceStore.OfferAction) async {
        guard !acting else { return }
        acting = true
        actionError = nil
        defer { acting = false }
        do {
            let updated = try await commerce.respond(toOffer: offerID, action)
            offer = updated
            showCounterForm = false
            Haptics.shared.play(.success)
            switch action {
            case .accept:
                toasts.show(
                    title: "Offer accepted",
                    message: viewerIsSeller
                        ? "The listing is reserved while the buyer pays."
                        : "Pay within 24 hours to make it yours.",
                    tone: .success
                )
            case .decline:
                toasts.show(title: "Offer declined")
            case .counter:
                toasts.show(title: "Counter sent", message: "We'll let you know when they respond.", tone: .success)
            }
        } catch {
            Haptics.shared.play(.error)
            actionError = friendlyMessage(error)
        }
    }

    var parsedCounterAmount: Decimal? {
        InputValidation.positiveMoney(counterAmountText)
    }

    var counterAmountError: String? {
        !InputValidation.isNonBlank(counterAmountText) || parsedCounterAmount != nil
            ? nil
            : "Enter an amount greater than zero with no more than two decimal places."
    }

    func sendCounter() async {
        guard let amount = parsedCounterAmount, !acting else { return }
        let trimmed = counterMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        await respond(.counter(amount: amount, message: trimmed.isEmpty ? nil : trimmed))
    }

    func cancel() async {
        guard !acting else { return }
        acting = true
        actionError = nil
        defer { acting = false }
        do {
            let updated = try await commerce.cancelOffer(offerID: offerID)
            offer = updated
            toasts.show(title: "Offer withdrawn", message: "Your $250 hold has been released.")
        } catch {
            Haptics.shared.play(.error)
            actionError = friendlyMessage(error)
        }
    }

    func payNow() {
        guard let offer else { return }
        router.open(.checkout(offer.listingId, offerID: offer.id))
    }

    func openOrder(_ orderID: String) {
        router.open(.order(orderID))
    }

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
