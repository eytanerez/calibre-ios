import Foundation

/// A watch in the member's Collection. Calibre purchases arrive automatically
/// on delivery (authenticated, with their Passport); manual adds cover the
/// rest of the drawer.
public struct VaultWatch: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let source: String
    public let orderId: String?
    public let listingId: String?
    public let passportCode: String?
    public let brand: String?
    public let model: String?
    public let reference: String?
    public let productionYear: Int?
    public let nickname: String?
    public let notes: String?
    public let photoUrl: String?
    public let acquiredPrice: String?
    public let acquiredDate: String?
    public let estimatedValue: String?
    public let estimatedAt: String?
    public let createdAt: String?

    public var isAuthenticated: Bool { source == "calibre_order" }

    public var displayTitle: String {
        let joined = [brand, model].compactMap { $0 }.joined(separator: " ")
        return nickname ?? (joined.isEmpty ? "Watch" : joined)
    }
}

/// One in-app notification (server-side inbox shared with the web bell).
public struct ServerNotification: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let category: String
    public let title: String
    public let body: String
    public let route: String
    public let readAt: String?
    public let createdAt: String?
}

public struct ServerNotificationList: Decodable, Equatable, Sendable {
    public let results: [ServerNotification]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let unreadCount: Int
}

public struct SavedSearchSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let lastMatchedAt: String?
    public let createdAt: String?
}
