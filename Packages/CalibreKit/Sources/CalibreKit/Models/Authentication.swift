import Foundation

// MARK: - The record

/// The five stages a watch moves through at the authentication centre.
public enum AuthenticationStage: String, Codable, Sendable {
    case incoming, inHand = "in_hand", ready, shipped, closed
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AuthenticationStage(rawValue: raw) ?? .unknown
    }
}

/// What the bench is doing inside a stage. `onHold` is the one a customer sees.
public enum AuthenticationStep: String, Codable, Sendable {
    case received, started, investigating, onHold = "on_hold", service, completed
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AuthenticationStep(rawValue: raw) ?? .unknown
    }
}

/// The stored report, as the order and the vault advertise it.
public struct AuthenticationReportRef: Codable, Sendable, Hashable {
    public let version: Int
    public let issuedAt: Date?
    /// Served through the permission-checked media proxy. Never a shareable link.
    public let pdfUrl: MediaURL?
}

/// The case this order is under, when it is under one.
public struct OrderCaseRef: Codable, Sendable, Hashable {
    public let id: String
    public let status: String
    /// True when a live proposal is waiting on this party's answer.
    public let awaitingYou: Bool?
    public let hasProposal: Bool?
}

/// `order.authentication` — the bench's record, as a customer may read it.
///
/// Deliberately thin, and the bench's own words are not in it. WPB write for
/// WPB; their notes are evidence on a record, not a message to the person whose
/// watch it is. Until this build the app printed `auth_result.notes` verbatim
/// under "Authentication issue".
///
/// Optional on `Order` for a reason worth keeping straight: nil means the
/// server said nothing, which is what an older deployment does. It never means
/// "no".
public struct OrderAuthentication: Codable, Sendable, Hashable {
    public let recordId: String
    /// `1041`, or `1041-R` for a return check. The order's own number.
    public let number: String
    public let kind: String
    public let stage: AuthenticationStage
    public let step: AuthenticationStep
    public let holdReason: String?
    public let verdict: String?
    public let serviceRecommended: Bool?
    /// When the bench confirmed the watch was in their hands — NOT the
    /// carrier's delivered scan. A parcel reaching a building and a watch
    /// reaching a person are different facts, and only this one can be
    /// confirmed by somebody who opened the box.
    public let arrivedAt: Date?
    /// The day the bench expects to be finished, as a calendar day.
    ///
    /// `expected_out_on` is a `Date` column and arrives as bare `YYYY-MM-DD`
    /// (`_serialize_authentication` calls `.isoformat()` on a `date`). Two
    /// things follow, and the first is the reason this initializer exists at
    /// all: `ISO8601DateFormatter` returns nil for a string with no time, so
    /// the decoder every payload goes through **threw** on it — and because
    /// the synthesized initializer let that throw travel, one bench date took
    /// the whole `Order` with it, and with it the order page and every row of
    /// a list it appeared in. Nothing read this field, so nothing looked wrong;
    /// the order simply failed to load.
    ///
    /// The second is that a calendar day is not an instant. Read as midnight
    /// UTC it is the day before the one the bench wrote down for every reader
    /// west of Greenwich — told to them confidently. It is built from its own
    /// components against the reader's calendar instead, so the day that comes
    /// back out is the day that went in. Anything carrying a time is an
    /// instant and is still read as one.
    public let expectedOutOn: Date?
    public let shippedAt: Date?
    public let report: AuthenticationReportRef?
    public let authCase: OrderCaseRef?

    private enum CodingKeys: String, CodingKey {
        case recordId, number, kind, stage, step, holdReason, verdict
        case serviceRecommended, arrivedAt, expectedOutOn, shippedAt, report
        // `case` is a keyword, so the wire name is spelled out here rather
        // than relying on the snake-case conversion.
        case authCase = "case"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordId = try container.decode(String.self, forKey: .recordId)
        number = try container.decode(String.self, forKey: .number)
        kind = try container.decode(String.self, forKey: .kind)
        stage = try container.decode(AuthenticationStage.self, forKey: .stage)
        step = try container.decode(AuthenticationStep.self, forKey: .step)
        holdReason = try container.decodeIfPresent(String.self, forKey: .holdReason)
        verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        serviceRecommended = try container.decodeIfPresent(Bool.self, forKey: .serviceRecommended)
        arrivedAt = try container.decodeIfPresent(Date.self, forKey: .arrivedAt)
        expectedOutOn = try CalendarDay.decode(from: container, forKey: .expectedOutOn)
        shippedAt = try container.decodeIfPresent(Date.self, forKey: .shippedAt)
        report = try container.decodeIfPresent(AuthenticationReportRef.self, forKey: .report)
        authCase = try container.decodeIfPresent(OrderCaseRef.self, forKey: .authCase)
    }

    /// A person at Calibre is looking at this watch more closely.
    ///
    /// A state of the RECORD, not of the order: the order sits at `to_auth`
    /// throughout, which is why nothing before this could tell a hold from
    /// ordinary progress.
    public var isHeld: Bool { stage == .inHand && step == .onHold }

    /// What a hold is called out loud.
    ///
    /// Here rather than in a view because the order's lead and the card a
    /// seller surface can draw must say the same thing, and two copies of a
    /// paragraph are two copies to keep in step.
    public var holdTitle: String { "We are taking a closer look at your watch" }

    /// The paragraph under it.
    ///
    /// The reason for the hold is not named. It is private to the two parties
    /// while it is open, and naming it would be Calibre's finding announced
    /// before Calibre has finished making it — which is why a service hold and
    /// every other hold deliberately differ only in what they promise next.
    public var holdBody: String {
        if holdReason == "service" || serviceRecommended == true {
            return "Our authentication centre found something worth a second opinion on how this watch is running. "
                + "Nothing is decided and nothing has changed about your order. A person at Calibre is reviewing it "
                + "and will write to you with what we found and what we suggest."
        }
        return "Your watch is with our authentication centre and a person at Calibre is reviewing it before it goes "
            + "any further. Nothing is decided yet. We will write to you with what we found, and you will be asked "
            + "before anything about your order changes."
    }
}

/// A calendar day on the wire, read as a calendar day.
///
/// Kept apart from the decoder's own date strategy because the two are reading
/// different things. That strategy reads an *instant* — a moment the same all
/// over the world — and every other date in these payloads is one. A day the
/// bench wrote on a record is not: it is a square on a calendar, and the reader
/// should see the square, not the moment its edge falls on in their zone.
enum CalendarDay {
    /// The day at the reader's own midnight, or nil.
    ///
    /// Nil rather than a throw is the deliberate part. This is one line on a
    /// screen full of them, and a value that cannot be read must cost that line
    /// and nothing else — never the record it sits on, and never the order page
    /// behind that. Every reader of the field already treats nil as "we were
    /// not told", which is exactly what an unreadable value means.
    static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date? {
        guard container.contains(key) else { return nil }
        // `try?` flattens here, so a null and a value of the wrong JSON type
        // both arrive as nil and both fall through to the line below.
        if let raw = try? container.decodeIfPresent(String.self, forKey: key), let day = day(from: raw) {
            return day
        }
        // Not the date-only shape: a deployment sending a timestamp here is
        // sending an instant, and the decoder's own strategy is what reads one.
        return try? container.decodeIfPresent(Date.self, forKey: key)
    }

    /// `YYYY-MM-DD` and nothing else — built from its own components against
    /// the reader's calendar, which is what makes the day survive the trip.
    static func day(from raw: String) -> Date? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2])
        else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: dayOfMonth))
    }
}

// MARK: - The report

/// The filed report, both media at once.
///
/// `html` is the exact document that was stored, read back and never
/// re-rendered, and it is self-contained — fonts, photographs and both QR codes
/// travel inside it — so it displays with no network of its own.
public struct AuthenticationReport: Codable, Sendable {
    public let html: String
    public let pdfUrl: MediaURL?
    public let version: Int
    public let issuedAt: Date?
    public let downloadFilename: String?
}

// MARK: - The case

public struct AuthCaseService: Codable, Sendable {
    public let amount: String?
    public let payer: String?
    public let yourShare: String?
    public let paymentUrl: MediaURL?
    public let paidAt: Date?
    public let paidDirectlyTo: String?
    public let statementDescriptorNote: String?
    public let warranty: String?
}

/// The offer on the table.
///
/// Both parties are shown both figures. That is the decision and it is the
/// opposite of the obvious one: an asymmetric proposal collapses the moment
/// either side screenshots it. Calibre's own remainder is not in this payload.
public struct AuthCaseProposal: Codable, Sendable {
    public let id: String
    public let refundAmount: String?
    public let payoutAmount: String?
    public let stripeFee: String?
    public let stripeFeeBearer: String?
    public let buyerReceives: String?
    public let sellerReceives: String?
    public let currency: String?
    public let service: AuthCaseService?
    public let youAcceptedAt: Date?
    public let otherPartyAccepted: Bool?
    public let declinedBy: String?
    public let declinedAt: Date?
    public let canRespond: Bool?
    public let createdAt: Date?
}

public struct AuthCaseProposalPayload: Codable, Sendable {
    public let caseId: String
    public let status: String
    public let orderNumber: Int?
    public let youAre: String
    public let summary: String?
    public let proposal: AuthCaseProposal?
    public let awaitingYou: Bool?
}

/// The answer, and what it set off.
///
/// `settlement` is nil while the other side has not answered, and carries a
/// status of `failed` when the pair completed and the money did not move. A
/// failure is still a success for the person who answered: their acceptance is
/// a fact about them, and telling them it did not work would ask them to agree
/// twice.
public struct AuthCaseResponse: Codable, Sendable {
    public struct Settlement: Codable, Sendable {
        public let status: String
    }

    public let caseId: String
    public let status: String
    public let youAre: String
    public let accepted: Bool
    public let proposal: AuthCaseProposal?
    public let settlement: Settlement?
}

public struct AuthCaseDiscrepancyPhoto: Codable, Sendable, Identifiable {
    public let id: String
    public let slot: String
    public let url: MediaURL?
    public let caption: String?
}

/// What we found, as a page rather than a file.
///
/// A PDF leaves the permission system the moment it is downloaded, and this
/// document names what is wrong with one identifiable person's watch. Every
/// photograph here is a proxy path that re-checks permission on the way to the
/// bytes.
public struct AuthCaseDiscrepancy: Codable, Sendable {
    public let caseId: String
    public let orderNumber: Int?
    public let recordNumber: String?
    public let openedAt: Date?
    public let summary: String?
    public let faultTypes: [String]?
    public let notes: String?
    public let photos: [AuthCaseDiscrepancyPhoto]?
}

// MARK: - Calls

extension APIClient {
    /// The order's own report. Owner-only, and permission-checked on every read.
    public func authenticationReport(orderID: String) async throws -> AuthenticationReport {
        try await send(Endpoint(path: "/orders/\(orderID)/authentication-report"))
    }

    /// The same document, reached from a watch in the owner's collection.
    public func vaultAuthenticationReport(vaultID: String) async throws -> AuthenticationReport {
        try await send(Endpoint(path: "/vault/\(vaultID)/authentication-report"))
    }

    public func authCaseProposal(caseID: String) async throws -> AuthCaseProposalPayload {
        try await send(Endpoint(path: "/auth-cases/\(caseID)/proposal"))
    }

    public func respondToAuthCase(caseID: String, accept: Bool) async throws -> AuthCaseResponse {
        try await send(
            Endpoint.json(method: .post, path: "/auth-cases/\(caseID)/respond", payload: ["accept": accept])
        )
    }

    public func authCaseDiscrepancy(caseID: String) async throws -> AuthCaseDiscrepancy {
        try await send(Endpoint(path: "/auth-cases/\(caseID)/discrepancy"))
    }
}
