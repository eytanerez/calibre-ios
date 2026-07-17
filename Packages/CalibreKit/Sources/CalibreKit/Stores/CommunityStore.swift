import Foundation
import Observation

/// Community: the daily question, polls, and the own-data market overview.
@MainActor
@Observable
public final class CommunityStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var today: CommunityToday?
    public private(set) var market: MarketOverview?

    public init(client: APIClient) {
        self.client = client
    }

    @discardableResult
    public func loadToday() async throws -> CommunityToday {
        let payload: CommunityToday = try await client.send(
            Endpoint(path: "/community/today", requiresAuth: false)
        )
        today = payload
        return payload
    }

    /// Votes (or changes a vote) and folds the refreshed prompt back into
    /// whatever section it lives in.
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
        if var current = today {
            if current.daily?.id == updated.id {
                current = CommunityToday(daily: updated, polls: current.polls, recent: current.recent)
            } else {
                current = CommunityToday(
                    daily: current.daily,
                    polls: current.polls.map { $0.id == updated.id ? updated : $0 },
                    recent: current.recent.map { $0.id == updated.id ? updated : $0 }
                )
            }
            today = current
        }
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
}
