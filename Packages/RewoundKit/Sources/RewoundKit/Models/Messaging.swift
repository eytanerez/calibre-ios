import Foundation

/// Buyer↔seller conversations, anchored to a listing — served by
/// `calibre-messaging`, a separate service from the main Backend (see
/// `MessagingClient`). Not support chat: that is a different service
/// (`SupportStore`) and a different conversation entirely.

public enum ThreadState: String, Codable, Sendable {
    case open
    case archived
    /// A participant blocked the other. The thread stays visible; sending
    /// into it is what the server refuses.
    case blocked
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// Mirrors the server's `GuardAction` — what the contact-leakage guard
/// decided about one message at send time. `hold` is a pending state, not a
/// final one: a human resolves it later, out of band (see
/// `ThreadMessage.deliveryState`).
public enum GuardAction: String, Codable, Sendable {
    case allow
    case hold
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// `GET /threads` / `POST /threads` — one buyer↔seller conversation.
///
/// The row now carries what a list row needs: the last delivered line, when it
/// was delivered, and how many messages the caller has not read. There is
/// still no counterparty name.
public struct MessageThread: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let listingId: String
    public let buyerId: String
    public let sellerId: String
    public let listingTitle: String?
    public let listingReference: String?
    public let state: ThreadState
    public let lastMessageAt: Date?
    public let createdAt: Date

    /// The most recently **delivered** message, whitespace already collapsed
    /// and cut to a wire-size cap by the server — a single line, but a long
    /// one, so a row still needs `lineLimit`.
    ///
    /// Never a held or denied message, for either party: a sender whose
    /// message is under review sees the previous delivered line here while the
    /// thread screen shows them their own held text. A send that does not
    /// change this row is that, and not a bug.
    ///
    /// It does not say who wrote it. There is no sender on this payload, so
    /// there is no honest way to draw a "You:" prefix.
    ///
    /// Nil means the thread has no delivered message yet — newly opened, or
    /// every message so far held by the guard.
    public let lastMessagePreview: String?
    /// When the previewed message was delivered. The two always describe the
    /// same event, so this is the timestamp to draw beside the preview.
    ///
    /// It equals `lastMessageAt` in the ordinary case, and can be later than
    /// the message's place in the transcript for one the moderation queue
    /// released — the stamp is when a person approved it. That is intended.
    /// Nil exactly when the preview is nil.
    public let lastMessagePreviewAt: Date?
    /// Messages from the other participant, delivered, and not yet marked read
    /// by the caller. Per-caller: the two sides see different numbers on the
    /// same thread. Never a "they read yours" receipt — no such thing exists
    /// in this service.
    ///
    /// It goes to zero through `POST /threads/{id}/read`, which returns no
    /// body, so the list is refetched (or the row zeroed) afterwards.
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id, listingId, buyerId, sellerId, listingTitle, listingReference
        case state, lastMessageAt, createdAt
        case lastMessagePreview, lastMessagePreviewAt, unreadCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        listingId = try container.decode(String.self, forKey: .listingId)
        buyerId = try container.decode(String.self, forKey: .buyerId)
        sellerId = try container.decode(String.self, forKey: .sellerId)
        listingTitle = ((try? container.decodeIfPresent(String.self, forKey: .listingTitle)) ?? nil)
        listingReference = ((try? container.decodeIfPresent(String.self, forKey: .listingReference)) ?? nil)
        state = try container.decode(ThreadState.self, forKey: .state)
        lastMessageAt = (try? container.decodeIfPresent(Date.self, forKey: .lastMessageAt)) ?? nil
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastMessagePreview = ((try? container.decodeIfPresent(String.self, forKey: .lastMessagePreview)) ?? nil)
        lastMessagePreviewAt = (try? container.decodeIfPresent(Date.self, forKey: .lastMessagePreviewAt)) ?? nil
        // Three fields the service only started sending tonight. A hard
        // decode of the count would turn a service one deploy behind into an
        // inbox that will not open at all.
        unreadCount = ((try? container.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? nil) ?? 0
    }

    public init(
        id: String,
        listingId: String,
        buyerId: String,
        sellerId: String,
        listingTitle: String? = nil,
        listingReference: String? = nil,
        state: ThreadState = .open,
        lastMessageAt: Date? = nil,
        createdAt: Date,
        lastMessagePreview: String? = nil,
        lastMessagePreviewAt: Date? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.listingId = listingId
        self.buyerId = buyerId
        self.sellerId = sellerId
        self.listingTitle = listingTitle
        self.listingReference = listingReference
        self.state = state
        self.lastMessageAt = lastMessageAt
        self.createdAt = createdAt
        self.lastMessagePreview = lastMessagePreview
        self.lastMessagePreviewAt = lastMessagePreviewAt
        self.unreadCount = unreadCount
    }

    /// The same thread with its unread count zeroed — what the list shows the
    /// moment somebody opens it, so the mark does not linger until a refetch.
    public func markedRead() -> MessageThread {
        MessageThread(
            id: id,
            listingId: listingId,
            buyerId: buyerId,
            sellerId: sellerId,
            listingTitle: listingTitle,
            listingReference: listingReference,
            state: state,
            lastMessageAt: lastMessageAt,
            createdAt: createdAt,
            lastMessagePreview: lastMessagePreview,
            lastMessagePreviewAt: lastMessagePreviewAt,
            unreadCount: 0
        )
    }
}

/// `GET /threads/{id}/messages` — one message. A message this client can see
/// but did not send is always `delivered`: the server excludes a held
/// message from every response except the one to its own sender (never a
/// silent drop, but never leaked to the other side either).
public struct ThreadMessage: Codable, Sendable, Identifiable {
    public let id: String
    public let threadId: String
    public let senderId: String
    public let body: String
    public let guardAction: GuardAction
    /// Never nil once delivered — the server's own words for why this is the
    /// authoritative signal rather than `guardAction` alone: "held" is an
    /// explicit state rather than an absent row.
    public let deliveredAt: Date?
    public let reviewOutcome: String?
    public let createdAt: Date

    public var deliveryState: MessageDeliveryState {
        if deliveredAt != nil { return .delivered }
        return reviewOutcome == "denied" ? .denied : .held
    }
}

public struct MessageThreadPage: Decodable, Sendable {
    public let items: [MessageThread]
    public let nextCursor: String?
}

public struct ThreadMessagePage: Decodable, Sendable {
    public let items: [ThreadMessage]
    public let nextCursor: String?
}

/// The three ways a sent message can end up, exactly as the product spec
/// names them. Rendering is sender-only for the last two — the recipient
/// must never see that a message was stopped at all.
public enum MessageDeliveryState: Sendable, Equatable {
    case delivered
    /// Guard-flagged, not yet reviewed by a human.
    case held
    /// An admin reviewed a held message and rejected it.
    case denied
}

/// The sender's own account of what happened, worded exactly as the product
/// spec requires — the backend's own `NOTICE_HELD`/`NOTICE_DENIED` constants
/// (`app/api/views/threads.py`), reproduced here because the messages-list
/// endpoint doesn't carry `notice` per row (only a fresh send's response
/// does) and both paths must read identically.
public enum MessagingCopy {
    public static let heldNotice =
        "This message flagged something in our system and is under review. It hasn't been delivered yet."
    public static let deniedNotice =
        "This message was rejected. Please don't send things like this — repeated attempts may lead to your account being suspended."

    public static func notice(for state: MessageDeliveryState) -> String? {
        switch state {
        case .delivered: nil
        case .held: heldNotice
        case .denied: deniedNotice
        }
    }
}

/// `POST /threads/{id}/messages` response — what the server decided, never
/// what the client hoped. Every bubble a send produces is built from this,
/// not from the local draft.
public struct SendMessageResult: Codable, Sendable {
    public let message: ThreadMessage
    public let action: GuardAction
    public let notice: String?
}

/// `POST /threads/{id}/stream-ticket` — a short-lived credential the SSE
/// `GET /threads/{id}/stream` URL can carry (a bearer token in a query string
/// would end up in proxy logs and browser/OS history).
public struct StreamTicket: Codable, Sendable {
    public let ticket: String
    public let expiresIn: Int
}
