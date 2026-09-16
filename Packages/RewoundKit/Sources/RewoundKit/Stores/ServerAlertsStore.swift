import Foundation
import Observation

/// The server-side notification inbox (shared with the web bell) plus saved
/// searches. Push delivery is instant; this is the durable record behind it.
@MainActor
@Observable
public final class ServerAlertsStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var notifications: [ServerNotification] = []
    /// What is still in the inbox. The badge counts what is left, not what is
    /// unread — a member who has read everything and cleared nothing still
    /// has an inbox with things in it, and the number says so.
    public private(set) var remainingCount: Int = 0
    public private(set) var savedSearches: [SavedSearchSummary] = []

    public init(client: APIClient) {
        self.client = client
    }

    @discardableResult
    public func load(pageSize: Int = 50) async throws -> [ServerNotification] {
        let response: ServerNotificationList = try await client.send(
            Endpoint(path: "/account/notifications", query: [URLQueryItem(name: "page_size", value: String(pageSize))])
        )
        notifications = response.results
        remainingCount = response.remainingCount
        return response.results
    }

    /// Clears one notification: the row leaves the inbox for good.
    ///
    /// A soft stamp on the server rather than a delete, because a deferred
    /// email hangs off the notification row and a delete would strand it —
    /// but from this app it is simply gone. There is no history and no undo,
    /// so nothing here keeps the row around.
    ///
    /// Idempotent: clearing a row that was already cleared answers 200 with
    /// the original stamp, so a second tap on a slow network is harmless.
    @discardableResult
    public func clear(id: String) async throws -> ServerNotification {
        let cleared: ServerNotification = try await client.send(
            Endpoint(method: .delete, path: "/account/notifications/\(id)")
        )
        drop(id: id)
        return cleared
    }

    /// Empties the inbox. Answers with how many rows this call actually swept
    /// — rows cleared earlier keep their own stamp and are not counted again.
    @discardableResult
    public func clearAll() async throws -> Int {
        struct Response: Decodable {
            let cleared: Int
            let remainingCount: Int?
        }
        let response: Response = try await client.send(
            Endpoint(method: .delete, path: "/account/notifications")
        )
        notifications = []
        remainingCount = response.remainingCount ?? 0
        return response.cleared
    }

    /// Takes a row out of the local inbox and off the badge without waiting
    /// for a refetch, so a clear reads as instant.
    private func drop(id: String) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications.remove(at: index)
        remainingCount = max(remainingCount - 1, 0)
    }

    /// Applies a clear that happened on one of the member's *other* devices,
    /// announced by the silent `notifications_cleared` push.
    ///
    /// The server has already done the work; this is the local record catching
    /// up so the inbox on this phone does not go on offering a row that is
    /// gone.
    ///
    /// `remaining` is the server's own count and replaces ours where it is
    /// there, rather than being derived from what this device happened to be
    /// holding — it may not have been holding all of it.
    ///
    /// Nil is the payload saying nothing about the count, which is a different
    /// sentence from saying zero. Zero would empty the bell on a phone that is
    /// holding a full inbox because two rows were cleared elsewhere. So the
    /// count moves by what was actually taken out here, the way a clear made
    /// on this phone moves it; a clear-all is the one case that reaches zero
    /// on its own arithmetic.
    public func applyCleared(ids: [String], clearedAll: Bool, remaining: Int?) {
        let held = notifications.count
        if clearedAll {
            notifications = []
        } else {
            let cleared = Set(ids)
            notifications.removeAll { cleared.contains($0.id) }
        }
        if let remaining {
            remainingCount = max(remaining, 0)
        } else if clearedAll {
            remainingCount = 0
        } else {
            remainingCount = max(remainingCount - (held - notifications.count), 0)
        }
    }

    /// Reports that the *push* for this notification was tapped.
    ///
    /// Deliberately not `markRead`: read means the row was seen in the inbox,
    /// opened means the person tapped the notification itself, and the
    /// server's push-first email delay only trusts the second. Idempotent
    /// server-side — the same push lands on every device the account
    /// registered, and one person reading one message once must stay one
    /// open, so the first tap wins and later ones change nothing.
    public func markOpened(id: String) async throws {
        let _: EmptyResponse = try await client.send(
            Endpoint(method: .post, path: "/account/notifications/\(id)/opened")
        )
        // `readAt` is left alone on purpose. Opened and read are two facts on
        // the server, and a tap only establishes the first; the row stays
        // unread in the inbox until it is cleared there.
        //
        // Nothing in this app marks a notification read any more. The inbox is
        // cleared, not ticked off, so the PATCH and read-all endpoints — which
        // the server keeps live for the web bell — have no caller here.
    }

    // MARK: - Saved searches

    @discardableResult
    public func loadSavedSearches() async throws -> [SavedSearchSummary] {
        struct Response: Decodable { let results: [SavedSearchSummary] }
        let response: Response = try await client.send(Endpoint(path: "/account/saved-searches"))
        savedSearches = response.results
        return response.results
    }

    /// Saves a browse query; the backend derives a name when none is given.
    @discardableResult
    public func createSavedSearch(filters: [String: String], name: String? = nil) async throws -> SavedSearchSummary {
        struct Payload: Encodable {
            let name: String?
            let filters: [String: String]
        }
        let created: SavedSearchSummary = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/account/saved-searches",
                payload: Payload(name: name, filters: filters)
            )
        )
        savedSearches.insert(created, at: 0)
        return created
    }

    public func deleteSavedSearch(id: String) async throws {
        struct Response: Decodable { let deleted: Bool }
        let _: Response = try await client.send(
            Endpoint(method: .delete, path: "/account/saved-searches/\(id)")
        )
        savedSearches.removeAll { $0.id == id }
    }

    public func reset() {
        notifications = []
        remainingCount = 0
        savedSearches = []
    }
}
