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

    // MARK: - Seller shipping label

    /// Live quote for the to-auth label without creating any payment.
    public func labelQuote(orderID: String, package: SellerLabelPackagePayload) async throws -> SellerLabelIntent {
        try await client.send(
            try Endpoint.json(method: .post, path: "/orders/\(orderID)/seller-label/quote", payload: package)
        )
    }

    /// PaymentIntent for the label purchase (PaymentSheet fields included).
    public func labelPaymentIntent(orderID: String, package: SellerLabelPackagePayload) async throws -> SellerLabelIntent {
        try await client.send(
            try Endpoint.json(method: .post, path: "/orders/\(orderID)/seller-label/payment-intent", payload: package)
        )
    }

    /// Finalizes a paid label PaymentIntent — idempotent; the webhook races
    /// this call and `alreadyCreated: true` is success.
    @discardableResult
    public func finalizeLabel(
        orderID: String,
        paymentIntentID: String,
        package: SellerLabelPackagePayload
    ) async throws -> SellerLabelFinalizeResult {
        struct Payload: Encodable {
            let paymentIntentId: String
            let boxLengthIn: String
            let boxWidthIn: String
            let boxHeightIn: String
            let weightLb: String
            let notes: String?
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/\(orderID)/seller-label/finalize",
                payload: Payload(
                    paymentIntentId: paymentIntentID,
                    boxLengthIn: package.boxLengthIn,
                    boxWidthIn: package.boxWidthIn,
                    boxHeightIn: package.boxHeightIn,
                    weightLb: package.weightLb,
                    notes: package.notes
                )
            )
        )
    }
}
