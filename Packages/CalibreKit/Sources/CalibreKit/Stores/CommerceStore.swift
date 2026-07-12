import Foundation
import Observation

/// Buyer-side commerce: cart, watchlist, offers, orders, reviews, addresses
/// and the saved payment method. Everything here requires a signed-in session.
@MainActor
@Observable
public final class CommerceStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var cart: [CartItem] = []
    public private(set) var watchlist: [WatchlistItem] = []
    /// Listing ids currently watched — drives instant heart toggles.
    public private(set) var watchedListingIDs: Set<String> = []
    public private(set) var addresses: [Address] = []

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Cart
    //
    // The backend allows multiple cart rows; Calibre's one-watch cart swap
    // ("replace what's in your cart?") is a UI decision layered on top.

    @discardableResult
    public func loadCart() async throws -> [CartItem] {
        let items: [CartItem] = try await client.send(Endpoint(path: "/cart"))
        cart = items
        return items
    }

    @discardableResult
    public func addToCart(listingID: String, note: String? = nil) async throws -> CartItem {
        struct Payload: Encodable {
            let listingId: String
            let note: String?
        }
        let item: CartItem = try await client.send(
            try Endpoint.json(method: .post, path: "/cart", payload: Payload(listingId: listingID, note: note))
        )
        if let index = cart.firstIndex(where: { $0.id == item.id }) {
            cart[index] = item
        } else {
            cart.append(item)
        }
        return item
    }

    public func removeCartItem(id: String) async throws {
        let _: EmptyResponse = try await client.send(Endpoint(method: .delete, path: "/cart/\(id)"))
        cart.removeAll { $0.id == id }
    }

    // MARK: - Watchlist

    @discardableResult
    public func loadWatchlist() async throws -> [WatchlistItem] {
        let items: [WatchlistItem] = try await client.send(Endpoint(path: "/watchlist"))
        watchlist = items
        watchedListingIDs = Set(items.map(\.listingId))
        return items
    }

    public func isWatching(listingID: String) -> Bool {
        watchedListingIDs.contains(listingID)
    }

    /// Optimistic watch toggle: local state flips immediately, then the
    /// network call runs; any failure reverts to the captured snapshot before
    /// rethrowing so the UI can toast.
    public func toggleWatch(listingID: String) async throws {
        let previousWatchlist = watchlist
        let previousIDs = watchedListingIDs
        let revert: @MainActor () -> Void = { [weak self] in
            self?.watchlist = previousWatchlist
            self?.watchedListingIDs = previousIDs
        }

        let wasWatching = watchedListingIDs.contains(listingID)
        if wasWatching {
            watchedListingIDs.remove(listingID)
            watchlist.removeAll { $0.listingId == listingID }
        } else {
            watchedListingIDs.insert(listingID)
        }

        do {
            if wasWatching {
                if let item = previousWatchlist.first(where: { $0.listingId == listingID }) {
                    let _: EmptyResponse = try await client.send(
                        Endpoint(method: .delete, path: "/watchlist/\(item.id)")
                    )
                }
            } else {
                struct Payload: Encodable {
                    let listingId: String
                }
                let item: WatchlistItem = try await client.send(
                    try Endpoint.json(method: .post, path: "/watchlist", payload: Payload(listingId: listingID))
                )
                watchlist.append(item)
            }
        } catch {
            revert()
            throw error
        }
    }

    // MARK: - Offers

    public enum OfferAction: Sendable {
        case accept(message: String? = nil)
        case decline(message: String? = nil)
        case counter(amount: Decimal, message: String? = nil)
    }

    /// Make an offer. The response's `hold.clientSecret` + `publishableKey`
    /// feed Stripe PaymentSheet to authorize the $250 good-faith hold; call
    /// `confirmHold` afterwards.
    public func createOffer(
        listingID: String,
        amount: Decimal,
        currency: String = "USD",
        message: String? = nil
    ) async throws -> Offer {
        struct Payload: Encodable {
            let amount: String
            let currency: String
            let buyerMessage: String?
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/listings/\(listingID)/offers",
                payload: Payload(amount: "\(amount)", currency: currency, buyerMessage: message)
            )
        )
    }

    /// Verify the hold PaymentIntent after PaymentSheet — the offer flips to
    /// `pending_seller` on success.
    @discardableResult
    public func confirmHold(offerID: String) async throws -> Offer {
        try await client.send(Endpoint(method: .post, path: "/offers/\(offerID)/confirm-hold"))
    }

    /// Withdraw an offer and release its hold (buyer only).
    @discardableResult
    public func cancelOffer(offerID: String) async throws -> Offer {
        try await client.send(Endpoint(method: .post, path: "/offers/\(offerID)/cancel"))
    }

    /// Accept / decline / counter via PATCH `/offers/{id}`. Sellers act on
    /// `pending_seller`, buyers act on `countered`.
    @discardableResult
    public func respond(toOffer offerID: String, _ action: OfferAction) async throws -> Offer {
        struct Payload: Encodable {
            let status: String
            let counterAmount: String?
            let message: String?
        }
        let payload: Payload
        switch action {
        case .accept(let message):
            payload = Payload(status: "accepted", counterAmount: nil, message: message)
        case .decline(let message):
            payload = Payload(status: "declined", counterAmount: nil, message: message)
        case .counter(let amount, let message):
            payload = Payload(status: "countered", counterAmount: "\(amount)", message: message)
        }
        return try await client.send(
            try Endpoint.json(method: .patch, path: "/offers/\(offerID)", payload: payload)
        )
    }

    /// All my offers. `scope`: "sent", "received" or nil for both.
    public func offers(scope: String? = nil) async throws -> [Offer] {
        var query: [URLQueryItem] = []
        if let scope {
            query.append(URLQueryItem(name: "scope", value: scope))
        }
        return try await client.send(Endpoint(path: "/account/offers", query: query))
    }

    public func offer(id: String) async throws -> Offer {
        try await client.send(Endpoint(path: "/offers/\(id)"))
    }

    // MARK: - Orders

    /// My purchases, paginated and filterable.
    public func orders(
        page: Int = 1,
        pageSize: Int = 20,
        status: OrderStatus? = nil,
        search: String? = nil
    ) async throws -> PageResponse<Order> {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        if let status {
            query.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "search", value: search))
        }
        return try await client.send(Endpoint(path: "/buyer/orders", query: query))
    }

    public func order(id: String) async throws -> Order {
        try await client.send(Endpoint(path: "/orders/\(id)"))
    }

    /// Order event history — the buyer view is filtered server-side.
    public func orderTimeline(orderID: String) async throws -> [OrderEvent] {
        try await client.send(Endpoint(path: "/orders/\(orderID)/timeline"))
    }

    // MARK: - Reviews

    /// The seller review for an order, nil when not written yet.
    public func review(forOrder orderID: String) async throws -> SellerReview? {
        try await client.send(Endpoint<SellerReview?>(path: "/orders/\(orderID)/review"))
    }

    @discardableResult
    public func submitReview(orderID: String, rating: Int, comment: String?) async throws -> SellerReview {
        struct Payload: Encodable {
            let rating: Int
            let comment: String?
        }
        return try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/orders/\(orderID)/review",
                payload: Payload(rating: rating, comment: comment)
            )
        )
    }

    // MARK: - Addresses

    @discardableResult
    public func loadAddresses() async throws -> [Address] {
        let rows: [Address] = try await client.send(Endpoint(path: "/account/addresses"))
        addresses = rows
        return rows
    }

    @discardableResult
    public func createAddress(_ payload: AddressPayload) async throws -> Address {
        let address: Address = try await client.send(
            try Endpoint.json(method: .post, path: "/account/addresses", payload: payload)
        )
        addresses.append(address)
        return address
    }

    @discardableResult
    public func updateAddress(id: String, _ payload: AddressPayload) async throws -> Address {
        let address: Address = try await client.send(
            try Endpoint.json(method: .patch, path: "/account/addresses/\(id)", payload: payload)
        )
        if let index = addresses.firstIndex(where: { $0.id == id }) {
            addresses[index] = address
        }
        return address
    }

    public func deleteAddress(id: String) async throws {
        let _: EmptyResponse = try await client.send(Endpoint(method: .delete, path: "/account/addresses/\(id)"))
        addresses.removeAll { $0.id == id }
    }

    // MARK: - Payment method

    /// The saved default card, nil when none is on file.
    public func paymentMethod() async throws -> SavedPaymentMethod? {
        try await client.send(Endpoint<SavedPaymentMethod?>(path: "/account/payment-method"))
    }

    /// Detach the saved card. 409s (surfaced as `APIError.server`) while an
    /// active hold or accepted-unpaid offer exists.
    public func deletePaymentMethod() async throws {
        let _: EmptyResponse = try await client.send(Endpoint(method: .delete, path: "/account/payment-method"))
    }
}
