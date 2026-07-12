import Foundation
import Observation

/// Support chat — works for guests and signed-in users alike. A guest's first
/// message returns a `guest_token` we persist so their thread survives relaunch
/// (mirrors the web widget's localStorage token).
@MainActor
@Observable
public final class SupportStore {
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let guestTokenKey = "calibre.support.guestToken"

    public private(set) var conversation: SupportConversation?

    public init(client: APIClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    /// The persisted guest token, if this device has written in as a guest.
    public var guestToken: String? {
        defaults.string(forKey: guestTokenKey)
    }

    /// Loads the caller's thread — via the auth session when signed in, or the
    /// stored guest token otherwise. Nil when no conversation exists yet.
    @discardableResult
    public func loadThread(authenticated: Bool) async throws -> SupportConversation? {
        var query: [URLQueryItem] = []
        if authenticated {
            // Once signed in, the account thread is authoritative — drop any
            // lingering guest token so a shared device can't resurface the
            // previous guest's conversation later.
            forgetGuestToken()
        } else if let token = guestToken {
            query.append(URLQueryItem(name: "token", value: token))
        }
        // The endpoint answers for guests too; only send auth when we have it.
        let thread: SupportConversation? = try await client.send(
            Endpoint(path: "/support/thread", query: query, requiresAuth: authenticated)
        )
        conversation = thread
        return thread
    }

    /// Posts a message. Guests must supply `guestEmail` on their first message;
    /// the returned guest token is persisted automatically.
    @discardableResult
    public func send(_ body: String, authenticated: Bool, guestEmail: String? = nil) async throws -> SupportConversation {
        struct Payload: Encodable {
            let body: String
            let email: String?
            let token: String?
        }
        let payload = Payload(
            body: body,
            email: authenticated ? nil : guestEmail,
            token: authenticated ? nil : guestToken
        )
        let result: SupportPostResult = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/support/messages",
                payload: payload,
                requiresAuth: authenticated
            )
        )
        if let token = result.guestToken {
            defaults.set(token, forKey: guestTokenKey)
        }
        conversation = result.thread
        return result.thread
    }

    /// Clears the persisted guest token (e.g. on sign-in, when the thread
    /// migrates to the account).
    public func forgetGuestToken() {
        defaults.removeObject(forKey: guestTokenKey)
    }
}
