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

    /// How many watches one checkout may cover, as the API enforces it.
    public static let maximumListingsPerCheckout = 10

    // MARK: - Native card checkout

    /// Prices the set server-side (each watch's subtotal and shipping, one
    /// card fee, upfront tax) and returns a PaymentIntent for PaymentSheet.
    /// The buyer's card is saved for future use
    /// (`setup_future_usage=off_session`).
    ///
    /// A checkout of one watch is a set of one: the request carries
    /// `listing_ids` either way, and the response carries `breakdown_group`
    /// either way — plus, for a single watch, the legacy `breakdown`.
    public func paymentIntent(
        listingIDs: [String],
        shippingAddressID: String?,
        offerID: String? = nil
    ) async throws -> NativeCheckoutIntent {
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/payment-intent",
                payload: CheckoutSetPayload(
                    listingIds: listingIDs,
                    shippingAddressId: shippingAddressID,
                    offerId: offerID,
                    paymentMethod: nil
                )
            )
        )
    }

    /// Materializes the purchase after PaymentSheet reports success.
    /// Idempotent: already-created orders (the webhook won the race) return
    /// 200 with the same shape — treat as success. `402` means the payment
    /// hasn't settled yet — poll again shortly.
    ///
    /// A set materializes one order per watch, and the orders can appear one
    /// at a time, so the caller polls until `orders.count` matches the set it
    /// checked out rather than stopping at the first 200.
    @discardableResult
    public func orderFromPaymentIntent(paymentIntentID: String) async throws -> OrderMaterialization {
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

    // MARK: - Funding gate + server confirm

    /// Asks whether this card may be used for this listing, the moment the
    /// PaymentMethod exists and while wire is still one tap away. Prepaid is
    /// refused everywhere; debit only clears where the discount presentation
    /// applies. `reason` carries the backend's machine code.
    public func validatePaymentMethod(
        listingIDs: [String],
        paymentMethodID: String
    ) async throws -> PaymentMethodValidation {
        struct Payload: Encodable {
            let listingIds: [String]
            let paymentMethodId: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/validate-payment-method",
                payload: Payload(listingIds: listingIDs, paymentMethodId: paymentMethodID)
            )
        )
    }

    /// Server-side confirmation of the PaymentIntent. A 402 carries the same
    /// refusal codes as validation (the funding gate is enforced twice, so a
    /// swapped card can't slip through). When the result requires action,
    /// hand its `clientSecret` to the SDK and then materialize the order.
    public func confirm(
        paymentIntentID: String,
        paymentMethodID: String
    ) async throws -> CheckoutConfirmation {
        struct Payload: Encodable {
            let paymentIntentId: String
            let paymentMethodId: String
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/confirm",
                payload: Payload(paymentIntentId: paymentIntentID, paymentMethodId: paymentMethodID)
            )
        )
    }

    // MARK: - Wire transfer

    /// Creates the wire checkout: a bank-transfer PaymentIntent with
    /// displayable instructions (bank, routing, account, reference memo) and
    /// the same server-priced breakdown as the card path — minus the card fee.
    public func wireCheckout(
        listingIDs: [String],
        shippingAddressID: String?,
        offerID: String? = nil
    ) async throws -> WireCheckout {
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/checkout/create-intent",
                payload: CheckoutSetPayload(
                    listingIds: listingIDs,
                    shippingAddressId: shippingAddressID,
                    offerId: offerID,
                    paymentMethod: "wire"
                )
            )
        )
    }

    /// "I've sent the wire" — creates one `awaiting_wire` order per watch in
    /// the set and reserves each of them. Idempotent per PaymentIntent: one
    /// transfer covers the whole purchase, so this is said once for the group.
    @discardableResult
    public func wireReservation(paymentIntentID: String) async throws -> OrderMaterialization {
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

    // MARK: - Read-only quote

    /// `GET /checkout/quote` — the set priced without reserving anything, for
    /// a screen that wants to show what a purchase would come to before the
    /// buyer commits to it.
    public func quote(
        listingIDs: [String],
        shippingAddressID: String? = nil,
        paymentMethod: String = "card"
    ) async throws -> CheckoutQuote {
        var query = [
            URLQueryItem(name: "listing_ids", value: listingIDs.joined(separator: ",")),
            URLQueryItem(name: "payment_method", value: paymentMethod),
        ]
        if let shippingAddressID {
            query.append(URLQueryItem(name: "shipping_address_id", value: shippingAddressID))
        }
        return try await client.send(Endpoint(path: "/checkout/quote", query: query))
    }

    // MARK: - Offers on a listing

    /// The caller's offers on one listing (buyer sees their own; the seller
    /// sees hold-backed ones). Used to route "you already have an open offer"
    /// conflicts to the existing offer.
    public func offers(onListing listingID: String) async throws -> [Offer] {
        try await client.send(Endpoint(path: "/listings/\(listingID)/offers"))
    }
}

/// The request body every checkout-intent endpoint takes: the set of watches,
/// where it ships, and — on `create-intent` only — how it is being paid for.
///
/// `listing_ids` is the authority on the wire; `listing_id` remains valid and
/// simply means a set of one. Only the keys that carry a value are written, so
/// the card endpoint (which has no `payment_method`) never receives one.
private struct CheckoutSetPayload: Encodable {
    let listingIds: [String]
    let shippingAddressId: String?
    let offerId: String?
    let paymentMethod: String?

    enum CodingKeys: String, CodingKey {
        case listingIds, shippingAddressId, offerId, paymentMethod
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(listingIds, forKey: .listingIds)
        try container.encodeIfPresent(shippingAddressId, forKey: .shippingAddressId)
        try container.encodeIfPresent(offerId, forKey: .offerId)
        try container.encodeIfPresent(paymentMethod, forKey: .paymentMethod)
    }
}
