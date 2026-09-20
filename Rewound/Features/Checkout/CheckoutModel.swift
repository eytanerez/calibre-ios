import RewoundKit
import Foundation
import Observation
import StripePayments
import StripePaymentSheet

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

/// A refused card, thrown so it can travel out of PaymentSheet's deferred
/// confirm handler as an error while still carrying the backend's machine
/// reason. The handler runs after the buyer taps Pay inside Stripe's own
/// sheet, so this is also what the sheet shows them: `errorDescription`
/// names the way out (credit cards only, wire at any price) because there is
/// no button beside it to say so instead.
struct CardRefusalError: LocalizedError {
    let refusal: CardRefusal
    let message: String

    var errorDescription: String? { message }
}

/// A failure carrying copy we already wrote. PaymentSheet surfaces the
/// thrown error's description inside its own sheet, so refusals have to
/// travel as errors rather than as state the sheet can't see.
struct CheckoutMessageError: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    static let lost = CheckoutMessageError(
        message: "We lost track of this checkout. Please start again."
    )
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

    /// Wire is the default, and the method cards list it first to match. The
    /// default is safe to change on its own here because nothing acts on it
    /// until `continueFromMethod()` — the deposit is placed by that tap, not
    /// by the selection, which is why iOS needs no second "committed" variable
    /// the way the website does.
    var method: CheckoutMethod = .wire
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
    /// Whether this checkout has already promoted a card the buyer owns in
    /// answer to "you need a credit card on file". One attempt per checkout.
    @ObservationIgnored private var triedPromotingOwnedCard = false
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

    // MARK: Payment

    private(set) var paymentProblem: CheckoutProblem?
    private(set) var confirmingOrder = false
    /// Every order the purchase materialized — one per watch.
    private(set) var completedOrders: [Order] = []

    /// The order the success moment leads with (and the one "View your order"
    /// opens). Nil until the purchase has materialized.
    var completedOrder: Order? { completedOrders.first }

    /// `STPPaymentHandler` keeps only a weak reference to this, so the model
    /// owns it for the life of a payment.
    @ObservationIgnored private let authenticationContext = CheckoutAuthenticationContext()
    /// Stripe holds this weakly once presented, so the model owns it for the
    /// life of the sheet.
    @ObservationIgnored private var paymentSheet: PaymentSheet?
    /// True from `presentPaymentSheet()` until the sheet reports a result —
    /// the guard against a second tap while Stripe's own sheet is up, and
    /// what disables "Pay by wire instead" while a card payment is in flight.
    private(set) var presentingPaymentSheet = false

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
            // Before the intent is kept, not after. Everything the card path
            // draws hangs off `cardIntent` — the breakdown, the Pay button,
            // the sheet it opens — and every one of them would be a promise
            // the SDK cannot keep if the server named no account. Failing
            // here puts the reason on screen; keeping the intent would put a
            // Pay button on screen whose sheet silently 401s at the tap.
            guard RewoundStripe.useKey(intent.publishableKey) else {
                recordPricingFailure(RewoundStripe.unkeyedFailure)
                return
            }
            cardIntent = intent
            trackCheckoutStarted(.card, group: intent.breakdownGroup, breakdown: intent.breakdown)
        } catch {
            recordPricingFailure(error)
            return
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
            // The review step has no pricing trigger of its own — it renders
            // the total or, failing that, a retry it only draws once a
            // `pricingProblem` exists. Arriving unpriced it would draw a
            // skeleton and nothing else, so the price is asked for here. A
            // no-op when the method step's own attempt already succeeded, and
            // it moves no money either way.
            await prepareCardIntent()
        case .wire:
            await startWire()
        }
    }

    /// "Actually, pay by wire" — reachable from the review step, after the
    /// buyer has seen exactly what the card costs.
    func switchToWire() async {
        method = .wire
        await startWire()
        // The card gate can refuse wire, and everything a buyer can do about
        // that — the message for each code, "Add a credit card", "Pay by card
        // instead" — lives on the method step. Refused from the review step,
        // the refusal would be state nothing on screen renders, and the button
        // would look broken. Step back to where the answer is.
        if wireCardRefusal != nil, path.last == .review {
            path = [.method]
        }
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
        guard !preparingWire, selectedAddressID != nil, !listingIDs.isEmpty else { return }
        await openWireCheckout()

        // "You need a credit card on file" is sometimes about our own record
        // of which card is the buyer's, not about anything they have to do:
        // the gate reads the account's *default* card, and a card saved
        // through checkout or a sheet can sit in the wallet with that field
        // never written. Being asked to add a card you are looking at on your
        // own payment screen is not an honest refusal, so before showing it,
        // promote what they already own and ask again. Once — a second round
        // against a server that keeps saying no is a loop, not a retry.
        //
        // Safe at exactly this point and nowhere else: the card gate runs
        // before the deposit is placed, so no authorization exists yet and
        // re-opening costs the buyer nothing (contracts §11.6).
        guard wireCardRefusal?.offersAddCard == true, !triedPromotingOwnedCard else { return }
        triedPromotingOwnedCard = true
        guard await promoteOwnedCard() else { return }
        wireCardRefusal = nil
        await openWireCheckout()
    }

    /// Makes a card the buyer already owns the one the deposit is placed on.
    ///
    /// A one-line server write, and the server still judges the funding
    /// afterwards — a promoted debit card is refused on the next attempt with
    /// `wire_card_must_be_credit`, which is the true answer.
    private func promoteOwnedCard() async -> Bool {
        do {
            let wallet = try await commerce.wallet()
            let spendable = wallet.spendableCards
            // Never the guarantee card: the deposit has to sit on a card the
            // buyer chose to spend from.
            let card = spendable.first { $0.id == wallet.defaultPaymentMethodId } ?? spendable.first
            guard let card else { return false }
            try await commerce.makeCardDefault(id: card.id)
            return true
        } catch {
            return false
        }
    }

    /// One attempt at opening the wire checkout.
    private func openWireCheckout() async {
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
        // from whatever a card intent happened to leave behind. A payload that
        // names no account is only fatal when nothing else has keyed the SDK
        // either — and it is fatal, because `handleNextAction` against an
        // unkeyed client fails with Stripe's own wording, which reads to a
        // buyer as their bank refusing them.
        if !RewoundStripe.useKey(wireHold?.publishableKey), !RewoundStripe.isKeyed {
            wireHoldError = RewoundStripe.unkeyedFailure.message
            return
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
            // The account's default card is written by the
            // `setup_intent.succeeded` webhook, and asking for wire again the
            // instant the sheet closes races it — the buyer is told a second
            // time to add the card they have just added. Promoting what the
            // wallet now holds settles it in a round trip we control, and the
            // server still judges the funding on the retry.
            _ = await promoteOwnedCard()
            // Already resolved by hand; the retry inside `startWire` would
            // only repeat this.
            triedPromotingOwnedCard = true
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

        // Whether the buyer had actually OPENED a wire, read before
        // `invalidatePricing()` throws it away. This is not the same question
        // as `method`, and the difference became dangerous the day wire became
        // the default: `method` is merely what is selected, so a buyer who has
        // not reached the payment step at all still reads as `.wire`, and
        // resuming on that would call `startWire()` and place a $250
        // authorization on a card for a step they never asked for. Recovering
        // from a watch going out of stock must not move money.
        let wasPayingByWire = wireCheckout != nil || wireHold != nil

        listingIDs.removeAll { $0 == reservedWatch.listingID }
        droppedWatch = reservedWatch
        self.reservedWatch = nil
        invalidatePricing()
        pricingError = nil
        pricingProblem = nil

        // The button says the purchase will be priced again, so it always is.
        // This is only reachable from a pricing failure, which means the buyer
        // is already standing on the method step or past it and there is no
        // "earlier step" to fall back to: leaving without a quote strands them
        // on a skeleton with no total and no retry.
        //
        // Wire resumes wire — `startWire` re-shows a live authorization rather
        // than minting a second one. Everybody else prices the card path,
        // which is exactly what the method step does on its own and moves no
        // money.
        if wasPayingByWire {
            await startWire()
        } else {
            await prepareCardIntent()
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
    }

    // MARK: - Review & pay (card)

    /// Paying is offered once the purchase is priced. The funding gate no
    /// longer runs before this button lights up — it runs inside Stripe's
    /// own sheet, in `confirmForPaymentSheet`, the moment the buyer taps its
    /// Pay button.
    var canPayWithCard: Bool {
        cardIntent != nil && !presentingPaymentSheet && !confirmingOrder
    }

    /// Whether this checkout is priced against a Stripe test key. Derived
    /// from the key the server priced it with, never from `#if DEBUG` — a
    /// debug build pointed at live keys must stay quiet, and a TestFlight
    /// build pointed at test keys (the beta program) still has to warn a
    /// tester before they authorize a real-looking total.
    var isTestModePayment: Bool {
        RewoundStripe.isTestKey(cardIntent?.publishableKey)
    }

    /// Presents Stripe's PaymentSheet against the priced intent, using its
    /// deferred-confirmation flow: Stripe hands `confirmForPaymentSheet` a
    /// full `STPPaymentMethod` and no money moves until it hands back a
    /// client secret. That is what keeps the funding gate alive now that it
    /// no longer runs at a card field of our own — it runs the moment the
    /// buyer taps Pay inside Stripe's sheet, and a refusal is shown right
    /// there, with wire still one tap away outside it.
    ///
    /// Apple Pay lives inside this same sheet — `RewoundStripe.configuration`
    /// attaches it whenever the build and device both support it — so
    /// tapping it calls this exact same confirm handler rather than a path
    /// of its own.
    func presentPaymentSheet() {
        guard canPayWithCard, let intent = cardIntent else { return }
        guard let amount = Self.minorUnits(intent.payableBreakdown?.grandTotal.value) else {
            paymentProblem = CheckoutProblem(message: "We couldn't price this purchase. Please try again.")
            return
        }
        paymentProblem = nil

        let intentConfiguration = PaymentSheet.IntentConfiguration(
            mode: .payment(
                amount: amount,
                currency: (intent.payableBreakdown?.currency ?? "usd").lowercased()
            ),
            confirmHandler: { [weak self] paymentMethod, _ in
                guard let self else { throw CheckoutMessageError.lost }
                return try await self.confirmForPaymentSheet(paymentMethodID: paymentMethod.stripeId)
            }
        )
        let sheet = PaymentSheet(
            intentConfiguration: intentConfiguration,
            configuration: RewoundStripe.configuration(
                customerID: intent.customerId,
                customerSessionClientSecret: intent.customerSessionClientSecret
            )
        )
        paymentSheet = sheet
        presentingPaymentSheet = true
        RewoundStripe.present(sheet) { [weak self] result in
            self?.handlePaymentSheetResult(result)
        }
    }

    /// The gate, then the server's confirmation — the exact pipeline a saved
    /// or typed card used to run before Pay went live, reused rather than
    /// duplicated. A refusal throws, so PaymentSheet shows it inside the
    /// sheet with wire still one tap away outside it.
    func confirmForPaymentSheet(paymentMethodID: String) async throws -> String {
        guard let intent = cardIntent else { throw CheckoutMessageError.lost }
        _ = try await gateThenConfirm(paymentMethodID: paymentMethodID, paymentIntentID: intent.paymentIntent.id)
        return intent.paymentIntent.clientSecret
    }

    /// Where `RewoundStripe.present` hands the sheet's outcome back. A
    /// refusal the confirm handler threw is already shown inside the sheet
    /// by this point — `.failed` here is an SDK-level failure outside our
    /// own control, so it gets the same generic handling any other payment
    /// failure gets.
    private func handlePaymentSheetResult(_ result: PaymentSheetResult) {
        presentingPaymentSheet = false
        paymentSheet = nil
        switch result {
        case .completed:
            Task { await materializeOrders() }
        case .canceled:
            break
        case .failed(let error):
            paymentProblem = CheckoutCopy.problem(for: error)
        }
    }

    /// The purchase total in the smallest currency unit `IntentConfiguration`
    /// wants. Straight from the server's own `grand_total` — never
    /// remembered, never recomputed from a formatted string.
    private static func minorUnits(_ amount: Decimal?) -> Int? {
        guard let amount, amount > 0 else { return nil }
        var scaled = amount * 100
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)
        let cents = NSDecimalNumber(decimal: whole).intValue
        return cents > 0 ? cents : nil
    }

    /// The funding gate, then the server's confirmation.
    ///
    /// Validation runs the moment PaymentSheet hands over a PaymentMethod —
    /// the moment the buyer taps its own Pay button — and the server
    /// enforces the same rule again on confirm, which is why a 402 there is
    /// read as the same refusal rather than as a generic failure.
    ///
    /// Returns a client secret only when a challenge is owed.
    private func gateThenConfirm(paymentMethodID: String, paymentIntentID: String) async throws -> String? {
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

    /// 3-D Secure for the wire deposit's own PaymentIntent — PaymentSheet
    /// handles the card path's challenges internally once its confirm
    /// handler hands back a client secret, so this is what the wire hold
    /// still calls directly. The status is mapped to a plain outcome before
    /// it crosses back, so nothing non-Sendable rides the continuation.
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
                returnURL: RewoundStripe.returnURL
            ) { status, _, error in
                switch status {
                case .succeeded:
                    continuation.resume(returning: .succeeded)
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed:
                    continuation.resume(
                        returning: .failed(
                            error.map { RewoundStripe.failureMessage(for: $0) }
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
                message: "You canceled the check with your bank, so nothing was charged."
            )
        case .failed(let message):
            throw CheckoutMessageError(message: message)
        }
    }

    /// A refused card, said warmly and plainly, naming the way out. Read by
    /// PaymentSheet, which shows `errorDescription` inside its own sheet and
    /// leaves it open for another card.
    private func refusalError(code: String?, serverMessage: String?) -> CardRefusalError {
        let refusal = CardRefusal(code: code, serverMessage: serverMessage)
        return CardRefusalError(
            refusal: refusal,
            message: CheckoutCopy.refusalMessage(refusal)
        )
    }

    func dismissPaymentProblem() {
        paymentProblem = nil
    }

    // MARK: - Apple Pay

    /// Whether the sheet the Pay button opens can promise Apple Pay inside
    /// it. Read by the method step's own copy ("Card or Apple Pay" versus
    /// "Card"), which is why this stays a promise the review step can
    /// actually keep rather than a guess about the device.
    var canOfferApplePay: Bool {
        RewoundStripe.canOfferApplePay && cardIntent != nil
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
                if case .server(let message, let code, let status, _) = error, status != 402, status < 500 {
                    // Terminal server verdict (refunded races, forbidden) —
                    // stop polling and show the backend's own message.
                    giveUp(partial, message: Self.terminalMessage(code: code, serverMessage: message))
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

    /// The server's own sentence for a purchase that cannot become an order,
    /// plus the half it leaves out.
    ///
    /// When a paid checkout can no longer be fulfilled the API refunds the
    /// charge and answers 409 with a `..._refunded` code — but its message is
    /// only "Listing is no longer available". A buyer who has just watched
    /// several thousand dollars leave their account is owed the other half of
    /// that sentence in the same breath, not in an email later. (Reachable
    /// only since the client started reading `details.code`; before that the
    /// code was always nil and this could never have been said.)
    private static func terminalMessage(code: String?, serverMessage: String) -> String {
        let served = serverMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = served.isEmpty ? "This purchase couldn't be completed." : served
        guard code?.hasSuffix("_refunded") == true else { return base }
        return "\(base) Your payment has been refunded in full — it can take a few days to reach your statement."
    }

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
