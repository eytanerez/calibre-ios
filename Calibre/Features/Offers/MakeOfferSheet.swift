import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

/// The offer entry sheet — amount with live serif rendering, an optional
/// note to the seller, the refundable hold consent, and the hold
/// PaymentSheet. Present in a `.sheet` (large detent comes from the scaffold).
///
/// No offer exists yet on this screen, so the hold figure comes from
/// `services.config` rather than a payload. When the config hasn't landed,
/// every sentence here drops the number and still reads correctly.
struct MakeOfferSheet: View {
    let listingID: String

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var model: MakeOfferModel?
    // The lesson quotes the hold, so it is rebuilt once the config lands —
    // `TutorialStep` is immutable by design.
    @State private var tutorial = TutorialController(
        id: "offers.make",
        steps: [MakeOfferSheet.holdStep(holdText: nil)]
    )
    @State private var tutorialHoldText: String?

    /// The coaching beat that sits on the consent row.
    private static func holdStep(holdText: String?) -> TutorialStep {
        let holdPhrase = holdText.map { "a refundable \($0) hold" } ?? "a refundable hold"
        return TutorialStep(
            id: "hold",
            anchor: "offer.hold",
            title: "A hold, not a charge",
            message: "Offers are backed by \(holdPhrase) on your credit card — never a charge. It's released once you pay, and it is only kept if the seller accepts and you then walk away.",
            advance: .tapToContinue,
            cutout: .roundedRect(Radius.card)
        )
    }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                SheetScaffold(title: "Make an offer", detents: [.large]) {
                    EmptyState(
                        icon: "arrow.left.arrow.right",
                        title: "Sign in to make an offer",
                        message: "Offers are backed by a small card hold, so we need to know it's you.",
                        actionTitle: "Sign in",
                        action: {
                            dismiss()
                            session.require("Sign in to make an offer") {}
                        }
                    )
                }
            } else if let model {
                sheetBody(model)
            } else {
                SheetScaffold(title: "Make an offer", detents: [.large]) {
                    ListingMiniCardSkeleton()
                }
            }
        }
        .task {
            // Rates and windows the sheet quotes before an offer exists.
            services.config.warm()
            guard session.isAuthenticated, model == nil else { return }
            let created = MakeOfferModel(
                listingID: listingID,
                catalog: services.catalog,
                commerce: services.commerce,
                client: services.client
            )
            model = created
            await created.load()
        }
    }

    @ViewBuilder
    private func sheetBody(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        switch model.phase {
        case .existing(let offer):
            // An open offer already exists — show its negotiation instead.
            NavigationStack {
                OfferDetailScreen(offerID: offer.id)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { dismiss() }
                                .font(CalibreType.bodySemiBold)
                                .tint(Color.calibre.primary)
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationBackground(Color.calibre.background)
            .presentationCornerRadius(Radius.overlay)
        default:
            SheetScaffold(title: scaffoldTitle(model), detents: [.large]) {
                ScrollView {
                    content(model)
                        .padding(.bottom, Space.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .tutorialOverlay(tutorial)
        }
    }

    private func scaffoldTitle(_ model: MakeOfferModel) -> String? {
        switch model.phase {
        case .sent: nil
        default: "Make an offer"
        }
    }

    @ViewBuilder
    private func content(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        switch model.phase {
        case .loading:
            VStack(spacing: Space.l) {
                ListingMiniCardSkeleton()
                Rectangle().frame(height: 52).shimmer()
                Rectangle().frame(height: 44).shimmer()
            }
        case .failed(let message):
            EmptyState(
                icon: "wifi.exclamationmark",
                title: "We couldn't load this listing",
                message: message,
                actionTitle: "Try again",
                action: { Task { await model.load() } }
            )
        case .input:
            inputForm(model)
        case .holdIssue(let message):
            holdIssue(model, message: message)
        case .sent(let offer):
            sentMoment(model, offer: offer)
        case .existing:
            EmptyView()
        }
    }

    // MARK: - Input

    @ViewBuilder
    private func inputForm(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Space.l) {
            if let listing = model.listing {
                ListingMiniCard(listing: listing)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("Your offer")
                Text(model.displayAmountText)
                    .font(CalibreType.priceLarge)
                    .foregroundStyle(Color.calibre.foreground)
                    .contentTransition(.numericText())
                    .animation(Motion.easeMedium, value: model.displayAmountText)

                CalibreTextField(
                    "Amount",
                    text: $model.amountText,
                    placeholder: "0",
                    error: model.amountError,
                    kind: .money
                ) {
                    Text("USD")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }

            CalibreTextEditor(
                "Message to the seller (optional)",
                text: $model.message,
                placeholder: "Anything they should know?",
                minHeight: 92,
                characterLimit: 1000
            )
            .onChange(of: model.message) { _, newValue in
                if newValue.count > 1000 {
                    model.message = String(newValue.prefix(1000))
                }
            }

            // The consent toggle gates `canSubmit`, so the disclosure has to be
            // on screen for the button to be reachable at all.
            consentRow(model)
                .tutorialAnchor("offer.hold")

            if let error = model.error {
                InlineErrorLine(message: error)
            }

            Button {
                Haptics.shared.play(.press)
                Task { await model.submit() }
            } label: {
                BusyLabel(title: continueTitle, busy: model.creating)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(!model.canSubmit || model.creating)
        }
        .animation(Motion.easeFast, value: model.error)
        .onAppear { startTutorial() }
    }

    /// "Continue — authorize the $250 hold", or the same sentence without the
    /// figure when the config hasn't stated one.
    private var continueTitle: String {
        "Continue — authorize the \(offerHoldNoun(services.config.offerHoldText))"
    }

    /// The disclosure §17.5 requires at placement, plus the consent it gates.
    private func consentRow(_ model: MakeOfferModel) -> some View {
        @Bindable var model = model
        let holdText = services.config.offerHoldText
        let disclosure = offerPlacementDisclosure(
            holdText: holdText,
            expiryHours: services.config.offerExpiryHours,
            graceHours: services.config.paymentGraceHours,
            paymentDueHours: services.config.paymentDeadlineHours
        )

        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Before you place this offer")
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)

            Text(disclosure)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Color.calibre.border)
                .frame(height: 1)

            HStack(alignment: .center, spacing: Space.m) {
                Text("I authorize the \(offerHoldNoun(holdText)) and understand it is kept only if the seller accepts and I then walk away.")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("", isOn: $model.consented)
                    .labelsHidden()
                    .tint(Color.calibre.primary)
            }
            .frame(minHeight: Space.touchTarget)
            .accessibilityElement(children: .combine)
        }
        .multilineTextAlignment(.leading)
        .padding(Space.l)
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    /// Rebuilds the lesson if the config has since supplied the hold figure,
    /// then starts it. The ledger keeps it to once per person either way.
    private func startTutorial() {
        let holdText = services.config.offerHoldText
        guard holdText != tutorialHoldText else {
            tutorial.startIfNeeded()
            return
        }
        let refreshed = TutorialController(
            id: "offers.make",
            steps: [MakeOfferSheet.holdStep(holdText: holdText)]
        )
        tutorialHoldText = holdText
        tutorial = refreshed
        refreshed.startIfNeeded()
    }

    // MARK: - Hold issue (failed / canceled PaymentSheet)

    private func holdIssue(_ model: MakeOfferModel, message: String?) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let listing = model.listing {
                ListingMiniCard(listing: listing)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                Text("Your offer isn't sent yet")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                // The offer exists by now, so its own hold is the figure.
                Text("The \(offerHoldNoun(offerHoldText(model.offer, config: services.config))) wasn't completed, so the seller hasn't seen your offer. You can finish the hold or withdraw the offer.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                InlineErrorLine(message: message)
            }

            Button {
                Haptics.shared.play(.press)
                model.retryHold()
            } label: {
                Text("Try the hold again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))

            Button {
                Task {
                    if await model.cancelOffer() {
                        toasts.show(title: "Offer withdrawn", message: "No hold was kept on your card.")
                        dismiss()
                    }
                }
            } label: {
                BusyLabel(title: "Cancel offer", busy: model.cancelling)
                    .foregroundStyle(Color.calibre.destructive)
            }
            .buttonStyle(.calibreGhost)
            .disabled(model.cancelling)
        }
    }

    // MARK: - Sent

    private func sentMoment(_ model: MakeOfferModel, offer: Offer) -> some View {
        VStack(spacing: Space.l) {
            Spacer(minLength: Space.xxl)
            IconTile(systemName: "paperplane")
            VStack(spacing: Space.s) {
                Text("Offer sent.")
                    .font(CalibreType.display)
                    .foregroundStyle(Color.calibre.foreground)
                Text(responseWindowLine(model.sellerName))
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Space.s) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                Text(holdAuthorizedCaption(offer))
                    .font(CalibreType.caption)
            }
            .foregroundStyle(Color.calibre.mutedForeground)

            Spacer(minLength: Space.xxl)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            Haptics.shared.play(.success)
        }
    }

    /// How long the seller has to answer — from the marketplace config, with
    /// the canonical window standing in only while it hasn't landed.
    private func responseWindowLine(_ seller: String) -> String {
        "\(seller) has \(offerExpiryPhrase(services.config.offerExpiryHours)) to respond. "
            + "We'll let you know the moment they do."
    }

    /// The receipt line on the sent moment — the offer's own hold figure.
    private func holdAuthorizedCaption(_ offer: Offer) -> String {
        guard let holdText = offerHoldText(offer, config: services.config) else {
            return "Hold authorized · released after payment"
        }
        return "\(holdText) hold authorized · released after payment"
    }
}

/// State for the offer entry sheet: listing, form fields, offer creation,
/// the hold PaymentSheet and its aftermath.
@MainActor
@Observable
final class MakeOfferModel {
    enum Phase {
        case loading
        case input
        case holdIssue(message: String?)
        case sent(Offer)
        case existing(Offer)
        case failed(String)
    }

    let listingID: String
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let checkout: CheckoutStore

    var phase: Phase = .loading
    var listing: Listing?

    var amountText = ""
    var message = ""
    var consented = false
    var error: String?
    private(set) var creating = false
    private(set) var cancelling = false

    private(set) var offer: Offer?
    private(set) var paymentSheet: PaymentSheet?

    init(listingID: String, catalog: CatalogStore, commerce: CommerceStore, client: APIClient) {
        self.listingID = listingID
        self.catalog = catalog
        self.commerce = commerce
        self.checkout = CheckoutStore(client: client)
    }

    var sellerName: String {
        listing?.seller?.username ?? "The seller"
    }

    func load() async {
        phase = .loading
        do {
            let listing = try await catalog.listing(id: listingID)
            self.listing = listing
            if amountText.isEmpty {
                amountText = plainAmount(listing.price.value)
            }
            phase = .input
        } catch {
            phase = .failed(friendlyMessage(error))
        }
    }

    // MARK: Amount

    var parsedAmount: Decimal? {
        InputValidation.positiveMoney(amountText)
    }

    var displayAmountText: String {
        guard let amount = parsedAmount else { return "$0" }
        return PriceFormatter.format(amount, currency: listing?.currency ?? "USD")
    }

    var amountError: String? {
        !InputValidation.isNonBlank(amountText) || parsedAmount != nil
            ? nil
            : "Enter an amount greater than zero with no more than two decimal places."
    }

    var canSubmit: Bool {
        parsedAmount != nil && consented && !creating
    }

    // MARK: Create + hold

    func submit() async {
        guard let amount = parsedAmount, consented, !creating else { return }
        creating = true
        error = nil
        defer { creating = false }
        do {
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let offer = try await commerce.createOffer(
                listingID: listingID,
                amount: amount,
                currency: listing?.currency ?? "USD",
                message: trimmedMessage.isEmpty ? nil : trimmedMessage
            )
            self.offer = offer
            // Schema puts `offer_started` at the create call succeeding,
            // deliberately independent of whether the card hold completes.
            Analytics.offerStarted(
                listing.map(Analytics.ListingInfo.init) ?? .init(id: listingID)
            )
            presentHold(for: offer)
        } catch let apiError as APIError {
            if case .server(let message, _, let status, _) = apiError, status == 409 {
                if let existing = await findOpenOffer() {
                    phase = .existing(existing)
                } else {
                    error = message
                }
            } else {
                error = apiError.errorDescription
            }
        } catch {
            self.error = friendlyMessage(error)
        }
    }

    private func presentHold(for offer: Offer) {
        guard let clientSecret = offer.hold?.clientSecret else {
            phase = .holdIssue(message: "We couldn't start the card hold. Please try again.")
            return
        }
        if let key = offer.publishableKey {
            STPAPIClient.shared.publishableKey = key
        }
        // The create response carries a mobile CustomerSession secret but no
        // Stripe customer id, which PaymentSheet's customer configuration
        // requires — so the hold sheet runs customer-less (cards + Apple Pay
        // still work; saved cards just don't redisplay).
        let configuration = CalibreStripe.configuration(
            customerID: nil,
            customerSessionClientSecret: nil
        )
        let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
        paymentSheet = sheet
        CalibreStripe.present(sheet) { [weak self] result in
            self?.handleHoldResult(result)
        }
    }

    func retryHold() {
        guard let offer else { return }
        presentHold(for: offer)
    }

    func handleHoldResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            Task { await confirmHold() }
        case .canceled:
            phase = .holdIssue(message: nil)
        case .failed(let failure):
            phase = .holdIssue(message: CalibreStripe.failureMessage(for: failure))
        }
    }

    private func confirmHold() async {
        guard let offer else { return }
        do {
            let confirmed = try await commerce.confirmHold(offerID: offer.id)
            self.offer = confirmed
            phase = .sent(confirmed)
        } catch {
            phase = .holdIssue(message: friendlyMessage(error))
        }
    }

    func cancelOffer() async -> Bool {
        guard let offer, !cancelling else { return false }
        cancelling = true
        defer { cancelling = false }
        do {
            _ = try await commerce.cancelOffer(offerID: offer.id)
            return true
        } catch {
            phase = .holdIssue(message: friendlyMessage(error))
            return false
        }
    }

    // MARK: Conflict → existing offer

    private func findOpenOffer() async -> Offer? {
        guard let offers = try? await checkout.offers(onListing: listingID) else { return nil }
        return offers.first { $0.perspective == "sent" && offerIsOpen($0) }
    }

    // MARK: Helpers

    private func plainAmount(_ value: Decimal) -> String {
        var rounded = value
        var result = Decimal()
        NSDecimalRound(&result, &rounded, 2, .plain)
        return "\(result)"
    }

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
