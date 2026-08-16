import Foundation

public enum SupportConversationStatus: String, Codable, Sendable {
    case open
    /// The customer wrote last; their Calibre contact owes a reply.
    case waitingOnCalibre = "waiting_on_calibre"
    /// Calibre wrote last.
    case waitingOnCustomer = "waiting_on_customer"
    case closed
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// The named person on the Calibre side of this conversation. Messages come
/// personally from them, and writing to support@buycalibre.com lands in the
/// same thread.
public struct SupportContact: Codable, Sendable {
    public let key: String?
    public let displayName: String?
}

public enum SupportSender: String, Codable, Sendable {
    case customer
    case admin
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

// FIXTURE-PENDING: the signed-in capture couldn't be recorded (backend
// mid-migration); the guest capture legitimately returns `data: null`. Shape
// from `serialize_thread` in app/api/views/support_chat.py.
/// `/support/thread` — the caller's support conversation, or nil if none.
public struct SupportConversation: Codable, Sendable, Identifiable {
    public let id: String
    public let status: SupportConversationStatus
    public let createdAt: Date?
    public let lastMessageAt: Date?
    public let messages: [SupportMessage]
    /// Present once a contact is assigned; nil before then.
    public let assignedContact: SupportContact?
}

public struct SupportMessage: Codable, Sendable, Identifiable {
    public let id: String
    public let sender: SupportSender
    public let body: String
    public let createdAt: Date?
}

/// POST `/support/messages` response — `{"thread": ..., "guest_token": ...}`.
/// `guestToken` is only issued the first time a guest writes in.
public struct SupportPostResult: Codable, Sendable {
    public let thread: SupportConversation
    public let guestToken: String?
}
