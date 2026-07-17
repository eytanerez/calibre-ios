import Foundation
import Observation

/// The server-side notification inbox (shared with the web bell) plus saved
/// searches. Push delivery is instant; this is the durable record behind it.
@MainActor
@Observable
public final class ServerAlertsStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var notifications: [ServerNotification] = []
    public private(set) var unreadCount: Int = 0
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
        unreadCount = response.unreadCount
        return response.results
    }

    public func markRead(id: String) async throws {
        struct Payload: Encodable { let read: Bool }
        let updated: ServerNotification = try await client.send(
            try Endpoint.json(method: .patch, path: "/account/notifications/\(id)", payload: Payload(read: true))
        )
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            let wasUnread = notifications[index].readAt == nil
            notifications[index] = updated
            if wasUnread {
                unreadCount = max(unreadCount - 1, 0)
            }
        }
    }

    public func markAllRead() async throws {
        struct Response: Decodable { let markedRead: Int }
        let _: Response = try await client.send(
            Endpoint(method: .post, path: "/account/notifications/read-all")
        )
        try? await load()
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
        unreadCount = 0
        savedSearches = []
    }
}
