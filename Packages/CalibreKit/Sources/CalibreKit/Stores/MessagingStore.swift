import Foundation
import Observation

extension APIConfiguration {
    /// Resolves calibre-messaging's own base URL from Info.plist
    /// (`CalibreMessagingBaseURL`) — a separate service from the main
    /// Backend, on its own host/port (dev: `http://localhost:8020`), so it
    /// needs a configuration `fromInfoPlist()` doesn't provide.
    public static func fromMessagingInfoPlist() -> APIConfiguration {
        #if DEBUG
        // Same UI-test/physical-device override seam as `fromInfoPlist()`.
        if let override = ProcessInfo.processInfo.environment["CALIBRE_MESSAGING_BASE_URL"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let raw = override.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else {
                preconditionFailure("CALIBRE_MESSAGING_BASE_URL must be an absolute HTTP(S) URL")
            }
            return APIConfiguration(baseURL: url)
        }
        #endif

        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CalibreMessagingBaseURL") as? String,
              let url = URL(string: raw) else {
            preconditionFailure("CalibreMessagingBaseURL missing from Info.plist")
        }
        return APIConfiguration(baseURL: url)
    }
}

/// Buyer↔seller messaging — threads, messages, and the send path's three
/// delivery states. Talks to `calibre-messaging` through `MessagingClient`,
/// not `APIClient`: see that file for why the two services need different
/// transports even though they share the one signed-in session.
@MainActor
@Observable
public final class MessagingStore {
    @ObservationIgnored private let client: MessagingClient

    public init(client: MessagingClient) {
        self.client = client
    }

    // MARK: - Threads

    public func listThreads() async throws -> [MessageThread] {
        try await client.send(Endpoint(path: "/threads"))
    }

    /// Opens a thread on a listing, or returns the existing one — idempotent
    /// per (listing, buyer) on the server, so tapping "Message Seller" twice
    /// from the PDP can never fork the conversation into two threads neither
    /// party can follow.
    public func openThread(
        listingID: String,
        sellerID: String,
        listingTitle: String?,
        listingReference: String?
    ) async throws -> MessageThread {
        struct Payload: Encodable {
            let listingId: String
            let sellerId: String
            let listingTitle: String?
            let listingReference: String?
        }
        return try await client.send(try Endpoint.json(
            method: .post,
            path: "/threads",
            payload: Payload(
                listingId: listingID,
                sellerId: sellerID,
                listingTitle: listingTitle,
                listingReference: listingReference
            )
        ))
    }

    // MARK: - Messages

    public func listMessages(threadID: String) async throws -> [ThreadMessage] {
        try await client.send(Endpoint(path: "/threads/\(threadID)/messages"))
    }

    /// Sends one message. The server alone decides delivered vs held —
    /// screens must render this result, never a locally-guessed state.
    public func send(threadID: String, body: String) async throws -> SendMessageResult {
        struct Payload: Encodable { let body: String }
        return try await client.send(try Endpoint.json(
            method: .post,
            path: "/threads/\(threadID)/messages",
            payload: Payload(body: body)
        ))
    }

    public func markRead(threadID: String) async throws {
        let _: EmptyResponse = try await client.send(
            Endpoint(method: .post, path: "/threads/\(threadID)/read")
        )
    }

    // MARK: - Live delivery

    /// Live messages for one open thread, over Server-Sent Events — additive
    /// only, same contract as the web client: a dropped connection degrades
    /// to "see it on the next fetch," never a gap the reader has no way to
    /// notice. Redeems a fresh ticket and resubscribes whenever the
    /// connection ends, for any reason — the server itself only closes a
    /// healthy stream on error, so an ended stream here means reconnect, not
    /// stop.
    ///
    /// Yields only ever-delivered messages: the fanout this stream carries is
    /// published solely for `allow`, after commit (`app/services/fanout.py`
    /// in calibre-messaging), so nothing held or denied can arrive this way.
    public func messageStream(threadID: String) -> AsyncStream<ThreadMessage> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    guard let ticket = try? await client.send(
                        Endpoint<StreamTicket>(method: .post, path: "/threads/\(threadID)/stream-ticket")
                    ) else {
                        try? await Task.sleep(for: .seconds(5))
                        continue
                    }
                    do {
                        let frames = client.eventStream(
                            path: "/threads/\(threadID)/stream",
                            query: [URLQueryItem(name: "ticket", value: ticket.ticket)]
                        )
                        for try await frame in frames {
                            if let message = Self.decodeFanoutMessage(frame, threadID: threadID) {
                                continuation.yield(message)
                            }
                        }
                    } catch {
                        // Falls through to the reconnect below.
                    }
                    guard !Task.isCancelled else { break }
                    // The ticket is one-shot and good for 60s; a fresh one is
                    // needed either way, so there is no backoff to lose by
                    // reconnecting promptly — just a floor so a server that
                    // is refusing every attempt doesn't spin.
                    try? await Task.sleep(for: .seconds(3))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `publish_message`'s payload shape — `{id, thread_id, sender_id, body,
    /// created_at}` — carries no `guard_action`/`delivered_at` because it is
    /// only ever sent for a message that is already delivered.
    private static func decodeFanoutMessage(_ data: Data, threadID: String) -> ThreadMessage? {
        struct Fanout: Decodable {
            let id: String
            let senderId: String
            let body: String
            let createdAt: Date
        }
        guard let fanout = try? APIClient.makeDecoder(origin: nil).decode(Fanout.self, from: data) else {
            return nil
        }
        return ThreadMessage(
            id: fanout.id,
            threadId: threadID,
            senderId: fanout.senderId,
            body: fanout.body,
            guardAction: .allow,
            deliveredAt: fanout.createdAt,
            createdAt: fanout.createdAt
        )
    }
}
