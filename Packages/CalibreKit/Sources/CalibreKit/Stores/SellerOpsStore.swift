import Foundation
import Observation

/// Seller flows the Sell suite needs beyond `SellerStore`'s CRUD surface:
/// Stripe Connect account sessions, the sales ledger and the native
/// shipping-label purchase. Lives in its own store so the committed
/// `SellerStore` file stays untouched (P6 no-collision rule).
@MainActor
@Observable
public final class SellerOpsStore {
    @ObservationIgnored private let client: APIClient

    /// The seller's sales (orders on their listings), newest first.
    public private(set) var sales: [Order] = []

    /// Bumped by a first-page `loadSales()` call, guarding its write to
    /// `sales` — same overlapping-retry risk as `SellerStore`'s dashboard and
    /// listings loads.
    @ObservationIgnored private var salesGeneration = 0

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Connect onboarding

    /// Creates (or reuses) the seller's Connect account and returns an
    /// AccountSession client secret for the Stripe Connect SDK. The SSN is
    /// forwarded to Stripe for identity verification; the backend keeps only
    /// a one-way fingerprint. Error codes: `ssn_required`,
    /// `seller_onboarding_blocked`.
    public func connectAccountSession(ssn: String) async throws -> ConnectAccountSession {
        struct Payload: Encodable {
            let ssn: String
        }
        return try await client.send(
            try Endpoint.json(method: .post, path: "/stripe/connect/account-session", payload: Payload(ssn: ssn))
        )
    }

    /// Stripe publishable key for SDK initialization. The backend only hands
    /// the key out inside payment payloads; `/billing/setup-intent` is the
    /// one authenticated endpoint that returns it without an order attached
    /// (the SetupIntent it creates is never confirmed and expires unused).
    public func stripePublishableKey() async throws -> String {
        struct Probe: Decodable, Sendable {
            let publishableKey: String
        }
        let probe: Probe = try await client.send(Endpoint(method: .post, path: "/billing/setup-intent"))
        return probe.publishableKey
    }

    // MARK: - Sales

    /// `GET /account/sales` — orders on the seller's listings, paginated.
    @discardableResult
    public func loadSales(page: Int = 1, pageSize: Int = 20, status: OrderStatus? = nil) async throws -> PageResponse<Order> {
        if page == 1 {
            salesGeneration += 1
        }
        let generation = salesGeneration
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        if let status {
            query.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        let response: PageResponse<Order> = try await client.send(Endpoint(path: "/account/sales", query: query))
        if page == 1, generation == salesGeneration {
            sales = response.results
        }
        return response
    }

    /// One order — the seller of the listing may read it.
    public func order(id: String) async throws -> Order {
        try await client.send(Endpoint(path: "/orders/\(id)"))
    }

    // MARK: - Returns (seller side)

    /// After a refunded return, the seller chooses: put it back on the
    /// market, or take it off. The watch is already on its way back to them.
    @discardableResult
    public func relistDecision(orderID: String, relist: Bool) async throws -> RelistDecision {
        struct Payload: Encodable {
            let relist: Bool
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/\(orderID)/return/relist-decision",
                payload: Payload(relist: relist)
            )
        )
    }

    /// "I shipped it" for the seller's own outbound leg — the same rule as
    /// the buyer's return: declaring buys a grace period for the carrier's
    /// first scan.
    ///
    /// `packingNote` is the one line the seller sends with the parcel, kept
    /// on the order and shown to the buyer when it arrives. It is written
    /// here or not at all — only the first declaration records one.
    ///
    /// A note longer than the card in the box is refused rather than cut:
    /// truncation would take the end of a sentence away without saying so.
    @discardableResult
    public func declareOutboundShipped(
        orderID: String,
        packingNote: String? = nil
    ) async throws -> FulfillmentShipped {
        struct Payload: Encodable { let packingNote: String }
        guard let packingNote else {
            return try await client.send(Endpoint(method: .post, path: "/orders/\(orderID)/fulfillment/shipped"))
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/\(orderID)/fulfillment/shipped",
                payload: Payload(packingNote: packingNote)
            )
        )
    }

    // MARK: - Seller fulfillment

    /// `POST /orders/{id}/fulfillment/shipping-quote` — what this box costs,
    /// and what it leaves the seller. Nothing is bought and nothing is
    /// charged. An order that already has a label answers `alreadyCreated`.
    public func shippingQuote(
        orderID: String,
        package: FulfillmentPackagePayload
    ) async throws -> FulfillmentShippingQuote {
        struct Payload: Encodable {
            let package: FulfillmentPackagePayload
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/\(orderID)/fulfillment/shipping-quote",
                payload: Payload(package: package)
            )
        )
    }

    /// `POST /orders/{id}/fulfillment/shipping-details` — the seller confirms
    /// the box, Calibre buys the label, and the order moves to authentication.
    /// `confirm` is explicit because pressing this spends Calibre's money and
    /// takes the payout down by whatever the carrier charged.
    @discardableResult
    public func submitShippingDetails(
        orderID: String,
        package: FulfillmentPackagePayload
    ) async throws -> FulfillmentShippingDetails {
        struct Payload: Encodable {
            let package: FulfillmentPackagePayload
            let confirm: Bool
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/\(orderID)/fulfillment/shipping-details",
                payload: Payload(package: package, confirm: true)
            )
        )
    }
}
