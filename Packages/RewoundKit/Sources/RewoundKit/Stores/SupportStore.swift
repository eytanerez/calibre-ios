import Foundation
import Observation

/// Support chat — works for guests and signed-in users alike. A customer has
/// as many conversations as they have written in about; this store holds the
/// list of them and whichever one is open.
///
/// A guest's message returns a `guest_token` we persist so their thread
/// survives relaunch (mirrors the web widget's localStorage token). Starting
/// a second conversation as a guest mints a second token, so the device keeps
/// a set of them and presents all of them when it asks for the list — and,
/// when it writes, presents the one belonging to the conversation being
/// written into, because a token proves one conversation and not the rest.
@MainActor
@Observable
public final class SupportStore {
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let defaults: UserDefaults
    /// The single token this app stored before a guest could have more than
    /// one conversation. Still read, once, so nobody loses the thread they
    /// already had; never written again.
    @ObservationIgnored private let legacyGuestTokenKey = "calibre.support.guestToken"
    @ObservationIgnored private let guestTokensKey = "calibre.support.guestTokens"

    public private(set) var conversation: SupportConversation?
    public private(set) var threads: [SupportThreadSummary] = []

    public init(client: APIClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    /// Every guest token this device holds, oldest first. Empty for a device
    /// that has only ever been signed in.
    public var guestTokens: [String] {
        let stored = defaults.stringArray(forKey: guestTokensKey) ?? []
        guard stored.isEmpty else { return stored }
        return defaults.string(forKey: legacyGuestTokenKey).map { [$0] } ?? []
    }

    /// The most recent guest token — what a call that names no conversation
    /// sends, because a new conversation is what the newest token belongs to.
    public var guestToken: String? { guestTokens.last }

    /// Which conversation each token this device holds actually proves.
    ///
    /// A guest token is a bearer token for **one** conversation, not for the
    /// mailbox: the server resolves a named thread against the tokens
    /// presented with it and answers 404 for anything they do not name. So a
    /// write into an older conversation has to travel with that
    /// conversation's own token; the newest one is refused as somebody
    /// else's. Filled in by `send`, which learns the pairing when a token is
    /// minted, and by `listThreads`, where the server echoes each row's token
    /// back beside it.
    @ObservationIgnored private var tokensByThread: [String: String] = [:]

    /// The token that proves `threadID`, or the newest token when nothing is
    /// named.
    ///
    /// A miss asks the server, because the thread list is the only place a
    /// token and the conversation it proves appear together and a guest can
    /// land on a conversation from a link without ever opening the list. Only
    /// worth a request for a device holding more than one token: with one
    /// token there is nothing to choose between.
    private func guestToken(forThread threadID: String?) async -> String? {
        guard let threadID else { return guestToken }
        if let known = knownGuestToken(forThread: threadID) { return known }
        guard guestTokens.count > 1 else { return guestToken }
        _ = try? await listThreads(authenticated: false)
        return knownGuestToken(forThread: threadID) ?? guestToken
    }

    /// The recorded token for a conversation, without asking the server. A
    /// token that has since been forgotten is not offered — sign-out empties
    /// the set, and a pointer that outlived it proves nothing.
    private func knownGuestToken(forThread threadID: String) -> String? {
        let held = guestTokens
        if let recorded = tokensByThread[threadID], held.contains(recorded) { return recorded }
        if let listed = threads.first(where: { $0.id == threadID })?.guestToken, held.contains(listed) {
            return listed
        }
        return nil
    }

    /// The server caps the repeated `token` parameter, so a device that has
    /// somehow collected more than the cap sends its most recent ones.
    private static let guestTokenLimit = 20

    private func remember(guestToken token: String) {
        var tokens = guestTokens
        guard !tokens.contains(token) else { return }
        tokens.append(token)
        if tokens.count > Self.guestTokenLimit {
            tokens.removeFirst(tokens.count - Self.guestTokenLimit)
        }
        defaults.set(tokens, forKey: guestTokensKey)
    }

    private func guestTokenQuery() -> [URLQueryItem] {
        guestTokens.suffix(Self.guestTokenLimit).map { URLQueryItem(name: "token", value: $0) }
    }

    /// The customer's conversations, newest activity first. A guest is
    /// answered with exactly the threads their own tokens name.
    @discardableResult
    public func listThreads(authenticated: Bool) async throws -> [SupportThreadSummary] {
        struct Response: Decodable { let results: [SupportThreadSummary] }
        let response: Response = try await client.send(
            Endpoint(
                path: "/support/threads",
                query: authenticated ? [] : guestTokenQuery(),
                requiresAuth: authenticated
            )
        )
        threads = response.results
        for thread in response.results where thread.guestToken != nil {
            tokensByThread[thread.id] = thread.guestToken
        }
        return response.results
    }

    /// One conversation by id. A thread that is not the caller's and a thread
    /// that does not exist are the same 404, by design.
    @discardableResult
    public func loadThread(id: String, authenticated: Bool) async throws -> SupportConversation {
        let thread: SupportConversation = try await client.send(
            Endpoint(
                path: "/support/threads/\(id)",
                query: authenticated ? [] : guestTokenQuery(),
                requiresAuth: authenticated
            )
        )
        conversation = thread
        return thread
    }

    /// Loads the caller's most recently active thread — via the auth session
    /// when signed in, or the stored guest tokens otherwise. Nil when no
    /// conversation exists yet.
    ///
    /// It answers with that thread whether or not writing into it would
    /// continue it; `resumable` on the payload is how the caller knows which.
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
    ///
    /// `threadID` is the conversation the file is being written into. It
    /// decides nothing on the server — a guest's upload is staged against
    /// whichever thread the token proves — which is exactly why it has to be
    /// passed: staged against the newest conversation, a file attached to an
    /// older one is claimed by a `send` scoped to that older thread and found
    /// nowhere.
    @discardableResult
    public func uploadAttachment(
        filename: String,
        contentType: String,
        data: Data,
        authenticated: Bool,
        threadID: String? = nil
    ) async throws -> SupportAttachment {
        var form = MultipartForm()
        if !authenticated, let token = await guestToken(forThread: threadID) {
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
    /// any guest token the response carries is persisted automatically.
    /// `attachmentIDs` claims files already staged through `uploadAttachment`.
    ///
    /// Which conversation it lands on, in the server's order of precedence:
    /// `threadID` names one outright (and writes to it even when it is
    /// closed — naming a thread is somebody deliberately going back to it);
    /// `newThread` opens a fresh one whatever else exists; neither, and the
    /// server applies its own resume rule. The 24-hour window is not
    /// reimplemented here, and must not be.
    @discardableResult
    public func send(
        _ body: String,
        authenticated: Bool,
        guestEmail: String? = nil,
        attachmentIDs: [String] = [],
        threadID: String? = nil,
        newThread: Bool = false
    ) async throws -> SupportConversation {
        struct Payload: Encodable {
            let body: String
            let email: String?
            let token: String?
            let attachmentIds: [String]?
            let threadId: String?
            let newThread: Bool?
        }
        // The token that proves the conversation being written into — not the
        // newest one. `threadID` names a thread the server will only accept
        // from a caller who can prove it, and each of a guest's tokens proves
        // one conversation, so replying to anything but their latest with the
        // latest token is a 404 and the words are lost.
        let token = authenticated ? nil : await guestToken(forThread: threadID)
        let payload = Payload(
            body: body,
            email: authenticated ? nil : guestEmail,
            token: token,
            attachmentIds: attachmentIDs.isEmpty ? nil : attachmentIDs,
            threadId: threadID,
            newThread: newThread ? true : nil
        )
        let result: SupportPostResult = try await client.send(
            try Endpoint.json(
                method: .post,
                path: "/support/messages",
                payload: payload,
                requiresAuth: authenticated
            )
        )
        // Both halves of the pairing are in hand here and nowhere else on this
        // path: the conversation the message landed in, and the token that now
        // proves it — freshly minted when the response carries one, otherwise
        // the one this call presented.
        if let minted = result.guestToken {
            remember(guestToken: minted)
            tokensByThread[result.thread.id] = minted
        } else if let token {
            tokensByThread[result.thread.id] = token
        }
        conversation = result.thread
        return result.thread
    }

    /// The records this customer may name in a message (contracts §12.9b).
    ///
    /// Scoped by the server, twice, and the scoping is the feature rather than
    /// a detail: `/buyer/orders` answers only orders whose `buyer_id` is the
    /// caller, and `/account/listings` only listings whose `seller_id` is. The
    /// admin console's own record search is deliberately not used — it can
    /// reach anybody's order, and this code runs on a customer's handset.
    ///
    /// Listings are narrowed to the live ones here: a draft or an archived
    /// listing has no page to send a reader to, so naming one would produce a
    /// chip that means nothing to whoever opens the thread.
    ///
    /// Only for a signed-in member. A guest has no records and no session to
    /// scope them by, so the caller does not offer the control at all.
    public func linkableRecords(query: String) async throws -> [RecordRefOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var orderQuery = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
        ]
        if !trimmed.isEmpty {
            orderQuery.append(URLQueryItem(name: "search", value: trimmed))
        }

        async let ordersTask: PageResponse<Order> = client.send(
            Endpoint(path: "/buyer/orders", query: orderQuery)
        )
        async let listingsTask: [Listing] = client.send(Endpoint(path: "/account/listings"))
        let (orders, listings) = try await (ordersTask, listingsTask)

        let orderOptions = orders.results.map { order in
            RecordRefOption(
                ref: RecordRef(kind: .order, recordID: order.id, label: Self.orderLabel(order)),
                detail: order.listing?.title
            )
        }
        let listingOptions = listings
            .filter { $0.status == .active }
            .map { listing in
                RecordRefOption(
                    ref: RecordRef(kind: .listing, recordID: listing.id, label: listing.title),
                    detail: "#\(listing.listingNumber)"
                )
            }

        let all = orderOptions + listingOptions
        guard !trimmed.isEmpty else { return all }
        return all.filter { option in
            option.ref.label.localizedCaseInsensitiveContains(trimmed)
                || (option.detail ?? "").localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// `Order #13` when there is a number, and something a person still reads
    /// when there is not — the label is what the message says, so it is never
    /// allowed to be empty.
    private static func orderLabel(_ order: Order) -> String {
        if let number = order.orderNumber {
            return "Order #\(number)"
        }
        if let title = order.listing?.title, !title.isEmpty {
            return "Order for \(title)"
        }
        return "Your order"
    }

    /// Clears every persisted guest token. Called at sign-out — not at
    /// sign-in, where the server is the one that reconciles a guest thread
    /// with the account it belongs to.
    public func forgetGuestToken() {
        defaults.removeObject(forKey: guestTokensKey)
        defaults.removeObject(forKey: legacyGuestTokenKey)
        tokensByThread = [:]
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
        threads = []
    }
}
