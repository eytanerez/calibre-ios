import Foundation

/// The money track: native card checkout (PaymentSheet), order
/// materialization, and the wire-transfer path. Stateless — every call is a
/// straight request/response, so screens construct one with the app's shared
/// `APIClient` on demand.
///
/// Added by the P5 track as a new type because `CommerceStore.client` is
/// `private`, which a same-module extension in a separate file cannot reach.
public struct CheckoutStore: Sendable {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Native card checkout

    /// Prices the order server-side (subtotal, shipping, 3% card convenience
    /// fee, upfront tax) and returns a PaymentIntent for PaymentSheet. The
    /// buyer's card is saved for future use (`setup_future_usage=off_session`).
    public func paymentIntent(
        listingID: String,
        shippingAddressID: String?,
        offerID: String? = nil
    ) async throws -> NativeCheckoutIntent {
        struct Payload: Encodable {
            let listingId: String
            let shippingAddressId: String?
            let offerId: String?
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/payment-intent",
                payload: Payload(listingId: listingID, shippingAddressId: shippingAddressID, offerId: offerID)
            )
        )
    }

    /// Materializes the order after PaymentSheet reports success. Idempotent:
    /// an already-created order (webhook won the race) returns 200 with the
    /// same order shape — treat as success. `402` means the payment hasn't
    /// settled yet — poll again shortly.
    @discardableResult
    public func orderFromPaymentIntent(paymentIntentID: String) async throws -> Order {
        struct Payload: Encodable {
            let paymentIntentId: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/from-payment-intent",
                payload: Payload(paymentIntentId: paymentIntentID)
            )
        )
    }

    // MARK: - Wire transfer

    /// Creates the wire checkout: a bank-transfer PaymentIntent with
    /// displayable instructions (bank, routing, account, reference memo) and
    /// the same server-priced breakdown as the card path — minus the card fee.
    public func wireCheckout(
        listingID: String,
        shippingAddressID: String?,
        offerID: String? = nil
    ) async throws -> WireCheckout {
        struct Payload: Encodable {
            let listingId: String
            let shippingAddressId: String?
            let offerId: String?
            let paymentMethod: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/create-intent",
                payload: Payload(
                    listingId: listingID,
                    shippingAddressId: shippingAddressID,
                    offerId: offerID,
                    paymentMethod: "wire"
                )
            )
        )
    }

    /// "I've sent the wire" — creates the order in `awaiting_wire` and
    /// reserves the listing for 24 hours. Idempotent per PaymentIntent.
    @discardableResult
    public func wireReservation(paymentIntentID: String) async throws -> Order {
        struct Payload: Encodable {
            let paymentIntentId: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/wire-reservation",
                payload: Payload(paymentIntentId: paymentIntentID)
            )
        )
    }

    // MARK: - Offers on a listing

    /// The caller's offers on one listing (buyer sees their own; the seller
    /// sees hold-backed ones). Used to route "you already have an open offer"
    /// conflicts to the existing offer.
    public func offers(onListing listingID: String) async throws -> [Offer] {
        try await client.send(Endpoint(path: "/listings/\(listingID)/offers"))
    }
}
