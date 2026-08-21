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
    /// Files carried by this message. Served through signed, time-limited
    /// URLs, so a link is only good for as long as the thread is open.
    public let attachments: [SupportAttachment]

    enum CodingKeys: String, CodingKey {
        case id, sender, body, createdAt, attachments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sender = try container.decode(SupportSender.self, forKey: .sender)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt)
        attachments = (try? container.decodeIfPresent([SupportAttachment].self, forKey: .attachments)) ?? []
    }
}

/// One file on a support message. Images and PDFs only, at most 10MB each and
/// 20MB across a message — the server enforces all three and says so in its
/// own words when it refuses.
public struct SupportAttachment: Codable, Sendable, Identifiable {
    /// Images and PDFs, and nothing else.
    public static let maxBytesPerFile = 10 * 1024 * 1024
    public static let maxBytesPerMessage = 20 * 1024 * 1024

    public let id: String
    public let filename: String?
    public let contentType: String?
    public let sizeBytes: Int?
    /// Signed and time-limited. Absent on the upload response, which answers
    /// before the file belongs to any message.
    public let url: MediaURL?

    public var isImage: Bool { (contentType ?? "").hasPrefix("image/") }
    public var isPDF: Bool { contentType == "application/pdf" }

    /// "1.2 MB" — what a person needs to know about a file they can see.
    public var sizeText: String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

/// POST `/support/messages` response — `{"thread": ..., "guest_token": ...}`.
/// `guestToken` is only issued the first time a guest writes in.
public struct SupportPostResult: Codable, Sendable {
    public let thread: SupportConversation
    public let guestToken: String?
}
