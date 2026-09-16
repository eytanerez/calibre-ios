import Foundation
import Observation

/// Community: the day's questions, and the market room's two reads —
/// the brand-level overview and the published reference prices behind the
/// board. Both live here because both are `/market/*` and both are read from
/// the same room; a second store would only split one screen's fetches.
@MainActor
@Observable
public final class CommunityStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var today: CommunityToday?
    public private(set) var market: MarketOverview?
    /// Every reference that publishes a price. Empty until loaded — and
    /// legitimately empty afterwards if nothing publishes yet.
    public private(set) var referencePrices: [MarketReferencePrice] = []
    /// When the published set was last recomputed, as the server states it.
    public private(set) var referencePricesAsOf: String?

    public init(client: APIClient) {
        self.client = client
    }

    /// Loads today's questions, one per kind. Pass `authenticated: true` for signed-in members
    /// so the response carries their votes — the client only attaches the auth
    /// header when an endpoint requires it, and without it the feed comes back
    /// as a guest's (no `my_vote`, questions re-ask after every reload).
    @discardableResult
    public func loadToday(authenticated: Bool) async throws -> CommunityToday {
        let payload: CommunityToday = try await client.send(
            Endpoint(path: "/community/today", requiresAuth: authenticated)
        )
        today = payload
        return payload
    }

    /// Votes (or changes a vote) and folds the refreshed question back into
    /// whichever lane — or the history — it came from.
    @discardableResult
    public func vote(promptID: String, option: String) async throws -> CommunityPrompt {
        struct Payload: Encodable { let option: String }
        let updated: CommunityPrompt = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/community/prompts/\(promptID)/vote",
                payload: Payload(option: option)
            )
        )
        today = today?.replacing(updated)
        return updated
    }

    @discardableResult
    public func loadMarket() async throws -> MarketOverview {
        let payload: MarketOverview = try await client.send(
            Endpoint(path: "/market/overview", requiresAuth: false)
        )
        market = payload
        return payload
    }

    /// The board's whole dataset: what each reference is worth today plus the
    /// change-points behind it.
    @discardableResult
    public func loadReferencePrices() async throws -> [MarketReferencePrice] {
        let payload: MarketReferencePriceList = try await client.send(
            Endpoint(path: "/market/reference-prices", requiresAuth: false)
        )
        referencePrices = payload.references
        referencePricesAsOf = payload.asOf
        return payload.references
    }

    /// One reference's price, or nil when it publishes none.
    ///
    /// Most references in the catalog have no published price, so the 404 is
    /// an ordinary answer here rather than a failure — it is the difference
    /// between "we don't price this" and "we couldn't reach Calibre", and the
    /// screen says something different for each.
    public func referencePrice(slug: String) async throws -> MarketReferencePrice? {
        let endpoint = Endpoint<MarketReferencePrice>(
            path: "/market/reference-prices/\(slug)",
            requiresAuth: false
        )
        do {
            return try await client.send(endpoint)
        } catch let APIError.server(_, _, status, _) where status == 404 {
            return nil
        }
    }
}
