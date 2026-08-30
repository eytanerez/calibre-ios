import CalibreDesign
import CalibreKit
import SwiftUI

/// Every negotiation in one place — Sent / Received segments, swipe actions
/// for the quick answers, tap through to the detail. Exported for the
/// Activity tab (route `.offers`).
struct OffersListScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    @State private var model: OffersListModel?
    @State private var segment: OffersSegment = .sent
    @State private var tutorial = TutorialController(id: "offers.list", steps: steps(expiryHours: nil))

    /// The lesson's own copy quotes the offer's time to live, so it is built
    /// once the marketplace config has stated it — the canonical window only
    /// stands in while the config hasn't landed.
    private static func steps(expiryHours: Int?) -> [TutorialStep] {
        [
            TutorialStep(
                id: "swipe",
                anchor: "offers.list",
                title: "Swipe for the quick answer",
                message: "Swipe any offer row: Accept or Decline the ones waiting on you, or Cancel one you sent. Each offer expires \(offerExpiryPhrase(expiryHours)) after the last move.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.box),
                cutoutPadding: Space.xs
            ),
            TutorialStep(
                id: "segments",
                anchor: "offers.segments",
                title: "Two sides to every deal",
                message: "Sent holds what you've offered; Received holds what buyers have offered you. Tap across to see the other side.",
                advance: .perform(event: "segment"),
                hint: .tap,
                cutout: .roundedRect(Radius.control),
                actionPrompt: "Tap a segment"
            ),
        ]
    }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "arrow.left.arrow.right",
                    title: "Sign in to see your offers",
                    message: "Your negotiations — sent and received — live here once you're signed in.",
                    actionTitle: "Sign in",
                    action: { session.require("Sign in to see your offers") {} }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let model {
                content(model)
            } else {
                Color.calibre.background
            }
        }
        .calibrePageBackground()
        .tutorialOverlay(tutorial)
        .navigationTitle("Offers")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: segment) { _, _ in tutorial.fire("segment") }
        .task {
            guard session.isAuthenticated, model == nil else { return }
            let created = OffersListModel(
                catalog: services.catalog,
                commerce: services.commerce,
                config: services.config,
                seller: services.seller,
                client: services.client,
                userID: session.user?.id,
                toasts: toasts
            )
            model = created
            await created.load()
        }
        .task { try? await services.config.load() }
    }

    @ViewBuilder
    private func content(_ model: OffersListModel) -> some View {
        VStack(spacing: 0) {
            SegmentedTabs(
                selection: $segment,
                items: [(.sent, "Sent"), (.received, "Received")]
            )
            .padding(.horizontal, Space.margin)
            .tutorialAnchor("offers.segments")

            switch model.phase {
            case .loading:
                loadingRows
            case .failed(let message):
                EmptyState(
                    icon: "wifi.exclamationmark",
                    title: "We couldn't load your offers",
                    message: message,
                    actionTitle: "Try again",
                    action: { Task { await model.load() } }
                )
                Spacer()
            case .ready:
                let offers = model.offers(for: segment)
                if offers.isEmpty {
                    emptyState
                    Spacer()
                } else {
                    list(offers, model: model)
                }
            }
        }
    }

    private func list(_ offers: [Offer], model: OffersListModel) -> some View {
        List {
            ForEach(offers) { offer in
                OfferRow(
                    offer: offer,
                    viewerIsSeller: segment == .received,
                    thumbURL: model.thumbs.url(for: offer.listingId),
                    netProceeds: segment == .received ? model.netProceeds(for: offer) : nil,
                    currency: offer.currency,
                    feePercent: model.effectiveFeePercent,
                    includesShipping: model.hasShippingEstimate(for: offer)
                )
                .onAppear { model.thumbs.warm(listingID: offer.listingId) }
                .listRowBackground(Color.calibre.background)
                .listRowSeparatorTint(Color.calibre.border)
                .listRowInsets(EdgeInsets(top: Space.m, leading: Space.margin, bottom: Space.m, trailing: Space.margin))
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if segment == .received, offer.status == .pendingSeller {
                        Button {
                            model.pendingAction = .accept(offer)
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                        }
                        .tint(Color.calibre.success)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if segment == .received, offer.status == .pendingSeller {
                        Button {
                            model.pendingAction = .decline(offer)
                        } label: {
                            Label("Decline", systemImage: "xmark")
                        }
                        .tint(Color.calibre.destructive)
                    } else if segment == .sent, offerIsOpen(offer) {
                        Button {
                            model.pendingAction = .cancel(offer)
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .tint(Color.calibre.destructive)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .tutorialAnchor("offers.list")
        .onAppear {
            tutorial.adopt(steps: Self.steps(expiryHours: services.config.offerExpiryHours))
            tutorial.startIfNeeded()
        }
        .refreshable { await model.load(quiet: true) }
        .alert(
            model.pendingAction?.title ?? "",
            isPresented: Binding(
                get: { model.pendingAction != nil },
                set: { if !$0 { model.pendingAction = nil } }
            )
        ) {
            if let action = model.pendingAction {
                Button(action.confirmLabel, role: action.isDestructive ? .destructive : nil) {
                    Task { await model.perform(action) }
                }
            }
            Button("Not now", role: .cancel) { model.pendingAction = nil }
        } message: {
            if let action = model.pendingAction {
                Text(model.confirmationMessage(action))
            }
        }
    }

    private var loadingRows: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: Space.m) {
                        Rectangle().frame(width: 56, height: 56).shimmer()
                        VStack(alignment: .leading, spacing: Space.s) {
                            Rectangle().frame(width: 170, height: 13).shimmer()
                            Rectangle().frame(width: 80, height: 16).shimmer()
                            Rectangle().frame(width: 120, height: 11).shimmer()
                        }
                        Spacer()
                    }
                }
            }
            .padding(Space.margin)
        }
    }

    private var emptyState: some View {
        Group {
            switch segment {
            case .sent:
                EmptyState(
                    icon: "arrow.up.right",
                    title: "No offers yet",
                    message: "You haven't made any offers yet. Found a watch you love? Start the conversation."
                )
            case .received:
                EmptyState(
                    icon: "arrow.down.left",
                    title: "Nothing received yet",
                    message: "Offers on your listings land here, with \(offerExpiryPhrase(services.config.offerExpiryHours)) to respond to each one."
                )
            }
        }
    }
}

enum OffersSegment: Hashable {
    case sent, received
}

/// One offer row — thumb, serif amount, status, countdown, latest message.
private struct OfferRow: View {
    let offer: Offer
    let viewerIsSeller: Bool
    let thumbURL: URL?
    /// Seller side only, and only when the server has stated a rate.
    var netProceeds: SellerNetProceeds?
    var currency: String = "USD"
    var feePercent: Decimal?
    var includesShipping: Bool = false

    var body: some View {
        NavigationLink {
            OfferDetailScreen(offerID: offer.id)
        } label: {
            HStack(alignment: .top, spacing: Space.m) {
                SquareThumb(url: thumbURL, side: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.listing?.title ?? "Listing")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)

                    Text(PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)

                    HStack(spacing: Space.s) {
                        let presentation = offerStatusPresentation(for: offer, viewerIsSeller: viewerIsSeller)
                        StatusBadge(presentation.text, tone: presentation.tone)
                        if let deadline = offerLiveDeadline(for: offer) {
                            CountdownChip(until: deadline)
                        }
                    }
                    .padding(.top, 2)

                    if offerHoldNeedsRenewal(offer) {
                        Label(
                            viewerIsSeller ? "Buyer\u{2019}s deposit expiring" : "Renew your deposit",
                            systemImage: "creditcard.trianglebadge.exclamationmark"
                        )
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.primary)
                        .padding(.top, 1)
                    }

                    if let netProceeds {
                        netProceedsLine(netProceeds)
                    }

                    if let preview = offerLatestMessage(offer) {
                        Text(preview)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(1)
                            .padding(.top, 1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What the seller would take home, and the working behind it. Labelled
    /// an estimate every time it is shown: the shipping figure is priced from
    /// a standard box, and the real label is bought after the sale.
    private func netProceedsLine(_ estimate: SellerNetProceeds) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("You\u{2019}d take home about \(PriceFormatter.format(estimate.takeHome, currency: currency))")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(workingText(estimate))
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("An estimate \u{2014} the shipping figure is priced from a standard box, and the actual label cost is what comes off your payout.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func workingText(_ estimate: SellerNetProceeds) -> String {
        var line = "\(PriceFormatter.format(estimate.offerAmount, currency: currency)) offer \u{2212} \(PriceFormatter.format(estimate.commission, currency: currency)) commission"
        if let feePercent {
            line += " (\(feePercentText(feePercent))%\(estimate.minimumApplied ? ", minimum applied" : ""))"
        } else if estimate.minimumApplied {
            line += " (minimum applied)"
        }
        if includesShipping {
            line += " \u{2212} \(PriceFormatter.format(estimate.shipping, currency: currency)) estimated shipping"
        }
        return line
    }
}

/// State + quick actions for the offers list.
@MainActor
@Observable
final class OffersListModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum QuickAction {
        case accept(Offer)
        case decline(Offer)
        case cancel(Offer)

        var title: String {
            switch self {
            case .accept: "Accept this offer?"
            case .decline: "Decline this offer?"
            case .cancel: "Cancel your offer?"
            }
        }

        /// Every hold figure here is the offer's own `hold.amount` — for a
        /// specific offer the payload always wins. The accept case's windows
        /// come from the marketplace config, so it is composed on the model
        /// (see `confirmationMessage(_:)`) where the config is reachable;
        /// this is only its fallback.
        var message: String {
            switch self {
            case .accept(let offer):
                offerAcceptanceDisclosure(
                    amountText: PriceFormatter.format(
                        offerCurrentAmount(offer),
                        currency: offer.currency
                    ),
                    holdText: offerHoldText(offer),
                    graceHours: nil,
                    paymentDueHours: nil,
                    viewerIsSeller: true,
                    buyerName: offer.buyer?.username ?? "the buyer"
                )
            case .decline(let offer):
                "The buyer's \(offerHoldNoun(offerHoldText(offer))) is released and the negotiation ends."
            case .cancel(let offer):
                "Your \(offerHoldNoun(offerHoldText(offer))) is released when the offer is withdrawn."
            }
        }

        var confirmLabel: String {
            switch self {
            case .accept: "Accept"
            case .decline: "Decline"
            case .cancel: "Cancel offer"
            }
        }

        var isDestructive: Bool {
            switch self {
            case .accept: false
            case .decline, .cancel: true
            }
        }
    }

    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let userID: String?
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let seller: SellerStore
    @ObservationIgnored private let client: APIClient
    let thumbs: ListingThumbCache

    var phase: Phase = .loading
    private(set) var all: [Offer] = []
    var pendingAction: QuickAction?

    /// The rate this seller is actually quoted, from the server — a
    /// negotiated override included. Nil until it lands, and nil is an
    /// answer: no rate means no net-proceeds figure at all, because a
    /// commission guessed from a tier the seller may not be on would be
    /// contradicted at the sale.
    private(set) var effectiveFeePercent: Decimal?
    /// offer amount → the seller's estimated label to authentication.
    private(set) var shippingEstimates: [Decimal: Decimal] = [:]

    init(
        catalog: CatalogStore,
        commerce: CommerceStore,
        config: ConfigStore,
        seller: SellerStore,
        client: APIClient,
        userID: String?,
        toasts: ToastCenter
    ) {
        self.commerce = commerce
        self.config = config
        self.seller = seller
        self.client = client
        self.userID = userID
        self.toasts = toasts
        self.thumbs = ListingThumbCache(catalog: catalog)
    }

    // MARK: What a seller would take home

    /// Loaded only once there is something to price. A member who has never
    /// listed a watch is never asked for a seller rate.
    private func loadSellerFigures() async {
        let received = all.filter { offerViewerIsSeller($0, userID: userID) }
        guard !received.isEmpty else { return }

        if effectiveFeePercent == nil {
            // The profile carries the resolved rate; the dashboard is the
            // fallback for a build whose profile predates it.
            if let profile = try? await client.accountProfile(),
               let percent = profile.dealerApplication?.effectiveFeePercent?.value {
                effectiveFeePercent = percent
            } else if let percent = seller.dashboard?.dealerApplication?.effectiveFeePercent?.value {
                effectiveFeePercent = percent
            }
        }

        // Priced against the offer rather than the asking price, from the
        // same endpoint the sell form uses — and it inherits that endpoint's
        // caveat, which is why every figure is called an estimate.
        for amount in Set(received.map { offerCurrentAmount($0) }) where shippingEstimates[amount] == nil {
            guard amount > 0 else { continue }
            if let quote = try? await seller.shippingEstimate(listingPrice: amount) {
                shippingEstimates[amount] = quote.amount.value
            }
        }
    }

    /// What this offer would leave the seller, or nil when we cannot say.
    func netProceeds(for offer: Offer) -> SellerNetProceeds? {
        let amount = offerCurrentAmount(offer)
        return SellerNetProceeds(
            offerAmount: amount,
            feePercent: effectiveFeePercent,
            feeMinimum: config.config?.sellerFeeMinimum?.value,
            shippingEstimate: shippingEstimates[amount]
        )
    }

    /// True when a shipping figure was actually priced, so the sentence can
    /// name it rather than pretending a zero is an estimate.
    func hasShippingEstimate(for offer: Offer) -> Bool {
        shippingEstimates[offerCurrentAmount(offer)] != nil
    }

    /// The disclosure §17.5 requires at acceptance, built with the windows the
    /// marketplace config states. The hold figure stays the offer's own.
    func confirmationMessage(_ action: QuickAction) -> String {
        guard case .accept(let offer) = action else { return action.message }
        return offerAcceptanceDisclosure(
            amountText: PriceFormatter.format(offerCurrentAmount(offer), currency: offer.currency),
            holdText: offerHoldText(offer),
            graceHours: config.paymentGraceHours,
            paymentDueHours: config.paymentDeadlineHours,
            viewerIsSeller: true,
            buyerName: offer.buyer?.username ?? "the buyer"
        )
    }

    func load(quiet: Bool = false) async {
        if !quiet { phase = .loading }
        do {
            all = try await commerce.offers()
            phase = .ready
            await loadSellerFigures()
        } catch {
            if !quiet {
                phase = .failed((error as? APIError)?.errorDescription ?? "Something went wrong.")
            }
        }
    }

    func offers(for segment: OffersSegment) -> [Offer] {
        all.filter { offer in
            let isSeller = offerViewerIsSeller(offer, userID: userID)
            return segment == .received ? isSeller : !isSeller
        }
    }

    func perform(_ action: QuickAction) async {
        pendingAction = nil
        do {
            switch action {
            case .accept(let offer):
                _ = try await commerce.respond(toOffer: offer.id, .accept(message: nil))
                Haptics.shared.play(.success)
                toasts.show(
                    title: "Offer accepted",
                    message: "The buyer has \(offerPaymentDuePhrase(config.paymentDeadlineHours)) to pay.",
                    tone: .success
                )
            case .decline(let offer):
                _ = try await commerce.respond(toOffer: offer.id, .decline(message: nil))
                toasts.show(title: "Offer declined")
            case .cancel(let offer):
                _ = try await commerce.cancelOffer(offerID: offer.id)
                toasts.show(
                    title: "Offer withdrawn",
                    message: "Your \(offerHoldNoun(offerHoldText(offer))) has been released."
                )
            }
            await load(quiet: true)
        } catch {
            Haptics.shared.play(.error)
            // Not a refusal of the price: the deposit behind the offer has
            // aged out and there is nothing standing behind it any more. Only
            // the buyer can replace their own authorization, so the seller is
            // told what is happening rather than offered a button they could
            // not press.
            if offerHoldRenewalRequired(error) {
                toasts.show(
                    title: "The buyer\u{2019}s deposit has run out",
                    message: "This offer can\u{2019}t move until they place a new one. We\u{2019}ve asked them to.",
                    tone: .neutral
                )
                await load(quiet: true)
                return
            }
            toasts.show(
                title: "That didn't go through",
                message: (error as? APIError)?.errorDescription ?? "Please try again.",
                tone: .error
            )
        }
    }
}
