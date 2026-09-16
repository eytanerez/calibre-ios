import Foundation

public enum SupportConversationStatus: String, Codable, Sendable {
    case open
    /// The customer wrote last; their Rewound contact owes a reply.
    case waitingOnRewound = "waiting_on_rewound"
    /// Rewound wrote last.
    case waitingOnCustomer = "waiting_on_customer"
    case closed
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// The named person on the Rewound side of this conversation. Messages come
/// personally from them, and writing to support@shoprewound.com lands in the
/// same thread.
public struct SupportContact: Codable, Sendable, Equatable {
    public let key: String?
    public let displayName: String?

    /// The name, or nil — never an empty string dressed up as one.
    public var name: String? {
        let trimmed = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// First letters of the name, for an avatar that carries no photograph.
    ///
    /// Derived here, from whatever the server sent, rather than stored beside
    /// a name: there is no table of people in this app to keep in step, and
    /// adding or renaming a contact is the server's to do alone.
    public var initials: String {
        let words = (name ?? "").split(separator: " ").filter { !$0.isEmpty }
        guard let first = words.first else { return "?" }
        if words.count == 1 {
            return String(first.prefix(2)).uppercased()
        }
        let last = words[words.count - 1]
        return (String(first.prefix(1)) + String(last.prefix(1))).uppercased()
    }
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
/// `/support/thread` and `/support/threads/{id}` — one support conversation.
///
/// A customer now has as many of these as they have written in about; this is
/// one of them, not "the" one.
public struct SupportConversation: Codable, Sendable, Identifiable {
    public let id: String
    public let status: SupportConversationStatus
    public let createdAt: Date?
    public let lastMessageAt: Date?
    public let messages: [SupportMessage]
    /// Present once a contact is assigned; nil before then.
    public let assignedContact: SupportContact?
    /// The server's own name for this conversation — the date it was opened.
    /// Nil only against a server that predates the field, which is what
    /// `title(now:)` is still here to cover.
    public let serverTitle: String?
    /// `status == "closed"`, derived on the server so it can never disagree
    /// with `status`.
    public let resolved: Bool
    /// Whether writing now continues *this* conversation rather than opening
    /// a new one. The 24-hour window behind it lives on the server, in one
    /// place, and this client does not reimplement it — it reads this field.
    public let resumable: Bool

    enum CodingKeys: String, CodingKey {
        case id, status, createdAt, lastMessageAt, messages, assignedContact
        case serverTitle = "title"
        case resolved, resumable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(SupportConversationStatus.self, forKey: .status)
        // Both stamps are decoded permissively. A support thread is a whole
        // screen, and a timestamp the shared ISO-8601 strategy cannot parse —
        // a date with no time in it, say — must cost the reader the line it
        // would have drawn, never the conversation.
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        lastMessageAt = (try? container.decodeIfPresent(Date.self, forKey: .lastMessageAt)) ?? nil
        messages = ((try? container.decodeIfPresent([SupportMessage].self, forKey: .messages)) ?? nil) ?? []
        assignedContact = (try? container.decodeIfPresent(SupportContact.self, forKey: .assignedContact)) ?? nil
        serverTitle = ((try? container.decodeIfPresent(String.self, forKey: .serverTitle)) ?? nil)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let closed = status == .closed
        resolved = ((try? container.decodeIfPresent(Bool.self, forKey: .resolved)) ?? nil) ?? closed
        // A server that does not send `resumable` is one that cannot hold two
        // conversations either, so "keep writing into the one thread there is"
        // is the honest default for it.
        resumable = ((try? container.decodeIfPresent(Bool.self, forKey: .resumable)) ?? nil) ?? !closed
    }

    /// The heading this conversation is read under.
    ///
    /// Explicitly **not** the opening line, and not the person answering
    /// either. Naming a thread after its first message repeats a sentence that
    /// is already on screen as the first message; naming it after the contact
    /// tells the customer the one thing the line beneath it already says.
    /// Named by when it started instead — stable, and the same shape a mail
    /// client gives a thread with no subject.
    ///
    /// The two absences are different and are not collapsed: a thread with no
    /// messages has not started, and "New conversation" is true of it. A thread
    /// that has messages but no `created_at` HAS started and there is simply no
    /// date to name it by — calling that one new would be a sentence about
    /// somebody's open case that is not true. It reads "Support", which is what
    /// the web (`supportThreadTitle`) and Android
    /// (`supportConversationTitle`) both fall back to.
    public func title(now: Date = .now) -> String {
        // The server names the thread by its date now, in the customer's own
        // timezone and its own words. Deriving one here is the fallback, not
        // the rule — two clients naming the same thread differently is how
        // "which conversation is this" stops having an answer.
        if let serverTitle { return serverTitle }
        guard !messages.isEmpty else { return "New conversation" }
        guard let createdAt else { return "Support" }
        let sameYear = Calendar.current.component(.year, from: createdAt)
            == Calendar.current.component(.year, from: now)
        let day = sameYear
            ? createdAt.formatted(.dateTime.month(.abbreviated).day())
            : createdAt.formatted(.dateTime.month(.abbreviated).day().year())
        return "Support \u{00B7} \(day)"
    }
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
/// A guest is issued a token the first time they write in, and again for each
/// new conversation they start; the client keeps every one it is given.
public struct SupportPostResult: Codable, Sendable {
    public let thread: SupportConversation
    public let guestToken: String?
}

/// Who opened the conversation. Rewound writes first when it is reaching out
/// about an order rather than answering a question.
public enum SupportThreadOrigin: String, Codable, Sendable {
    case customer
    case rewound
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// One row of `GET /support/threads` — the customer's list of their own
/// conversations with Rewound.
public struct SupportThreadSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let status: SupportConversationStatus
    /// The date it was opened, as the server words it. Never the first
    /// message — a standing ruling, because a thread named after its opening
    /// line repeats a sentence already on screen.
    public let title: String
    /// `status == "closed"`, derived server-side.
    public let resolved: Bool
    /// Whether writing now continues this conversation. The window is the
    /// server's; this is the answer, not the inputs to it.
    public let resumable: Bool
    public let origin: SupportThreadOrigin
    public let createdAt: Date?
    public let lastMessageAt: Date?
    /// The last message, record references flattened. Empty when the thread
    /// has none.
    public let snippet: String
    public let assignedContact: SupportContact?
    /// Guests only, and absent entirely for a signed-in caller: which of the
    /// tokens the caller presented reached this row. It is their own value
    /// echoed back, not a new grant.
    public let guestToken: String?

    enum CodingKeys: String, CodingKey {
        case id, status, title, resolved, resumable, origin
        case createdAt, lastMessageAt, snippet, assignedContact, guestToken
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(SupportConversationStatus.self, forKey: .status)
        let closed = status == .closed
        // The list is the way into every conversation a customer has. One row
        // whose title or timestamp the decoder dislikes must cost that row a
        // line, never the customer their whole history — so every field below
        // the identity is optional at the wire and has a truthful stand-in.
        title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? "Support"
        resolved = ((try? container.decodeIfPresent(Bool.self, forKey: .resolved)) ?? nil) ?? closed
        resumable = ((try? container.decodeIfPresent(Bool.self, forKey: .resumable)) ?? nil) ?? !closed
        origin = ((try? container.decodeIfPresent(SupportThreadOrigin.self, forKey: .origin)) ?? nil) ?? .unknown
        createdAt = (try? container.decodeIfPresent(Date.self, forKey: .createdAt)) ?? nil
        lastMessageAt = (try? container.decodeIfPresent(Date.self, forKey: .lastMessageAt)) ?? nil
        snippet = ((try? container.decodeIfPresent(String.self, forKey: .snippet)) ?? nil) ?? ""
        assignedContact = (try? container.decodeIfPresent(SupportContact.self, forKey: .assignedContact)) ?? nil
        guestToken = ((try? container.decodeIfPresent(String.self, forKey: .guestToken)) ?? nil)
    }
}
