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
        .calibrePageBackground()
        .navigationTitle("Offer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            let created = OfferDetailModel(
                offerID: offerID,
                catalog: services.catalog,
                commerce: services.commerce,
                config: services.config,
                userID: session.user?.id,
                toasts: toasts,
                router: router
            )
            model = created
            async let config: Void = { _ = try? await services.config.load() }()
            await created.load()
            await config
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
    @State private var tutorial = TutorialController(
        id: "offers.detail",
        steps: [
            TutorialStep(
                id: "actions",
                anchor: "offer.actions",
                title: "The ball's in someone's court",
                message: "These buttons follow the negotiation: Accept, Counter, or Decline when it's your move — Counter opens an inline form. Once an offer is accepted, “Pay now” takes you straight to checkout at the agreed price.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.box)
            )
        ]
    )

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
        .calibrePageBackground()
        .tutorialOverlay(tutorial)
        .onChange(of: model.offer?.id) { _, id in
            if id != nil { tutorial.startIfNeeded() }
        }
        .refreshable { await model.load(quiet: true) }
    }

    @ViewBuilder
    private func content(_ offer: Offer) -> some View {
        let presentation = offerStatusPresentation(for: offer, viewerIsSeller: model.viewerIsSeller)

        VStack(alignment: .leading, spacing: Space.l) {
            OfferListingMiniCard(offer: offer, thumbURL: model.thumbURL)

            HStack(spacing: Space.m) {
                // Agreed and binding. `waxSeal` is the mark for exactly this
                // moment (CALIBRE_BY_HAND_CONTRACTS.md §4) and this is the one
                // screen in the negotiation that reaches it, so the budget of
                // one illustrated moment per step is spent here and nowhere
                // else in the flow. It presses when the screen first shows an
                // agreed offer and again if the status changes under it;
                // under Reduce Motion it is simply already sealed.
                if isAgreed(offer) {
                    CalibreMark.waxSeal(size: 44, trigger: offer.status)
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    StatusBadge(presentation.text, tone: presentation.tone)
                    if let deadline = offerLiveDeadline(for: offer) {
                        CountdownChip(until: deadline)
                    }
                }
                Spacer(minLength: 0)
            }

            // Money at risk comes before the negotiation history: a buyer
            // whose payment failed needs the clock and the figure first.
            if let notice = model.resolutionNotice {
                OfferResolutionBand(notice: notice)
            }

            // The deposit is what the whole negotiation stands on. When it is
            // close to running out — or the server has already refused an
            // action because it has — replacing it is the first thing on
            // screen, not a footnote.
            if model.showsHoldRenewal {
                holdRenewalBand(offer)
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

    /// An agreement that stands: the price is settled and the only thing
    /// left is the money. `paid` is past it — the seal marks the agreement
    /// being struck, not the payment clearing, and a mark that stayed on
    /// screen after the sale would be decoration.
    private func isAgreed(_ offer: Offer) -> Bool {
        offer.status == .acceptedPendingPayment
    }

    // MARK: - Renewing the deposit

    /// Only the buyer can renew their own card authorization, so the seller
    /// sees the plain fact and no button they could not press.
    @ViewBuilder
    private func holdRenewalBand(_ offer: Offer) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CalloutBand(
                icon: "creditcard.trianglebadge.exclamationmark",
                title: "Renew your deposit",
                message: model.holdRenewalMessage(offer)
            )

            if !model.viewerIsSeller {
                Button {
                    Haptics.shared.play(.press)
                    Task { await model.renewHold() }
                } label: {
                    BusyLabel(title: "Renew your deposit", busy: model.renewer.renewing)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.renewer.renewing)
            }

            if let error = model.renewer.error {
                InlineErrorLine(message: error)
            }
        }
        .animation(Motion.easeFast, value: model.renewer.error)
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
        .alert(
            model.acceptDialogTitle,
            isPresented: $model.confirmingAccept
        ) {
            Button("Accept") {
                Task { await model.respond(.accept(message: nil)) }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text(model.acceptDialogMessage)
        }
        .alert(
            "Decline this offer?",
            isPresented: $model.confirmingDecline
        ) {
            Button("Decline", role: .destructive) {
                Task { await model.respond(.decline(message: nil)) }
            }
            Button("Keep it open", role: .cancel) {}
        }
        .alert(
            "Cancel your offer?",
            isPresented: $model.confirmingCancel
        ) {
            Button("Cancel offer", role: .destructive) {
                Task { await model.cancel() }
            }
            Button("Keep it open", role: .cancel) {}
        } message: {
            Text(model.withdrawalHoldSentence)
        }
        .alert(
            "Back out of this purchase?",
            isPresented: $model.confirmingBackOut
        ) {
            Button("Back out", role: .destructive) {
                Task { await model.cancel() }
            }
            Button("Keep the deal", role: .cancel) {}
        } message: {
            Text(model.backOutMessage)
        }
        .tutorialAnchor("offer.actions")
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
                error: model.counterAmountError,
                kind: .money
            ) {
                Text(offer.currency)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .moneyFormatted($model.counterAmountText)

            CalibreTextField(
                "Message (optional)",
                text: $model.counterMessage,
                placeholder: "Add a note with your number",
                kind: .sentence
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
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
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
    /// Only ever consulted for figures that exist before the offer does; the
    /// offer's own `hold.amount` always wins.
    @ObservationIgnored let config: ConfigStore
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

    /// Runs the cancel-and-replace of the card authorization.
    let renewer: OfferHoldRenewer
    /// Set when the server has refused an action because the deposit aged
    /// out. Sticks until a renewal succeeds, so the way through stays on
    /// screen rather than disappearing with the error toast.
    private(set) var holdRenewalDemanded = false

    init(
        offerID: String,
        catalog: CatalogStore,
        commerce: CommerceStore,
        config: ConfigStore,
        userID: String?,
        toasts: ToastCenter,
        router: AppRouter
    ) {
        self.offerID = offerID
        self.catalog = catalog
        self.commerce = commerce
        self.config = config
        self.userID = userID
        self.toasts = toasts
        self.router = router
        self.renewer = OfferHoldRenewer(commerce: commerce)
    }

    // MARK: The deposit

    /// Either the hold is close enough to expiring to ask, or the server has
    /// already said it is too late to act without a new one.
    var showsHoldRenewal: Bool {
        holdRenewalDemanded || offerHoldNeedsRenewal(offer)
    }

    /// The date is the offer's own `hold.captureBefore` — never a window
    /// worked out here.
    func holdRenewalMessage(_ offer: Offer) -> String {
        let amount = offerHoldText(offer, config: config) ?? "the deposit"
        if holdRenewalDemanded {
            return viewerIsSeller
                ? "The buyer\u{2019}s \(amount) authorization has run out, so this offer can\u{2019}t move until they place a new one. We\u{2019}ve let them know."
                : "Your \(amount) authorization has run out. Place a new one and this offer picks up exactly where it left off."
        }
        let expiry = offer.hold?.captureBefore.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        }
        let when = expiry.map { " It runs out on \($0)." } ?? ""
        return viewerIsSeller
            ? "The buyer\u{2019}s \(amount) authorization is close to running out.\(when) We\u{2019}ve asked them to replace it."
            : "Your \(amount) authorization is close to running out.\(when) Replacing it keeps this offer alive \u{2014} an offer must never sit accepted with nothing behind it."
    }

    func renewHold() async {
        guard let renewed = await renewer.renew(offerID: offerID) else { return }
        offer = renewed
        holdRenewalDemanded = false
        actionError = nil
        toasts.show(
            title: "Deposit renewed",
            message: "Your offer is standing again.",
            tone: .success
        )
        await load(quiet: true)
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

    /// The hold's state in one line. The figure is the offer's own, and when
    /// the payload doesn't carry one the sentence simply loses its number.
    var holdCaption: String? {
        guard let offer, let hold = offer.hold else { return nil }
        let noun = offerHoldNoun(offerHoldText(offer, config: config))
        if offerSettledForfeit(offer) != nil || hold.capturedAt != nil {
            return "\(noun) forfeited to the seller"
        }
        if hold.releasedAt != nil { return "\(noun) released" }
        if hold.authorizedAt != nil || hold.status == "requires_capture" {
            return "\(noun) authorized · released after payment"
        }
        return nil
    }

    /// The failed-payment warning, or the settled outcome once the clock has
    /// run out. Nil when neither applies.
    var resolutionNotice: OfferResolutionNotice? {
        guard let offer else { return nil }
        return offerResolutionNotice(for: offer, viewerIsSeller: viewerIsSeller, config: config)
    }

    /// The hold released when a buyer withdraws — said with the real figure
    /// when we have it.
    var withdrawalHoldSentence: String {
        let noun = offerHoldNoun(offerHoldText(offer, config: config))
        return "Your \(noun) is released when the offer is withdrawn."
    }

    var withdrawnToastMessage: String {
        let noun = offerHoldNoun(offerHoldText(offer, config: config))
        return "Your \(noun) has been released."
    }

    /// Backing out of an accepted offer is the forfeiture case, stated with
    /// the exact amount at stake.
    var backOutMessage: String {
        let noun = offerHoldNoun(offerHoldText(offer, config: config))
        return "You agreed to buy this watch. If you back out now, your \(noun) is forfeited to the seller, less the cost of processing it."
    }

    var acceptDialogTitle: String {
        viewerIsSeller ? "Accept this offer?" : "Accept the counteroffer?"
    }

    /// §17.5 requires the forfeiture disclosure again at acceptance, adapted
    /// to whose money is at risk.
    var acceptDialogMessage: String {
        guard let offer else { return "" }
        return offerAcceptanceDisclosure(
            amountText: PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency),
            holdText: offerHoldText(offer, config: config),
            graceHours: config.paymentGraceHours,
            paymentDueHours: config.paymentDeadlineHours,
            viewerIsSeller: viewerIsSeller,
            buyerName: buyerName
        )
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
                        : "Pay within \(offerPaymentDuePhrase(config.paymentDeadlineHours)) to make it yours.",
                    tone: .success
                )
            case .decline:
                toasts.show(title: "Offer declined")
            case .counter:
                toasts.show(title: "Counter sent", message: "We'll let you know when they respond.", tone: .success)
            }
        } catch {
            Haptics.shared.play(.error)
            // Not a refusal of the price: the deposit behind the offer has
            // aged out. The renewal band is the answer, so it is put on
            // screen rather than left as an error the buyer can only reread.
            if offerHoldRenewalRequired(error) {
                holdRenewalDemanded = true
            }
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
            toasts.show(title: "Offer withdrawn", message: withdrawnToastMessage)
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
        router.push(.order(orderID))
    }

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
