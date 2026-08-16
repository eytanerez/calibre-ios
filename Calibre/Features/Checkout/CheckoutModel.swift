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

/// Everything the checkout cover needs: the listing, the buyer's addresses,
/// server-priced breakdowns for both payment methods, the funding-gated card
/// payment, and the post-payment order materialization.
@MainActor
@Observable
final class CheckoutModel {
    let listingID: String
    let offerID: String?

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

    var listing: Listing?
    var offer: Offer?

    // MARK: Shipping

    var addresses: [Address] = []
    var selectedAddressID: String? {
        didSet {
            guard oldValue != selectedAddressID else { return }
            // Pricing (tax, shipping) depends on the destination — refetch.
            cardIntent = nil
            pricingError = nil
            wireCheckout = nil
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
    private(set) var completedOrder: Order?

    /// `STPPaymentHandler` and `STPApplePayContext` both keep only weak
    /// references to these, so the model owns them for the life of a payment.
    @ObservationIgnored private let authenticationContext = CheckoutAuthenticationContext()
    @ObservationIgnored private var applePayCheckout: ApplePayCheckout?
    @ObservationIgnored private var applePayContext: STPApplePayContext?

    init(listingID: String, offerID: String?, catalog: CatalogStore, commerce: CommerceStore, client: APIClient) {
        self.listingID = listingID
        self.offerID = offerID
        self.catalog = catalog
        self.commerce = commerce
        self.checkout = CheckoutStore(client: client)
    }

    // MARK: - Loading

    func load() async {
        phase = .loading
        do {
            async let listingTask = catalog.listing(id: listingID)
            async let addressesTask = commerce.loadAddresses()
            if let offerID {
                offer = try await commerce.offer(id: offerID)
            }
            let (listing, addresses) = try await (listingTask, addressesTask)
            self.listing = listing
            self.addresses = addresses
            selectedAddressID = addresses.first(where: \.isDefaultShipping)?.id ?? addresses.first?.id
            showAddressForm = addresses.isEmpty
            phase = .ready
        } catch {
            phase = .failed(friendlyMessage(error))
        }
    }

    /// The amount being paid for the watch itself — the accepted offer when
    /// one rides along, the list price otherwise.
    var watchAmountText: String? {
        if let offer {
            return PriceFormatter.format(offer.amount.value, currency: offer.currency)
        }
        guard let listing else { return nil }
        return PriceFormatter.format(listing.price.value, currency: listing.currency)
    }

    var selectedAddress: Address? {
        addresses.first { $0.id == selectedAddressID }
    }

    var breakdown: CheckoutBreakdown? {
        cardIntent?.breakdown
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

    /// Prices the card path (and thereby the whole order). Fired when the
    /// method step appears so the fee difference can be shown in dollars.
    func prepareCardIntent() async {
        guard cardIntent == nil, !preparingCardIntent, let addressID = selectedAddressID else { return }
        preparingCardIntent = true
        pricingError = nil
        pricingProblem = nil
        defer { preparingCardIntent = false }
        do {
            let intent = try await checkout.paymentIntent(
                listingID: listingID,
                shippingAddressID: addressID,
                offerID: offerID
            )
            cardIntent = intent
            STPAPIClient.shared.publishableKey = intent.publishableKey
        } catch {
            let problem = CheckoutCopy.problem(for: error)
            pricingProblem = problem
            pricingError = problem.message
        }
    }

    /// The card cost in dollars, once the server has priced the order.
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

    private func startWire() async {
        if wireCheckout != nil {
            if path.last != .wire { path.append(.wire) }
            return
        }
        guard !preparingWire, let addressID = selectedAddressID else { return }
        preparingWire = true
        pricingError = nil
        pricingProblem = nil
        defer { preparingWire = false }
        do {
            wireCheckout = try await checkout.wireCheckout(
                listingID: listingID,
                shippingAddressID: addressID,
                offerID: offerID
            )
            path.append(.wire)
        } catch {
            let problem = CheckoutCopy.problem(for: error)
            pricingProblem = problem
            pricingError = problem.message
        }
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
                listingID: listingID,
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
            await materializeOrder()
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
            listingID: listingID,
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
    /// because that is the one Apple charges.
    private func applePaySummaryItems(_ breakdown: CheckoutBreakdown) -> [PKPaymentSummaryItem] {
        var items: [PKPaymentSummaryItem] = [
            PKPaymentSummaryItem(
                label: offerID == nil ? "Watch" : "Your accepted offer",
                amount: NSDecimalNumber(decimal: breakdown.subtotal.value)
            ),
            PKPaymentSummaryItem(
                label: "Shipping",
                amount: NSDecimalNumber(decimal: breakdown.shipping.value)
            ),
        ]
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
        Task { await materializeOrder() }
    }

    // MARK: - Order materialization

    /// Quiet "Confirming your order…" poll of /orders/from-payment-intent.
    /// The webhook can win the race — an already-created order returns 200
    /// and is equally a success. 402 means the payment is still settling.
    private func materializeOrder() async {
        guard let intent = cardIntent else { return }
        confirmingOrder = true
        defer { confirmingOrder = false }

        let deadline = Date.now.addingTimeInterval(15)
        while true {
            do {
                let order = try await checkout.orderFromPaymentIntent(
                    paymentIntentID: intent.paymentIntent.id
                )
                completedOrder = order
                return
            } catch let error as APIError {
                if case .server(_, _, let status, _) = error, status != 402, status < 500 {
                    // Terminal server verdict (refunded races, forbidden) —
                    // stop polling and show the backend's own message.
                    paymentProblem = CheckoutProblem(message: error.localizedDescription, retryable: false)
                    return
                }
                if Date.now >= deadline {
                    paymentProblem = CheckoutProblem(message: Self.settlingMessage, retryable: false)
                    return
                }
            } catch {
                if Date.now >= deadline {
                    paymentProblem = CheckoutProblem(message: Self.settlingMessage, retryable: false)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

    private static let settlingMessage =
        "Your payment went through, but we couldn't confirm the order just yet. It will appear in your orders shortly."

    // MARK: - Wire path

    private(set) var sendingWireReservation = false

    /// "I've sent the wire" — creates the awaiting-wire order and hands back
    /// its id so the view can route to order detail.
    func confirmWireSent() async -> Order? {
        guard let wire = wireCheckout, !sendingWireReservation else { return nil }
        sendingWireReservation = true
        defer { sendingWireReservation = false }
        do {
            return try await checkout.wireReservation(paymentIntentID: wire.wire.paymentIntentId)
        } catch {
            let problem = CheckoutCopy.problem(for: error)
            pricingProblem = problem
            pricingError = problem.message
            return nil
        }
    }

    // MARK: - Helpers

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
