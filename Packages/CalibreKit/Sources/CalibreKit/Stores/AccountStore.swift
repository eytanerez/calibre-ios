import Foundation
import Observation

/// Account-level settings that don't belong to commerce or selling: push
/// device registration, notification preferences, and password changes.
/// Everything here needs a signed-in session.
@MainActor
@Observable
public final class AccountStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var preferences: NotificationPreferences?

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Push devices

    /// Registers (upserts) an APNs device token. Safe to call on every launch
    /// and sign-in — APNs tokens rotate.
    public func registerDevice(token: String, environment: String) async throws {
        struct Payload: Encodable {
            let token: String
            let platform: String
            let environment: String
        }
        let _: DeviceRegistration = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/account/devices",
                payload: Payload(token: token, platform: "ios", environment: environment)
            )
        )
    }

    /// Unregisters a device token (called on sign-out).
    public func unregisterDevice(token: String) async throws {
        struct Payload: Encodable { let token: String }
        let _: EmptyResponse = try await client.send(
            try Endpoint.json(method: .delete, path: "/account/devices", payload: Payload(token: token))
        )
    }

    // MARK: - Notification preferences

    @discardableResult
    public func loadPreferences() async throws -> NotificationPreferences {
        let prefs: NotificationPreferences = try await client.send(
            Endpoint(path: "/account/notification-preferences")
        )
        preferences = prefs
        return prefs
    }

    /// Partial update — only the categories you pass change. Returns the full
    /// updated set.
    @discardableResult
    public func updatePreferences(_ patch: NotificationPreferencesPatch) async throws -> NotificationPreferences {
        let prefs: NotificationPreferences = try await client.send(
            try Endpoint.json(method: .patch, path: "/account/notification-preferences", payload: patch)
        )
        preferences = prefs
        return prefs
    }

    // MARK: - Password

    public func changePassword(current: String, new: String) async throws {
        struct Payload: Encodable {
            let currentPassword: String
            let newPassword: String
        }
        let _: EmptyResponse = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/auth/password/change",
                payload: Payload(currentPassword: current, newPassword: new)
            )
        )
    }

    // MARK: - Account deletion

    /// Schedules deletion with the backend's 30-day grace window.
    @discardableResult
    public func requestDeletion() async throws -> AccountDeletionState {
        try await client.send(Endpoint(method: .post, path: "/account/delete-request"))
    }

    /// Cancels a pending deletion.
    public func cancelDeletion() async throws {
        let _: EmptyResponse = try await client.send(Endpoint(method: .post, path: "/account/delete-cancel"))
    }
}

/// One APNs device registration record.
public struct DeviceRegistration: Codable, Sendable, Identifiable {
    public let id: String
    public let token: String
    public let platform: String
    public let environment: String
    public let lastSeenAt: Date?
    public let createdAt: Date?
}

/// Pending-deletion state returned by the delete-request endpoint.
public struct AccountDeletionState: Codable, Sendable {
    public let status: String
    public let scheduledFor: Date?
}

/// A partial notification-preferences update. Only non-nil fields are sent, so
/// a single toggle change touches exactly one category.
public struct NotificationPreferencesPatch: Encodable, Sendable {
    public var offerUpdates: Bool?
    public var orderUpdates: Bool?
    public var trackingUpdates: Bool?
    public var messageUpdates: Bool?
    public var watchlistAlerts: Bool?
    public var marketUpdates: Bool?
    public var securityAlerts: Bool?

    public init(
        offerUpdates: Bool? = nil,
        orderUpdates: Bool? = nil,
        trackingUpdates: Bool? = nil,
        messageUpdates: Bool? = nil,
        watchlistAlerts: Bool? = nil,
        marketUpdates: Bool? = nil,
        securityAlerts: Bool? = nil
    ) {
        self.offerUpdates = offerUpdates
        self.orderUpdates = orderUpdates
        self.trackingUpdates = trackingUpdates
        self.messageUpdates = messageUpdates
        self.watchlistAlerts = watchlistAlerts
        self.marketUpdates = marketUpdates
        self.securityAlerts = securityAlerts
    }

    // Synthesized Encodable uses `encodeIfPresent` for optionals, so nil
    // categories are omitted and a partial patch stays partial on the wire.
    // `Endpoint.json` applies the snake_case key strategy.
}
