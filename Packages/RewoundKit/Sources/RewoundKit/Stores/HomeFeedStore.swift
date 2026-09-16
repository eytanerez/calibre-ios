import Foundation
import Observation

/// The server-composed Home feed, and nothing else.
///
/// There is deliberately no scoring, no lane-filling and no re-ordering here.
/// The order arrives ranked and frozen for the day; this store holds it, swaps
/// a voted question into place without refetching, and drops it the moment the
/// reader changes.
@MainActor
@Observable
public final class HomeFeedStore {
    @ObservationIgnored private let client: APIClient

    /// The feed as last served. Nil before the first load settles, and nil
    /// again after `reset()`.
    public private(set) var feed: ComposedHomeFeed?

    public init(client: APIClient) {
        self.client = client
    }

    /// Loads the feed for whoever the session currently is.
    ///
    /// `authenticated` decides whether the auth header rides along, exactly as
    /// `CommunityStore.loadToday` does: the endpoint answers `AllowAny`, so
    /// without the header a signed-in member is served the guest feed — no
    /// next step, no saved-search matches, no collection, and a question that
    /// re-asks itself after every reload.
    ///
    /// `refresh` is the endpoint's "give me material I have not just been
    /// shown": it discards the day's frozen ordering and rebuilds it excluding
    /// what the previous one held. Home deliberately does **not** spend a
    /// pull-to-refresh on it — a pull usually means "are these prices still
    /// right", and burning the plan on every pull walks a reader down the
    /// ranked pool a screenful at a time. A plain reload re-reads every live
    /// row and cannot move a surviving card, which is what a pull should do.
    ///
    /// A failure is left to the caller. An empty feed and a failed request are
    /// different states with different words, and swallowing the error here
    /// would make them the same one.
    @discardableResult
    public func load(authenticated: Bool, refresh: Bool = false) async throws -> ComposedHomeFeed {
        let payload: ComposedHomeFeed = try await client.send(
            Endpoint(
                path: "/home/feed",
                query: refresh ? [URLQueryItem(name: "refresh", value: "1")] : [],
                requiresAuth: authenticated
            )
        )
        feed = payload
        return payload
    }

    /// Folds a freshly voted question back into the poll module in place.
    public func applyVote(_ prompt: CommunityPrompt) {
        feed = feed?.replacingPoll(prompt)
    }

    /// Drops the held feed. Called when the session changes: a feed is about
    /// one particular reader, and the previous member's ordering must never be
    /// painted for the next one.
    public func reset() {
        feed = nil
    }
}
