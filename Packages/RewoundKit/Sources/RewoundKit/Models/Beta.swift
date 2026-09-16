import Foundation

/// The beta program, as the app receives it.
///
/// Nothing here is a copy of the survey. The questions, their options, the
/// branching and the welcome letter are defined once, in
/// `Backend/app/services/beta_program.py`, and the app renders whatever
/// `GET /beta/config` hands it. That is deliberate: three hand-written copies
/// of a forty-question survey drift apart inside a week, and a renamed option
/// on the website with the old one still shipping in a TestFlight build means
/// two answers to the same question that can never be counted together — with
/// nothing anywhere going red to say so.
///
/// It also means a question can be added, reworded or removed while build 27 is
/// still in review, and every tester sees the change immediately.

// MARK: - Config

public struct BetaConfig: Decodable, Sendable {
    public let enabled: Bool
    public let welcome: BetaWelcome?
    public let bar: BetaBarCopy?
    public let testCard: BetaTestCard?
    public let form: BetaForm?

    private enum CodingKeys: String, CodingKey {
        case enabled, welcome, bar, form
        case testCard = "test_card"
    }

    /// What the app shows when the program is off, and when the config could
    /// not be fetched at all. Both are "there is no beta here", which is the
    /// only safe reading of "we do not know".
    public static let off = BetaConfig(enabled: false, welcome: nil, bar: nil, testCard: nil, form: nil)

    public init(
        enabled: Bool,
        welcome: BetaWelcome?,
        bar: BetaBarCopy?,
        testCard: BetaTestCard?,
        form: BetaForm?
    ) {
        self.enabled = enabled
        self.welcome = welcome
        self.bar = bar
        self.testCard = testCard
        self.form = form
    }
}

public struct BetaWelcome: Decodable, Sendable {
    public let title: String
    public let body: [String]
    public let signoff: String
}

public struct BetaBarCopy: Decodable, Sendable {
    public let text: String
    public let action: String
}

public struct BetaTestCard: Decodable, Sendable {
    public let number: String
    public let expiry: String
    public let cvc: String
    public let caption: String
    public let note: String
}

public struct BetaForm: Decodable, Sendable {
    public let catalogueVersion: String
    public let kindQuestion: String
    public let kinds: [BetaKindChoice]
    /// Keyed by kind. The app looks up the door the tester chose and renders it.
    public let sections: [String: [BetaSection]]

    private enum CodingKeys: String, CodingKey {
        case kinds, sections
        case catalogueVersion = "catalogue_version"
        case kindQuestion = "kind_question"
    }
}

public struct BetaKindChoice: Decodable, Sendable, Identifiable {
    public let value: String
    public let label: String
    public let description: String?

    public var id: String { value }
}

public struct BetaSection: Decodable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let questions: [BetaQuestion]
}

public struct BetaOption: Decodable, Sendable, Identifiable, Hashable {
    public let value: String
    public let label: String

    public var id: String { value }
}

public struct BetaCondition: Decodable, Sendable {
    public let question: String
    public let anyOf: [String]

    private enum CodingKeys: String, CodingKey {
        case question
        case anyOf = "any_of"
    }
}

public struct BetaQuestion: Decodable, Sendable, Identifiable {
    public let id: String
    /// `single`, `multi`, `scale`, `text`, `longtext`, `email`, `matrix`,
    /// `files`. A plain String rather than an enum on purpose: a build shipped
    /// today must not crash on a question type added to the catalog next
    /// month. `BetaAnswerKind` below does the interpreting, and answers
    /// `unsupported` for anything it does not recognize.
    public let type: String
    public let prompt: String
    public let help: String?
    public let options: [BetaOption]?
    public let rows: [BetaOption]?
    public let min: Int?
    public let max: Int?
    public let minLabel: String?
    public let maxLabel: String?
    public let maxSelect: Int?
    public let showWhen: BetaCondition?

    private enum CodingKeys: String, CodingKey {
        case id, type, prompt, help, options, rows, min, max
        case minLabel = "min_label"
        case maxLabel = "max_label"
        case maxSelect = "max_select"
        case showWhen = "show_when"
    }
}

/// The eight shapes this build knows how to draw, plus the one it does not.
public enum BetaAnswerKind: Sendable {
    case single, multi, scale, text, longtext, email, matrix, files
    case unsupported

    public init(_ raw: String) {
        switch raw {
        case "single": self = .single
        case "multi": self = .multi
        case "scale": self = .scale
        case "text": self = .text
        case "longtext": self = .longtext
        case "email": self = .email
        case "matrix": self = .matrix
        case "files": self = .files
        default: self = .unsupported
        }
    }
}

// MARK: - Answers

/// One answer, in whichever of the four shapes its question calls for.
///
/// A closed enum rather than a free-form JSON value: these are the only four
/// things the server accepts, so anything else is a bug that should not compile
/// rather than one that arrives as a 400 after somebody has typed for fifteen
/// minutes.
public enum BetaAnswer: Sendable, Equatable {
    case text(String)
    case number(Int)
    case choices([String])
    case matrix([String: String])

    /// Whether this counts as having said something. An empty string, an empty
    /// list and an empty map are all "not answered" — a question the tester
    /// opened and left.
    public var isEmpty: Bool {
        switch self {
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number: return false
        case .choices(let values): return values.isEmpty
        case .matrix(let values): return values.isEmpty
        }
    }

    /// Whether the condition `anyOf` is satisfied by this answer.
    public func matches(anyOf wanted: [String]) -> Bool {
        switch self {
        case .text(let value): return wanted.contains(value)
        case .number(let value): return wanted.contains(String(value))
        case .choices(let values): return values.contains { wanted.contains($0) }
        case .matrix: return false
        }
    }
}

extension BetaAnswer: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .choices(let values): try container.encode(values)
        case .matrix(let values): try container.encode(values)
        }
    }
}

// MARK: - Demo fill

public struct BetaDemoFill: Decodable, Sendable {
    public let account: Account
    public let address: Address
    public let listing: [String: String]
    public let card: BetaTestCard?

    public struct Account: Decodable, Sendable {
        public let firstName: String
        public let lastName: String
        public let username: String
        public let email: String
        public let password: String
        public let phone: String

        private enum CodingKeys: String, CodingKey {
            case username, email, password, phone
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    public struct Address: Decodable, Sendable {
        public let firstName: String
        public let lastName: String
        public let phone: String
        public let line1: String
        public let line2: String
        public let city: String
        public let region: String
        public let postalCode: String
        public let country: String

        private enum CodingKeys: String, CodingKey {
            case phone, line1, line2, city, region, country
            case firstName = "first_name"
            case lastName = "last_name"
            case postalCode = "postal_code"
        }
    }
}

// MARK: - Attachments

public struct BetaAttachment: Decodable, Sendable, Identifiable {
    public let id: String
    public let filename: String
    public let contentType: String
    public let sizeBytes: Int

    private enum CodingKeys: String, CodingKey {
        case id, filename
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
    }
}

public struct BetaSubmissionReceipt: Decodable, Sendable {
    public let id: String
}
