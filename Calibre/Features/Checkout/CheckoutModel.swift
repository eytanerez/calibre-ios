import CalibreKit
import Foundation
import Observation
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

/// Everything the checkout cover needs: the listing, the buyer's addresses,
/// server-priced breakdowns for both payment methods, PaymentSheet driving,
/// and the post-payment order materialization.
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
    private(set) var preparingCardIntent = false
    private(set) var wireCheckout: WireCheckout?
    private(set) var preparingWire = false

    // MARK: Payment

    var presentingPaymentSheet = false
    private(set) var paymentSheet: PaymentSheet?
    private(set) var paymentFailure: String?
    private(set) var confirmingOrder = false
    private(set) var completedOrder: Order?

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

    // MARK: - Shipping step

    func createAddress(_ payload: AddressPayload) async {
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
            pricingError = friendlyMessage(error)
        }
    }

    /// The 3% card cost in dollars, once the server has priced the order.
    var cardFeeText: String? {
        guard let breakdown = cardIntent?.breakdown,
              let fee = breakdown.cardConvenienceFee, fee.value > 0 else { return nil }
        return PriceFormatter.format(fee.value, currency: breakdown.currency)
    }

    func continueFromMethod() async {
        switch method {
        case .card:
            path.append(.review)
        case .wire:
            await startWire()
        }
    }

    private func startWire() async {
        if wireCheckout != nil {
            if path.last != .wire { path.append(.wire) }
            return
        }
        guard !preparingWire, let addressID = selectedAddressID else { return }
        preparingWire = true
        pricingError = nil
        defer { preparingWire = false }
        do {
            wireCheckout = try await checkout.wireCheckout(
                listingID: listingID,
                shippingAddressID: addressID,
                offerID: offerID
            )
            path.append(.wire)
        } catch {
            pricingError = friendlyMessage(error)
        }
    }

    // MARK: - Review & pay (card)

    func pay() {
        guard let intent = cardIntent else { return }
        paymentFailure = nil
        let configuration = CalibreStripe.configuration(
            customerID: intent.customerId,
            customerSessionClientSecret: intent.customerSessionClientSecret
        )
        paymentSheet = PaymentSheet(
            paymentIntentClientSecret: intent.paymentIntent.clientSecret,
            configuration: configuration
        )
        presentingPaymentSheet = true
    }

    func handlePaymentResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            Task { await materializeOrder() }
        case .canceled:
            // Back to review, silently — the buyer changed their mind.
            break
        case .failed(let error):
            paymentFailure = CalibreStripe.failureMessage(for: error)
        }
    }

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
                    paymentFailure = error.localizedDescription
                    return
                }
                if Date.now >= deadline {
                    paymentFailure = "Your payment went through, but we couldn't confirm the order just yet. It will appear in your orders shortly."
                    return
                }
            } catch {
                if Date.now >= deadline {
                    paymentFailure = "Your payment went through, but we couldn't confirm the order just yet. It will appear in your orders shortly."
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(1200))
        }
    }

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
            pricingError = friendlyMessage(error)
            return nil
        }
    }

    // MARK: - Helpers

    private func friendlyMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
