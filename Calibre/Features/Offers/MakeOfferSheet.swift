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
    /// True once the note has hit its limit, so the clamp is spoken at the
    /// boundary rather than on every rejected keystroke after it.
    @State private var messageClamped = false

    /// The coaching beat that sits on the consent row.
    private static func holdStep(holdText: String?) -> TutorialStep {
        let holdPhrase = holdText.map { "a refundable \($0) hold" } ?? "a refundable hold"
        return TutorialStep(
            id: "hold",
            anchor: "offer.hold",
            title: "A hold, not a charge",
            message: "Offers are backed by \(holdPhrase) on your credit card — never a charge. It's released once you pay, and it is only kept if the seller accepts and you then walk away.",
            advance: .tapToContinue,
            cutout: .roundedRect(Radius.box)
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
                config: services.config,
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
            .presentationCornerRadius(Radius.panel)
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
                .moneyFormatted($model.amountText)
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
                    // The clamp is invisible unless you can see the counter —
                    // typing simply stops adding characters. Say it once, at
                    // the boundary; silent when nothing is listening.
                    if !messageClamped {
                        messageClamped = true
                        A11y.announce("Character limit reached. 1000 of 1000 characters.")
                    }
                } else if newValue.count < 1000 {
                    messageClamped = false
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
                    // The sentence is the switch's label, so it should behave
                    // like one: three lines of text beside a 51pt switch is a
                    // lot of row that does nothing when you tap it. Hit region
                    // only — no pixel moves, and the switch keeps its own
                    // touches.
                    .contentShape(Rectangle())
                    .onTapGesture { model.consented.toggle() }

                Toggle("", isOn: $model.consented)
                    .labelsHidden()
                    .tint(Color.calibre.primary)
            }
            .frame(minHeight: Space.touchTarget)
            // `.combine` rather than `.contain`/`.ignore`: the switch has no
            // label of its own (`labelsHidden`), so the sentence has to merge
            // into it or the control reads as a bare unlabelled toggle.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isToggle)
        }
        .multilineTextAlignment(.leading)
        .padding(Space.l)
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
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
    @ObservationIgnored private let config: ConfigStore
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

    /// The last card refusal, kept past the sheet that showed it. Stripe's
    /// form closes when the buyer backs out of it, taking its red line with
    /// it; the reason has to survive onto our own screen.
    private(set) var lastRefusal: OfferHoldCardRefusal?
    /// The server's sentence for a 409 raised inside the card sheet — the
    /// buyer already has an open offer here. Resolved into `.existing` once
    /// the sheet is out of the way, and read out loud if that lookup comes
    /// back empty.
    private var conflictMessage: String?

    init(
        listingID: String,
        catalog: CatalogStore,
        commerce: CommerceStore,
        config: ConfigStore,
        client: APIClient
    ) {
        self.listingID = listingID
        self.catalog = catalog
        self.commerce = commerce
        self.config = config
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

    /// The hold figure the offer will carry, in words, before an offer exists
    /// to state it. Nil until the config lands, and a refusal written from a
    /// nil figure simply has no number in it.
    private var holdText: String? { config.offerHoldText }

    /// The same figure in the units Stripe wants, and the gate on collecting
    /// the card first: a card sheet needs an amount for its own button, and
    /// guessing one is not an option, so a config that hasn't landed sends
    /// the flow down the older path instead. Straight from the config —
    /// never remembered, never recovered from a formatted string.
    private var holdAmountCents: Int? {
        guard let amount = config.config?.offerHoldAmount?.value, amount > 0 else { return nil }
        var scaled = amount * 100
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)
        let cents = NSDecimalNumber(decimal: whole).intValue
        return cents > 0 ? cents : nil
    }

    func submit() async {
        guard let amount = parsedAmount, consented, !creating else { return }
        creating = true
        error = nil
        lastRefusal = nil
        conflictMessage = nil
        defer { creating = false }

        // The card first. Stripe hands the chosen PaymentMethod back before
        // it confirms anything, so the funding rule can be applied while
        // there is still no offer row and no PaymentIntent to be refused
        // against — a debit or prepaid card is turned away without a $250
        // authorization ever appearing on the buyer's statement.
        if let holdAmountCents, let key = try? await OfferStripeKey.resolve(commerce) {
            STPAPIClient.shared.publishableKey = key
            presentHoldForNewOffer(amount: amount, holdAmountCents: holdAmountCents)
            return
        }
        await createOfferThenHold(amount: amount)
    }

    /// Path 1 — the card is collected, checked and only then turned into an
    /// offer. `POST /listings/<id>/offers` gets the `payment_method_id` and
    /// answers 402 before it writes anything, so a refusal costs the buyer a
    /// retype rather than a hold their bank has already seen.
    private func presentHoldForNewOffer(amount: Decimal, holdAmountCents: Int) {
        let currency = listing?.currency ?? "USD"
        let intentConfiguration = PaymentSheet.IntentConfiguration(
            // Every value here has to be the one the server puts on the
            // PaymentIntent it creates inside `holdClientSecret`: the
            // marketplace hold, the offer's currency, `off_session` and a
            // manual capture, because a deposit is an authorization that is
            // captured later or not at all.
            mode: .payment(
                amount: holdAmountCents,
                currency: currency,
                setupFutureUsage: .offSession,
                captureMethod: .manual
            ),
            paymentMethodTypes: ["card"],
            confirmHandler: { [weak self] paymentMethod, _ in
                guard let self else { throw OfferHoldStartError.unavailable }
                return try await self.holdClientSecret(for: paymentMethod, amount: amount)
            }
        )
        let configuration = CalibreStripe.configuration(
            customerID: nil,
            customerSessionClientSecret: nil
        )
        let sheet = PaymentSheet(intentConfiguration: intentConfiguration, configuration: configuration)
        paymentSheet = sheet
        CalibreStripe.present(sheet) { [weak self] result in
            self?.handleHoldResult(result)
        }
    }

    /// Runs when the buyer taps the sheet's button, with the card they chose
    /// and nothing authorized yet. Throwing here leaves Stripe's form open
    /// with the thrown sentence under it, which is the whole reason the
    /// refusal can afford to be this early.
    private func holdClientSecret(for paymentMethod: STPPaymentMethod, amount: Decimal) async throws -> String {
        // A second pass through the same sheet, after a card already cleared
        // the server's check and an offer was written: asking for another
        // offer on this listing is a 409, so the intent in hand is reused.
        // The server's pre-check cannot run again — which is the one place
        // the funding Stripe already told us about is worth reading, and
        // `confirm-hold` still has the last word on what actually authorized.
        if let offer, let clientSecret = offer.hold?.clientSecret {
            if let funding = offerHoldRefusedFunding(paymentMethod) {
                let refusal = OfferHoldCardRefusal(clientRead: funding, holdText: holdText)
                lastRefusal = refusal
                throw refusal
            }
            return clientSecret
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await commerce.createOffer(
                listingID: listingID,
                amount: amount,
                currency: listing?.currency ?? "USD",
                message: trimmedMessage.isEmpty ? nil : trimmedMessage,
                penaltyConsent: consented,
                paymentMethodID: paymentMethod.stripeId
            )
            self.offer = created
            lastRefusal = nil
            // Schema puts `offer_started` at the create call succeeding,
            // deliberately independent of whether the card hold completes.
            Analytics.offerStarted(
                listing.map(Analytics.ListingInfo.init) ?? .init(id: listingID)
            )
            guard let clientSecret = created.hold?.clientSecret else {
                throw OfferHoldStartError.unavailable
            }
            return clientSecret
        } catch {
            if let refusal = OfferHoldCardRefusal(error, origin: .beforeAuthorization, holdText: holdText) {
                lastRefusal = refusal
                throw refusal
            }
            if let apiError = error as? APIError,
               case .server(let serverMessage, _, let status, _) = apiError, status == 409 {
                // Can't change screens from underneath Stripe's sheet; the
                // buyer reads the server's own sentence there, and the
                // negotiation they already have opens when it closes.
                conflictMessage = serverMessage
            }
            throw error
        }
    }

    /// Path 2 — the offer first, the card after. What every client did before
    /// the card could be collected up front, and still what runs when there
    /// is no hold figure to put on a sheet or the publishable key didn't
    /// arrive. An authorization is placed here before anything checks the
    /// card, which is exactly what `confirm-hold` is for.
    private func createOfferThenHold(amount: Decimal) async {
        do {
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let offer = try await commerce.createOffer(
                listingID: listingID,
                amount: amount,
                currency: listing?.currency ?? "USD",
                message: trimmedMessage.isEmpty ? nil : trimmedMessage,
                penaltyConsent: consented
            )
            self.offer = offer
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
            settleClosedSheet(message: nil)
        case .failed(let failure):
            settleClosedSheet(message: CalibreStripe.failureMessage(for: failure))
        }
    }

    /// Where the buyer lands when the card sheet closes with no authorization
    /// behind it.
    ///
    /// Collecting the card first means "the sheet closed" no longer implies
    /// an offer exists. `holdIssue` offers to finish the hold or withdraw the
    /// offer, and both sentences are lies about a row that was never written
    /// — so a run that created nothing goes back to the form, carrying the
    /// reason it stopped.
    private func settleClosedSheet(message: String?) {
        if let conflictMessage {
            self.conflictMessage = nil
            Task { [weak self] in
                guard let self else { return }
                if let existing = await self.findOpenOffer() {
                    self.phase = .existing(existing)
                } else {
                    // The offer the 409 named could not be found — say why
                    // the sheet closed rather than dropping the buyer on an
                    // untouched form.
                    self.phase = .input
                    self.error = conflictMessage
                    A11y.announce(conflictMessage)
                }
            }
            return
        }

        guard offer != nil else {
            phase = .input
            let reason = lastRefusal?.message ?? message
            error = reason
            // The form is behind a sheet that just vanished, so nothing about
            // this line is on screen for VoiceOver to have moved to.
            if let reason { A11y.announce(reason) }
            return
        }
        phase = .holdIssue(message: message)
    }

    private func confirmHold() async {
        guard let offer else { return }
        do {
            let confirmed = try await commerce.confirmHold(offerID: offer.id)
            self.offer = confirmed
            lastRefusal = nil
            phase = .sent(confirmed)
        } catch {
            // The backstop. It reads the card that actually authorized, so by
            // the time it refuses, the money has stood on the card and been
            // released — and the sentence says so rather than pretending the
            // pre-check caught it.
            if let refusal = OfferHoldCardRefusal(error, origin: .afterAuthorization, holdText: holdText) {
                lastRefusal = refusal
                phase = .holdIssue(message: refusal.message)
                return
            }
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

/// The card sheet asked for an intent and there wasn't one to give it. Shown
/// by Stripe under its own form, so it reads as a sentence and not a code.
enum OfferHoldStartError: Error, LocalizedError {
    case unavailable

    var errorDescription: String? {
        "We couldn\u{2019}t start the card hold. Please try again."
    }
}
