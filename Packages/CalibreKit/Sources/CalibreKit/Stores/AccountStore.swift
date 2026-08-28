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

    /// Where a deletion request stands, including exactly what is still
    /// outstanding. Safe to read before asking.
    public func deletionState() async throws -> AccountDeletionState {
        try await client.send(Endpoint(path: "/account/delete-request"))
    }

    /// Schedules deletion with the backend's 30-day grace window.
    ///
    /// Throws `APIError.server` with code `obligations_outstanding` (409)
    /// while anything is still in flight. Follow that with `deletionState()`
    /// to show the customer the actual list — the error envelope only
    /// carries flat string details, not the obligations array.
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

/// Pending-deletion state returned by the delete-request endpoints.
///
/// Deletion is blocked while obligations remain — a live order, an
/// outstanding payout, money in flight, an active return, an accepted offer.
/// The customer is told exactly what is outstanding, and deletion completes
/// on its own once the list clears.
public struct AccountDeletionState: Codable, Sendable {
    public let requested: Bool
    public let deletionScheduledFor: Date?
    public let obligations: [AccountObligation]
    public let canDelete: Bool
    /// Legacy field from the pre-obligations payload; still sent.
    public let status: String?
    public let scheduledFor: Date?

    enum CodingKeys: String, CodingKey {
        case requested, deletionScheduledFor, obligations, canDelete
        case status, scheduledFor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requested = try container.decodeIfPresent(Bool.self, forKey: .requested) ?? false
        deletionScheduledFor = try container.decodeIfPresent(Date.self, forKey: .deletionScheduledFor)
        obligations = try container.decodeIfPresent([AccountObligation].self, forKey: .obligations) ?? []
        canDelete = try container.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
        status = try container.decodeIfPresent(String.self, forKey: .status)
        scheduledFor = try container.decodeIfPresent(Date.self, forKey: .scheduledFor)
    }

    /// When deletion is expected to complete, from whichever field the
    /// backend filled in.
    public var scheduledDate: Date? { deletionScheduledFor ?? scheduledFor }

    /// Whether a deletion is standing against this account, and so whether the
    /// grace window is running and there is something to cancel.
    ///
    /// `requested` comes back from the read and from the request that schedules
    /// one; the request made against an account that is *already* scheduled
    /// answers with the date and the legacy `status` instead, and leaves
    /// `requested` out. A date is only ever set while one is pending — cancel
    /// clears it — so the two together are the whole answer.
    public var isPending: Bool { requested || scheduledDate != nil }
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
