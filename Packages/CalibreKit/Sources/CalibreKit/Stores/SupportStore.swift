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
        if !authenticated, let token = guestToken {
            query.append(URLQueryItem(name: "token", value: token))
        }
        // Signing in no longer throws the guest token away. The server merges
        // a guest conversation into the account on signup, matched on the
        // verified email (contracts §12.9), and a client that had already
        // deleted its pointer left the thread stranded whenever that merge
        // did not run — sign-in to an existing account, say. The token is now
        // dropped at sign-out instead, which is the moment a shared handset
        // actually changes hands.
        // The endpoint answers for guests too; only send auth when we have it.
        let thread: SupportConversation? = try await client.send(
            Endpoint(path: "/support/thread", query: query, requiresAuth: authenticated)
        )
        conversation = thread
        return thread
    }

    /// Stages one file against the caller's existing thread, before the
    /// message that carries it. An upload cannot start a conversation — the
    /// server refuses one with "Start the conversation before attaching a
    /// file", which is why the attach control only turns on once a thread
    /// exists (admin-contracts §11.8, binding).
    ///
    /// Images and PDFs only, at most 10MB each.
    @discardableResult
    public func uploadAttachment(
        filename: String,
        contentType: String,
        data: Data,
        authenticated: Bool
    ) async throws -> SupportAttachment {
        var form = MultipartForm()
        if !authenticated, let token = guestToken {
            form.addField("token", value: token)
        }
        form.addFile("file", filename: filename, contentType: contentType, data: data)
        return try await client.send(
            Endpoint(
                method: .post,
                path: "/support/attachments",
                body: .multipart(form),
                requiresAuth: authenticated
            )
        )
    }

    /// Posts a message. Guests must supply `guestEmail` on their first message;
    /// the returned guest token is persisted automatically. `attachmentIDs`
    /// claims files already staged through `uploadAttachment`.
    @discardableResult
    public func send(
        _ body: String,
        authenticated: Bool,
        guestEmail: String? = nil,
        attachmentIDs: [String] = []
    ) async throws -> SupportConversation {
        struct Payload: Encodable {
            let body: String
            let email: String?
            let token: String?
            let attachmentIds: [String]?
        }
        let payload = Payload(
            body: body,
            email: authenticated ? nil : guestEmail,
            token: authenticated ? nil : guestToken,
            attachmentIds: attachmentIDs.isEmpty ? nil : attachmentIDs
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

    /// Clears the persisted guest token. Called at sign-out — not at sign-in,
    /// where the server is the one that reconciles a guest thread with the
    /// account it belongs to.
    public func forgetGuestToken() {
        defaults.removeObject(forKey: guestTokenKey)
    }

    /// Drops the thread held in memory — wired to
    /// `AuthSession.onSessionCleared`, so the previous account's conversation
    /// is not still on screen for whoever uses the app next.
    ///
    /// Deliberately leaves the guest token alone. A session can clear for
    /// reasons that have nothing to do with a person leaving — a rejected
    /// refresh token, a 401 on a guest's stray authenticated request — and
    /// none of those should cost a guest the only pointer to their own
    /// thread. Sign-out clears it, because that is the moment a device
    /// actually changes hands.
    public func reset() {
        conversation = nil
    }
}
