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

    /// A person at Calibre is looking at this watch more closely.
    ///
    /// A state of the RECORD, not of the order: the order sits at `to_auth`
    /// throughout, which is why nothing before this could tell a hold from
    /// ordinary progress.
    public var isHeld: Bool { stage == .inHand && step == .onHold }
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
