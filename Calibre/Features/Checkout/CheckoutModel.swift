import CalibreKit
import Foundation
import Observation
import PassKit
import StripeApplePay
import StripePayments

/// Steps pushed inside the checkout's own NavigationStack. Shipping is the
/// stack root.
enum CheckoutStep: Hashable {
    case method
    case review
    case wire
}

/// The two ways to pay.
enum CheckoutMethod: Hashable {
    case card
    case wire
}

/// A refused card, thrown so it can travel out of the Apple Pay delegate as
/// an error while still carrying the backend's machine reason.
struct CardRefusalError: LocalizedError {
    let refusal: CardRefusal
    /// Filled in by whoever can reach the marketplace config; Apple Pay's
    /// sheet shows this string.
    let message: String

    var errorDescription: String? { message }
}

/// One watch in the checkout: the listing itself, and the server's own line
/// for it once the set has been priced.
struct CheckoutItem: Identifiable {
    let listingID: String
    var listing: Listing?
    var line: CheckoutBreakdownGroup.Item?

    var id: String { listingID }

    var title: String { listing?.title ?? "Your watch" }
    var imageURL: URL? { listing?.images.first?.url }

    /// The watch's own price — the server's line when the set is priced, the
    /// listing's price while it is still being priced.
    var priceText: String? {
        if let line {
            return PriceFormatter.format(line.subtotal.value, currency: line.currency)
        }
        guard let listing else { return nil }
        return PriceFormatter.format(listing.price.value, currency: listing.currency)
    }

    /// This watch's own shipping, from the server's line. Never a guess.
    var shippingText: String? {
        guard let line else { return nil }
        return PriceFormatter.format(line.shipping.value, currency: line.currency)
    }
}

/// One watch the server refused to reserve, so the buyer can be told which
/// one and offered the rest of their set.
struct ReservedWatch: Equatable {
    let listingID: String
    let title: String
}

/// Everything the checkout cover needs: the set of watches, the buyer's
/// addresses, server-priced breakdowns for both payment methods, the
/// funding-gated card payment, and the post-payment order materialization.
@MainActor
@Observable
final class CheckoutModel {
    /// The set as it stands. Shrinks by exactly one when the server refuses
    /// to reserve a watch and the buyer chooses to go on without it.
    private(set) var listingIDs: [String]
    let offerID: String?

    /// The set the cover opened with, so the success moment and the "we left
    /// one behind" copy can say what changed.
    private let requestedListingIDs: [String]

    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let checkout: CheckoutStore

    // MARK: Screen state

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// Where the payment has got to, so the pay bar can say something true
    /// rather than spinning anonymously.
    enum PayState: Equatable {
        case idle
        case readingCard
        case checkingCard
        case confirming
        case authenticating

        var isBusy: Bool { self != .idle }

        /// What the buyer is actually waiting on.
        var label: String? {
            switch self {
            case .idle: nil
            case .readingCard: "Reading your card…"
            case .checkingCard: "Checking your card…"
            case .confirming: "Taking payment…"
            case .authenticating: "Waiting on your bank…"
            }
        }
    }

    var phase: Phase = .loading
    var path: [CheckoutStep] = []

    /// Every listing this checkout has loaded, by id — including one that has
    /// since been dropped from the set, so it can still be named.
    private(set) var listingsByID: [String: Listing] = [:]
    var offer: Offer?

    /// The single watch, when there is exactly one. The screens that predate
    /// multi-item checkout read this and are right to.
    var listing: Listing? {
        guard listingIDs.count == 1, let id = listingIDs.first else { return nil }
        return listingsByID[id]
    }

    /// How many watches this checkout covers.
    var itemCount: Int { listingIDs.count }
    var isMultiItem: Bool { listingIDs.count > 1 }

    /// The set in order, each with its server line once the set is priced.
    var items: [CheckoutItem] {
        let lines = breakdownGroup?.items.reduce(into: [String: CheckoutBreakdownGroup.Item]()) {
            $0[$1.listingId] = $1
        }
        return listingIDs.map { id in
            CheckoutItem(listingID: id, listing: listingsByID[id], line: lines?[id])
        }
    }

    // MARK: Shipping

    var addresses: [Address] = []
    var selectedAddressID: String? {
        didSet {
            guard oldValue != selectedAddressID else { return }
            // Pricing (tax, shipping) depends on the destination — refetch.
            invalidatePricing()
        }
    }
    var showAddressForm = false
    var savingAddress = false
    var addressFormError: String?

    // MARK: Method + pricing

    var method: CheckoutMethod = .card
    private(set) var cardIntent: NativeCheckoutIntent?
    private(set) var pricingError: String?
    private(set) var pricingProblem: CheckoutProblem?
    private(set) var preparingCardIntent = false
    private(set) var wireCheckout: WireCheckout?
    private(set) var preparingWire = false

    // MARK: The wire deposit

    /// The $250 authorization behind this wire, once one has been placed.
    ///
    /// Kept for the life of the checkout on purpose: while it is live no new
    /// checkout may be opened, because a fresh checkout attempt mints a fresh
    /// hold and leaves this one sitting on the buyer's card until it expires
    /// (admin-contracts §11.6, binding).
    private(set) var wireHold: WireHold?
    /// The card gate refusing wire: no card on file, or one that is not a
    /// credit card. Both are 402s the buyer can act on.
    private(set) var wireCardRefusal: WireCardRefusal?
    private(set) var addingWireCard = false
    /// A challenge the buyer walked away from. The same intent is retried —
    /// never a new one.
    private(set) var wireHoldError: String?

    /// The watch the server would not reserve. Held separately from the
    /// pricing problem because the honest next step here isn't "try again" —
    /// it's "go on with the others".
    private(set) var reservedWatch: ReservedWatch?
    /// A watch the buyer chose to leave behind, so the set can say so once
    /// rather than silently shrinking.
    private(set) var droppedWatch: ReservedWatch?

    // MARK: Card entry

    /// Written by `CardEntryField`; nil until every field validates. Any
    /// change to it retires whatever the funding gate previously accepted —
    /// a different card is a different verdict.
    var cardParams: STPPaymentMethodCardParams? {
        didSet {
            validatedPaymentMethodID = nil
            cardCheckProblem = nil
        }
    }
    var cardIsValid = false

    /// The PaymentMethod the funding gate has already accepted. Created once,
    /// at card entry — while wire is still one tap away — and reused at
    /// confirm, so paying never creates a second PaymentMethod for the same
    /// card.
    private(set) var validatedPaymentMethodID: String?
    private(set) var checkingCardEntry = false
    /// A funding check that couldn't be completed (as opposed to one that
    /// said no). Retrying is honest advice here, so the view offers it.
    private(set) var cardCheckProblem: CheckoutProblem?

    /// The gate said yes to the card in the field.
    var cardAccepted: Bool { validatedPaymentMethodID != nil }

    // MARK: Payment

    private(set) var payState: PayState = .idle
    /// The funding gate said no. Shown inline, with wire one tap away.
    private(set) var cardRefusal: CardRefusal?
    private(set) var paymentProblem: CheckoutProblem?
    private(set) var confirmingOrder = false
    /// Every order the purchase materialized — one per watch.
    private(set) var completedOrders: [Order] = []

    /// The order the success moment leads with (and the one "View your order"
    /// opens). Nil until the purchase has materialized.
    var completedOrder: Order? { completedOrders.first }

    /// `STPPaymentHandler` and `STPApplePayContext` both keep only weak
    /// references to these, so the model owns them for the life of a payment.
    @ObservationIgnored private let authenticationContext = CheckoutAuthenticationContext()
    @ObservationIgnored private var applePayCheckout: ApplePayCheckout?
    @ObservationIgnored private var applePayContext: STPApplePayContext?

    init(
        listingIDs: [String],
        offerID: String?,
        catalog: CatalogStore,
        commerce: CommerceStore,
        client: APIClient
    ) {
        self.listingIDs = listingIDs
        self.requestedListingIDs = listingIDs
        self.offerID = offerID
        self.catalog = catalog
        self.commerce = commerce
        self.checkout = CheckoutStore(client: client)
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            async let addressesTask = commerce.loadAddresses()
            if let offerID {
                offer = try await commerce.offer(id: offerID)
            }
            async let listingsTask = loadListings(listingIDs)
            let (listings, addresses) = try await (listingsTask, addressesTask)
            for listing in listings {
                listingsByID[listing.id] = listing
            }
            self.addresses = addresses
            selectedAddressID = addresses.first(where: \.isDefaultShipping)?.id ?? addresses.first?.id
            showAddressForm = addresses.isEmpty
            phase = .ready
        } catch {
            phase = .failed(friendlyMessage(error))
        }
    }

    /// Every watch in the set, fetched together. One failure fails the load —
    /// a checkout that can't name what it is selling isn't one.
    private func loadListings(_ ids: [String]) async throws -> [Listing] {
        try await withThrowingTaskGroup(of: Listing.self) { group in
            for id in ids {
                group.addTask { [catalog] in try await catalog.listing(id: id) }
            }
            var loaded: [Listing] = []
            for try await listing in group {
                loaded.append(listing)
            }
            return loaded
        }
    }

    /// The amount being paid for the watches themselves — the accepted offer
    /// when one rides along, the set's own prices otherwise.
    var watchAmountText: String? {
        if let offer {
            return PriceFormatter.format(offer.amount.value, currency: offer.currency)
        }
        if let combined = breakdownGroup?.combined {
            return PriceFormatter.format(combined.subtotal.value, currency: combined.currency)
        }
        guard let listing else { return nil }
        return PriceFormatter.format(listing.price.value, currency: listing.currency)
    }

    var selectedAddress: Address? {
        addresses.first { $0.id == selectedAddressID }
    }

    /// The money for the purchase as a whole: the legacy single breakdown for
    /// one watch, the server's combined column for a set. Both are the
    /// server's own figures — nothing here is added up on the device.
    var breakdown: CheckoutBreakdown? {
        cardIntent?.payableBreakdown
    }

    /// The per-watch lines and the combined column, whichever way this
    /// checkout was priced.
    var breakdownGroup: CheckoutBreakdownGroup? {
        cardIntent?.breakdownGroup ?? wireCheckout?.breakdownGroup
    }

    /// The purchase the server grouped this checkout under, for the two
    /// events that carry it. Absent until the intent exists — and then
    /// omitted from the event rather than invented.
    var checkoutGroupID: String? {
        breakdownGroup?.checkoutGroupId
    }

    /// The hold a buyer forfeits by not paying an accepted offer. Only ever
    /// the offer's own figure — a number we don't have is a sentence without
    /// a number, never a remembered one.
    var offerHoldText: String? {
        guard let hold = offer?.hold else { return nil }
        return PriceFormatter.format(hold.amount.value, currency: hold.currency ?? offer?.currency ?? "USD")
    }

    // MARK: - Shipping step

    func createAddress(_ payload: AddressPayload) async {
        guard !savingAddress else { return }
        savingAddress = true
        addressFormError = nil
        defer { savingAddress = false }
        do {
            let address = try await commerce.createAddress(payload)
            addresses = commerce.addresses
            selectedAddressID = address.id
            showAddressForm = false
        } catch {
            addressFormError = friendlyMessage(error)
        }
    }

    func continueFromShipping() {
        guard selectedAddressID != nil else { return }
        path.append(.method)
        Task { await prepareCardIntent() }
    }

    // MARK: - Method step

    /// Prices the card path (and thereby the whole purchase). Fired when the
    /// method step appears so the fee difference can be shown in dollars.
    func prepareCardIntent() async {
        guard cardIntent == nil, !preparingCardIntent, let addressID = selectedAddressID else { return }
        guard !listingIDs.isEmpty else { return }
        preparingCardIntent = true
        pricingError = nil
        pricingProblem = nil
        reservedWatch = nil
        defer { preparingCardIntent = false }
        do {
            let intent = try await checkout.paymentIntent(
                listingIDs: listingIDs,
                shippingAddressID: addressID,
                offerID: offerID
            )
            cardIntent = intent
            STPAPIClient.shared.publishableKey = intent.publishableKey
            trackCheckoutStarted(.card, group: intent.breakdownGroup, breakdown: intent.breakdown)
        } catch {
            recordPricingFailure(error)
        }
    }

    /// The card cost in dollars, once the server has priced the purchase.
    var cardFeeText: String? {
        guard let breakdown else { return nil }
        return CheckoutCopy.cardFeeAmountText(breakdown)
    }

    func continueFromMethod() async {
        switch method {
        case .card:
            path.append(.review)
        case .wire:
            await startWire()
        }
    }

    /// "Actually, pay by wire" — reachable from the review step, after the
    /// buyer has seen exactly what the card costs.
    func switchToWire() async {
        method = .wire
        clearCardEntry()
        await startWire()
    }

    /// Opens the wire path, deposit first.
    ///
    /// Choosing wire is a statement that the buyer is buying the watch, and
    /// the $250 authorization is where they make it — so the hold is placed
    /// before the bank details exist. Two things follow from that, and both
    /// are binding:
    ///
    /// * a wire checkout is opened exactly once. While a hold is live the
    ///   existing checkout is re-shown rather than re-created, because a new
    ///   attempt mints a second authorization and abandons the first on the
    ///   buyer's card until it expires;
    /// * a `requires_action` hold is confirmed *on that same intent* and the
    ///   flow carries on with the instructions already in hand.
    private func startWire() async {
        if wireCheckout != nil {
            if path.last != .wire { path.append(.wire) }
            return
        }
        guard !preparingWire, let addressID = selectedAddressID, !listingIDs.isEmpty else { return }
        preparingWire = true
        pricingError = nil
        pricingProblem = nil
        wireCardRefusal = nil
        wireHoldError = nil
        reservedWatch = nil
        defer { preparingWire = false }
        do {
            let wire = try await checkout.wireCheckout(
                listingIDs: listingIDs,
                shippingAddressID: addressID,
                offerID: offerID
            )
            wireCheckout = wire
            // An accepted offer's own deposit already stands behind this
            // wire, in which case the server sends no hold and none is placed.
            if let hold = wire.wireHold {
                wireHold = hold
                if hold.requiresAction {
                    await confirmWireHoldChallenge()
                }
            }
            trackCheckoutStarted(.wire, group: wire.breakdownGroup, breakdown: wire.breakdown)
            path.append(.wire)
        } catch let apiError as APIError {
            if case .server(let message, let code, 402, _) = apiError,
               let refusal = WireCardRefusal(code: code, serverMessage: message) {
                wireCardRefusal = refusal
                return
            }
            recordPricingFailure(apiError)
        } catch {
            recordPricingFailure(error)
        }
    }

    /// Confirms the hold's own PaymentIntent. Nothing is re-created here: the
    /// wire checkout in hand already carries the bank instructions, and the
    /// only thing outstanding is the issuer's challenge.
    func confirmWireHoldChallenge() async {
        guard let secret = wireHold?.clientSecret else { return }
        wireHoldError = nil
        // The wire path can reach a challenge without a card ever having been
        // priced, so the SDK is keyed from the hold's own payload rather than
        // from whatever a card intent happened to leave behind.
        if let key = wireHold?.publishableKey {
            STPAPIClient.shared.publishableKey = key
        }
        do {
            try await handleNextAction(clientSecret: secret)
        } catch {
            wireHoldError = (error as? LocalizedError)?.errorDescription
                ?? "Your bank didn\u{2019}t approve the $250 authorization. Try the check again."
        }
    }

    /// Adds a credit card through the account's own saved-card flow, then
    /// tries wire again. Reached only from a 402 — no hold has been placed at
    /// that point, so opening the checkout afresh costs nothing.
    func addCardForWire(presentSheet: @escaping (BillingSetupIntent) async -> Bool) async {
        guard !addingWireCard else { return }
        addingWireCard = true
        defer { addingWireCard = false }
        do {
            let intent = try await commerce.setupIntent()
            guard await presentSheet(intent) else { return }
            wireCardRefusal = nil
            await startWire()
        } catch {
            wireCardRefusal = WireCardRefusal(
                code: "wire_card_required",
                serverMessage: friendlyMessage(error)
            )
        }
    }

    func dismissWireCardRefusal() {
        wireCardRefusal = nil
    }

    // MARK: - A watch someone else is checking out

    /// Reads a pricing failure. A reserved watch in a set of several is not a
    /// dead end — it names the watch so the buyer can be offered the rest.
    private func recordPricingFailure(_ error: Error) {
        let problem = CheckoutCopy.problem(for: error)
        if problem.listingReserved, let id = problem.reservedListingID ?? soleListingID {
            reservedWatch = ReservedWatch(listingID: id, title: title(of: id))
        }
        pricingProblem = problem
        pricingError = problem.message
    }

    /// In a checkout of one there is only one watch a 409 can be about, so a
    /// payload without an id still names it correctly.
    private var soleListingID: String? {
        listingIDs.count == 1 ? listingIDs.first : nil
    }

    func title(of listingID: String) -> String {
        listingsByID[listingID]?.title ?? "that watch"
    }

    /// Whether dropping the refused watch still leaves something to buy.
    var canContinueWithoutReservedWatch: Bool {
        guard let reservedWatch else { return false }
        return listingIDs.contains(reservedWatch.listingID) && listingIDs.count > 1
    }

    /// "Go on without it" — drops the refused watch and re-prices the rest.
    /// The server is asked again from scratch; nothing about the old quote
    /// carries over.
    func continueWithoutReservedWatch() async {
        guard let reservedWatch, canContinueWithoutReservedWatch else { return }
        listingIDs.removeAll { $0 == reservedWatch.listingID }
        droppedWatch = reservedWatch
        self.reservedWatch = nil
        invalidatePricing()
        pricingError = nil
        pricingProblem = nil
        switch method {
        case .card:
            await prepareCardIntent()
        case .wire:
            await startWire()
        }
    }

    func dismissDroppedWatchNote() {
        droppedWatch = nil
    }

    /// Everything the server priced is stale — a new destination, or a new
    /// set. Both quotes go, so neither can be paid against.
    private func invalidatePricing() {
        cardIntent = nil
        // A wire checkout with a live authorization behind it is never thrown
        // away: re-opening one would place a second $250 on the buyer's card
        // and strand the first (admin-contracts §11.6, binding).
        if wireHold == nil {
            wireCheckout = nil
        }
        pricingError = nil
        clearCardEntry()
    }

    // MARK: - Review & pay (card)

    /// Paying is only offered once the funding gate has accepted the card in
    /// the field. A card nobody has checked is never one tap from a charge.
    var canPayWithCard: Bool {
        cardIntent != nil && cardAccepted && !payState.isBusy && !confirmingOrder && !checkingCardEntry
    }

    /// The funding check, run the moment a complete card is in the field —
    /// while wire is still one tap away, and before the Pay button is live.
    ///
    /// A refusal lands inline here rather than after a submission the buyer
    /// thought had succeeded. The accepted PaymentMethod is kept so paying
    /// reuses it instead of creating a second one for the same card.
    func validateEnteredCard() async {
        guard let params = cardParams, cardIntent != nil else { return }
        guard !checkingCardEntry, !payState.isBusy, !confirmingOrder else { return }
        checkingCardEntry = true
        cardRefusal = nil
        cardCheckProblem = nil
        paymentProblem = nil
        defer { checkingCardEntry = false }

        do {
            let paymentMethodID = try await createPaymentMethodID(params)
            let validation = try await checkout.validatePaymentMethod(
                listingIDs: listingIDs,
                paymentMethodID: paymentMethodID
            )
            guard validation.accepted else {
                cardRefusal = CardRefusal(code: validation.reason, serverMessage: nil)
                return
            }
            // The card the gate accepted may already have been replaced by a
            // newer one — that write cleared the id, and this verdict is no
            // longer about what is on screen.
            guard cardParams === params else { return }
            validatedPaymentMethodID = paymentMethodID
        } catch {
            guard cardParams === params else { return }
            cardCheckProblem = CheckoutCopy.problem(for: error)
        }
    }

    /// The whole card path from an accepted card: let the server confirm,
    /// answer a 3-D Secure challenge if one comes back, then materialize. The
    /// funding gate already ran at card entry and its PaymentMethod is reused.
    func payWithCard() async {
        guard let intent = cardIntent,
              let paymentMethodID = validatedPaymentMethodID,
              !payState.isBusy else { return }
        cardRefusal = nil
        paymentProblem = nil

        do {
            let clientSecret = try await confirmAccepted(
                paymentMethodID: paymentMethodID,
                paymentIntentID: intent.paymentIntent.id
            )
            if let clientSecret {
                payState = .authenticating
                try await handleNextAction(clientSecret: clientSecret)
            }
            payState = .idle
            await materializeOrders()
        } catch let refusal as CardRefusalError {
            payState = .idle
            cardRefusal = refusal.refusal
        } catch {
            payState = .idle
            paymentProblem = CheckoutCopy.problem(for: error)
        }
    }

    /// Turns a validated card into a Stripe PaymentMethod. Only the id
    /// crosses back — the PaymentMethod object itself never leaves the
    /// callback.
    private func createPaymentMethodID(_ card: STPPaymentMethodCardParams) async throws -> String {
        let params = STPPaymentMethodParams(card: card, billingDetails: nil, metadata: nil)
        return try await withCheckedThrowingContinuation { continuation in
            STPAPIClient.shared.createPaymentMethod(with: params) { method, error in
                if let id = method?.stripeId {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(
                        throwing: error ?? CheckoutMessageError(
                            message: "We couldn't read that card. Please check the details and try again."
                        )
                    )
                }
            }
        }
    }

    /// The funding gate, then the server's confirmation.
    ///
    /// Validation runs the moment the PaymentMethod exists — while wire is
    /// still one tap away — and the server enforces the same rule again on
    /// confirm, which is why a 402 there is read as the same refusal rather
    /// than as a generic failure.
    ///
    /// Returns a client secret only when a challenge is owed.
    private func gateThenConfirm(paymentMethodID: String, paymentIntentID: String) async throws -> String? {
        payState = .checkingCard
        let validation = try await checkout.validatePaymentMethod(
            listingIDs: listingIDs,
            paymentMethodID: paymentMethodID
        )
        guard validation.accepted else {
            throw refusalError(code: validation.reason, serverMessage: nil)
        }
        return try await confirmAccepted(
            paymentMethodID: paymentMethodID,
            paymentIntentID: paymentIntentID
        )
    }

    /// The server's confirmation of an already-accepted PaymentMethod. The
    /// server enforces the funding rule again here, which is why a 402 is read
    /// as the same refusal rather than as a generic failure.
    private func confirmAccepted(paymentMethodID: String, paymentIntentID: String) async throws -> String? {
        payState = .confirming
        let confirmation: CheckoutConfirmation
        do {
            confirmation = try await checkout.confirm(
                paymentIntentID: paymentIntentID,
                paymentMethodID: paymentMethodID
            )
        } catch let apiError as APIError {
            if case .server(let message, let code, 402, _) = apiError {
                throw refusalError(code: code, serverMessage: message)
            }
            throw apiError
        }

        guard confirmation.requiresAction else { return nil }
        return confirmation.clientSecret
    }

    /// 3-D Secure. The status is mapped to a plain outcome before it crosses
    /// back, so nothing non-Sendable rides the continuation.
    private func handleNextAction(clientSecret: String) async throws {
        enum Outcome: Sendable {
            case succeeded
            case canceled
            case failed(String)
        }

        let outcome: Outcome = await withCheckedContinuation { continuation in
            STPPaymentHandler.shared().handleNextAction(
                forPayment: clientSecret,
                with: authenticationContext,
                returnURL: CalibreStripe.returnURL
            ) { status, _, error in
                switch status {
                case .succeeded:
                    continuation.resume(returning: .succeeded)
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed:
                    continuation.resume(
                        returning: .failed(
                            error.map { CalibreStripe.failureMessage(for: $0) }
                                ?? "Your bank didn't approve this payment. Please try again."
                        )
                    )
                @unknown default:
                    continuation.resume(returning: .failed("Your payment didn't go through. Please try again."))
                }
            }
        }

        switch outcome {
        case .succeeded:
            return
        case .canceled:
            throw CheckoutMessageError(
                message: "You cancelled the check with your bank, so nothing was charged."
            )
        case .failed(let message):
            throw CheckoutMessageError(message: message)
        }
    }

    private func refusalError(code: String?, serverMessage: String?) -> CardRefusalError {
        let refusal = CardRefusal(code: code, serverMessage: serverMessage)
        return CardRefusalError(
            refusal: refusal,
            // Apple Pay's sheet can only show a string, and it has no access
            // to the marketplace config, so the states clause is dropped
            // there rather than guessed at. The inline card path re-renders
            // the same refusal with the states named.
            message: CheckoutCopy.refusalMessage(refusal, statesText: nil)
        )
    }

    /// Clears a refused or abandoned card so the next attempt starts clean.
    func clearCardEntry() {
        // Writing `cardParams` also retires the accepted PaymentMethod.
        cardParams = nil
        cardIsValid = false
        cardRefusal = nil
        cardCheckProblem = nil
    }

    func dismissPaymentProblem() {
        paymentProblem = nil
    }

    // MARK: - Apple Pay

    var canOfferApplePay: Bool {
        CalibreStripe.canOfferApplePay && cardIntent != nil
    }

    /// Raises the wallet. Everything after the buyer authorizes runs through
    /// `ApplePayCheckout` into the same gate the card form uses.
    func startApplePay() {
        guard let breakdown, canOfferApplePay else { return }
        cardRefusal = nil
        paymentProblem = nil

        let request = CalibreStripe.applePayRequest(
            currency: breakdown.currency,
            summaryItems: applePaySummaryItems(breakdown)
        )
        let delegate = ApplePayCheckout(model: self)
        applePayCheckout = delegate
        guard let context = STPApplePayContext(paymentRequest: request, delegate: delegate) else {
            paymentProblem = CheckoutProblem(
                message: "Apple Pay isn't available for this order. You can pay by card or by wire."
            )
            return
        }
        applePayContext = context
        context.presentApplePay()
    }

    /// Every line already priced by the server. Nothing here adds up to a
    /// total — the total is the server's `grand_total`, shown as the last item
    /// because that is the one Apple charges. A purchase of several watches
    /// lists each one, so the wallet sheet says what is being bought.
    private func applePaySummaryItems(_ breakdown: CheckoutBreakdown) -> [PKPaymentSummaryItem] {
        var items: [PKPaymentSummaryItem] = []
        let lines = breakdownGroup?.items ?? []
        if isMultiItem, lines.count == listingIDs.count {
            for line in lines {
                items.append(
                    PKPaymentSummaryItem(
                        label: listingsByID[line.listingId]?.title ?? "Watch",
                        amount: NSDecimalNumber(decimal: line.subtotal.value)
                    )
                )
            }
        } else {
            items.append(
                PKPaymentSummaryItem(
                    label: offerID == nil ? "Watch" : "Your accepted offer",
                    amount: NSDecimalNumber(decimal: breakdown.subtotal.value)
                )
            )
        }
        items.append(
            PKPaymentSummaryItem(
                label: "Shipping",
                amount: NSDecimalNumber(decimal: breakdown.shipping.value)
            )
        )
        if let fee = CheckoutCopy.cardFeeAmount(breakdown), fee > 0 {
            items.append(
                PKPaymentSummaryItem(label: "Card processing", amount: NSDecimalNumber(decimal: fee))
            )
        }
        if let tax = breakdown.tax?.value, tax > 0 {
            items.append(PKPaymentSummaryItem(label: "Tax", amount: NSDecimalNumber(decimal: tax)))
        }
        items.append(
            PKPaymentSummaryItem(
                label: CalibreStripe.merchantDisplayName,
                amount: NSDecimalNumber(decimal: breakdown.grandTotal.value)
            )
        )
        return items
    }

    /// The wallet's PaymentMethod, put through exactly the gate a typed card
    /// goes through. Returns the client secret Stripe needs to close its
    /// sheet; throws so a refusal shows inside the sheet rather than behind it.
    func authorizeWalletPayment(paymentMethodID: String) async throws -> String {
        guard let intent = cardIntent else { throw CheckoutMessageError.lost }
        _ = try await gateThenConfirm(
            paymentMethodID: paymentMethodID,
            paymentIntentID: intent.paymentIntent.id
        )
        payState = .idle
        return intent.paymentIntent.clientSecret
    }

    func applePayFinished(succeeded: Bool, error: Error?) {
        applePayCheckout = nil
        applePayContext = nil
        payState = .idle

        guard succeeded else {
            if let refusal = error as? CardRefusalError {
                cardRefusal = refusal.refusal
            } else if let error {
                paymentProblem = CheckoutCopy.problem(for: error)
            }
            // A plain cancel says nothing — the buyer changed their mind.
            return
        }
        Task { await materializeOrders() }
    }

    // MARK: - Order materialization

    /// Quiet "Confirming your order…" poll of /orders/from-payment-intent.
    /// The webhook can win the race — already-created orders return 200 and
    /// are equally a success. 402 means the payment is still settling.
    ///
    /// A purchase of several watches materializes one order per watch, and
    /// they can land one at a time, so this polls until the count matches the
    /// set that was paid for rather than stopping at the first 200.
    private func materializeOrders() async {
        guard let intent = cardIntent else { return }
        confirmingOrder = true
        defer { confirmingOrder = false }

        let expected = listingIDs.count
        let deadline = Date.now.addingTimeInterval(15)
        var partial: [Order] = []

        while true {
            do {
                let result = try await checkout.orderFromPaymentIntent(
                    paymentIntentID: intent.paymentIntent.id
                )
                partial = result.orders
                if result.count >= expected {
                    finish(with: result.orders, paymentMethod: .card)
                    return
                }
                // Fewer orders than watches: the rest are still being written.
                if Date.now >= deadline {
                    // Some of the purchase exists. Showing it is truer than
                    // showing an error about a payment that went through.
                    finish(with: partial, paymentMethod: .card)
                    return
                }
            } catch let error as APIError {
                if case .server(_, _, let status, _) = error, status != 402, status < 500 {
                    // Terminal server verdict (refunded races, forbidden) —
                    // stop polling and show the backend's own message.
                    giveUp(partial, message: error.localizedDescription)
                    return
                }
                if Date.now >= deadline {
                    giveUp(partial, message: Self.settlingMessage)
                    return
                }
            } catch {
                if Date.now >= deadline {
                    giveUp(partial, message: Self.settlingMessage)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

    /// The purchase is real. Recorded once — the poll above returns on the
    /// first call that gets here — and one `purchase_completed` per order.
    private func finish(with orders: [Order], paymentMethod: Analytics.PaymentMethod) {
        guard completedOrders.isEmpty, !orders.isEmpty else { return }
        completedOrders = orders
        trackPurchaseCompleted(orders, paymentMethod: paymentMethod)
    }

    /// The poll ran out. Orders that did materialize are still the buyer's,
    /// so they are shown rather than thrown away in favour of an error about
    /// a payment that went through.
    private func giveUp(_ partial: [Order], message: String) {
        if !partial.isEmpty {
            finish(with: partial, paymentMethod: .card)
            return
        }
        paymentProblem = CheckoutProblem(message: message, retryable: false)
    }

    private static let settlingMessage =
        "Your payment went through, but we couldn't confirm the order just yet. It will appear in your orders shortly."

    // MARK: - Wire path

    private(set) var sendingWireReservation = false

    /// "I've sent the wire" — one transfer covers the whole purchase, so this
    /// is said once and creates every awaiting-wire order in the group. Hands
    /// back the orders so the view can route to the first one.
    func confirmWireSent() async -> [Order] {
        guard let wire = wireCheckout, !sendingWireReservation else { return [] }
        sendingWireReservation = true
        defer { sendingWireReservation = false }
        do {
            let result = try await checkout.wireReservation(paymentIntentID: wire.wire.paymentIntentId)
            // An awaiting-wire order is not a completed purchase — no money
            // has moved yet — so nothing is emitted here. `purchase_completed`
            // fires when the transfer lands and the order is paid.
            return result.orders
        } catch {
            let problem = CheckoutCopy.problem(for: error)
            pricingProblem = problem
            pricingError = problem.message
            return []
        }
    }

    // MARK: - Analytics

    /// Listing-shaped analytics properties for one watch in the set. Per the
    /// schema, an accepted offer bands by the agreed amount rather than the
    /// list price.
    private func analyticsListing(_ listingID: String) -> Analytics.ListingInfo {
        let info = listingsByID[listingID].map(Analytics.ListingInfo.init) ?? .init(id: listingID)
        return offer.map { info.priced(at: $0.amount.value) } ?? info
    }

    /// One `checkout_started` **per watch**, each with its own `event_id`,
    /// all carrying the same `checkout_group_id`. A checkout covering three
    /// watches emits three events — an event that sometimes means one watch
    /// and sometimes three could not answer a per-watch question.
    ///
    /// `pricing_mode` comes from the breakdown the server priced; an
    /// `unknown` mode (a wire format this build predates) is omitted rather
    /// than guessed, so the event goes out without it.
    private func trackCheckoutStarted(
        _ paymentMethod: Analytics.PaymentMethod,
        group: CheckoutBreakdownGroup?,
        breakdown: CheckoutBreakdown?
    ) {
        let groupID = group?.checkoutGroupId
        let lines = group?.items.reduce(into: [String: CheckoutBreakdownGroup.Item]()) {
            $0[$1.listingId] = $1
        }
        for listingID in listingIDs {
            let mode = lines?[listingID]?.pricingMode ?? group?.combined?.pricingMode ?? breakdown?.pricingMode
            Analytics.checkoutStarted(
                analyticsListing(listingID),
                paymentMethod: paymentMethod,
                pricingMode: Self.pricingMode(mode),
                fromOffer: offerID != nil,
                checkoutGroupID: groupID
            )
        }
    }

    /// One `purchase_completed` **per order**, each with its own `event_id`
    /// and its own `value` — that order's grand total, exactly as the API
    /// reports it, including its allocated share of the single card fee.
    /// Summing `value` across the group is what the buyer paid, and that only
    /// holds if each event carries its own share.
    private func trackPurchaseCompleted(_ orders: [Order], paymentMethod: Analytics.PaymentMethod) {
        for order in orders {
            Analytics.purchaseCompleted(
                orderID: order.id,
                listing: analyticsListing(order.listingId),
                paymentMethod: paymentMethod,
                value: order.grandTotal.value,
                checkoutGroupID: order.checkoutGroupId ?? checkoutGroupID
            )
        }
    }

    private static func pricingMode(_ mode: CheckoutBreakdown.PricingMode?) -> Analytics.PricingMode? {
        switch mode {
        case .surcharge: .surcharge
        case .discount: .discount
        case .unknown, nil: nil
        }
    }

    // MARK: - Helpers

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
