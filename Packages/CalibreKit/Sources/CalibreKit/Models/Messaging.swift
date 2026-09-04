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
/// Deliberately thin: no counterparty name, no message preview, no unread
/// count. The server denormalises only `listing_title`/`listing_reference`
/// onto the thread row (so a list renders without a per-row fetch); anything
/// else a richer inbox would want isn't in this service's response yet.
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
    public let createdAt: Date

    public var deliveryState: MessageDeliveryState {
        deliveredAt != nil ? .delivered : .held
    }
}

/// The three ways a sent message can end up, exactly as the product spec
/// names them. Rendering is sender-only for the last two — the recipient
/// must never see that a message was stopped at all.
public enum MessageDeliveryState: Sendable, Equatable {
    case delivered
    /// Guard-flagged, not yet reviewed by a human.
    case held
    /// An admin reviewed a held message and rejected it.
    ///
    /// Structurally supported end to end — `MessagingCopy.deniedNotice` and
    /// every bubble built on this enum already know how to render it — but
    /// nothing this store fetches can currently produce it: a denial leaves
    /// `guard_action` at `hold` forever (`app/api/views/reviews.py` in
    /// calibre-messaging never rewrites it on denial) and is never
    /// republished over the stream, so a denied message reads identically to
    /// a still-pending one through `GET /threads/{id}/messages`. The web
    /// reference has the same gap: `MessageThread.tsx` never computes
    /// `denied` either. Closing it needs a wire signal from the service that
    /// doesn't exist yet — not a client-side guess.
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
