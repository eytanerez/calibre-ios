import Foundation

/// A watch in the member's Collection. Calibre purchases arrive automatically
/// on delivery (authenticated, with their Passport); manual adds cover the
/// rest of the drawer.
public struct VaultWatch: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let source: String
    /// Server-computed. The rule ("it came from a Calibre order") lives on the
    /// server; re-deriving it from `source` here would be a second copy of a
    /// rule that decides whether a watch claims to be authenticated.
    public let authenticated: Bool
    public let orderId: String?
    public let listingId: String?
    public let passportCode: String?
    public let brand: String?
    public let model: String?
    public let reference: String?
    public let productionYear: Int?
    public let nickname: String?
    public let notes: String?
    public let photoUrl: String?
    public let acquiredPrice: String?
    public let acquiredDate: String?
    public let estimatedValue: String?
    public let estimatedAt: String?
    public let createdAt: String?

    public var displayTitle: String {
        let joined = [brand, model].compactMap { $0 }.joined(separator: " ")
        return nickname ?? (joined.isEmpty ? "Watch" : joined)
    }

    /// True when `displayTitle` is the owner speaking rather than the
    /// catalog. The two read differently and are set differently: a nickname
    /// is written in the hand, a brand and model never are.
    public var isNicknamed: Bool { nickname != nil }
}

/// One of the seller's own watches that a listing being written might be —
/// `GET /vault/matches`.
///
/// Deliberately narrower than `VaultWatch`: the seller is being asked to
/// recognise a watch, not to browse their collection, so no valuation and no
/// private note travels with the question.
public struct VaultMatch: Decodable, Equatable, Sendable, Identifiable {
    public let vaultWatchId: String
    public let brand: String?
    public let model: String?
    public let reference: String?
    /// The day they got it, `yyyy-MM-dd`, and the detail that makes the
    /// question answerable — "the one you bought in March 2024". Null when
    /// the collection entry never recorded one.
    public let acquiredDate: String?
    public let passportCode: String?

    public var id: String { vaultWatchId }

    /// What to call the watch in the prompt: the catalog's words where the
    /// entry has them, otherwise the reference the match was made on.
    public var displayTitle: String {
        let named = [brand, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !named.isEmpty { return named }
        return reference ?? "A watch in your collection"
    }
}

/// The spec sheet Calibre keeps for a reference, in the order a sheet is
/// read in. Every field is optional because the catalog fills up over time —
/// an unfilled field is not a fact, so it is left out rather than shown empty.
public struct WatchReferenceSpecs: Decodable, Equatable, Sendable {
    public let material: String?
    public let bezel: String?
    public let glass: String?
    public let back: String?
    public let shape: String?
    /// Whole millimetres, rendered "41mm".
    public let diameterMm: Int?
    public let finish: String?
    public let dial: String?
    public let indexes: String?
    public let hands: String?

    /// Label/value pairs for a spec list, in sheet order, with the unfilled
    /// fields dropped. A row that reads "—" tells the owner nothing and makes
    /// a half-known reference look like a broken one.
    public var rows: [(label: String, value: String)] {
        var out: [(label: String, value: String)] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            out.append((label, value))
        }
        add("Material", material)
        add("Bezel", bezel)
        add("Glass", glass)
        add("Back", back)
        add("Shape", shape)
        add("Diameter", diameterMm.map { "\($0)mm" })
        add("Finish", finish)
        add("Dial", dial)
        add("Indexes", indexes)
        add("Hands", hands)
        return out
    }

    public var isEmpty: Bool { rows.isEmpty }
}

/// The catalog row a vault watch resolves to, if Calibre has one.
///
/// `inCatalog` is narrower than "a row exists": a row with no spec filled in
/// is a name and nothing else. It can still carry a published price, so the
/// row comes back either way — but the detail page still offers the owner the
/// catalog-gap form, because nothing on it can answer "what is this watch".
public struct VaultReferenceRow: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let slug: String
    public let brand: String?
    public let model: String?
    public let reference: String?
    public let specs: WatchReferenceSpecs
    public let inCatalog: Bool
}

/// One service visit recorded against a watch.
public struct VaultServiceRecord: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let vaultWatchId: String
    public let servicedAt: String?
    public let provider: String?
    public let details: String?
    public let cost: String?
    public let createdAt: String?
}

/// `GET /vault/{id}` — the watch itself plus what only the detail route asks
/// for. The payload is flat, so the watch decodes from the same container.
public struct VaultWatchDetail: Decodable, Equatable, Sendable, Identifiable {
    public let watch: VaultWatch
    public let serviceRecords: [VaultServiceRecord]
    /// nil when the collection entry resolves to no catalog row at all.
    public let referenceRow: VaultReferenceRow?
    /// This watch already has a suggestion waiting on a reviewer.
    public let pendingSuggestion: Bool

    public var id: String { watch.id }

    private enum CodingKeys: String, CodingKey {
        case serviceRecords, referenceRow, pendingSuggestion
    }

    public init(from decoder: Decoder) throws {
        watch = try VaultWatch(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceRecords = try container.decode([VaultServiceRecord].self, forKey: .serviceRecords)
        referenceRow = try container.decodeIfPresent(VaultReferenceRow.self, forKey: .referenceRow)
        pendingSuggestion = try container.decode(Bool.self, forKey: .pendingSuggestion)
    }
}

/// What the owner gets back after telling us about a watch we don't have.
/// It is not a catalog row — it is evidence waiting on a reviewer.
public struct ReferenceSuggestion: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let brand: String?
    public let model: String?
    public let reference: String?
    public let productionYear: Int?
    public let notes: String?
    public let specs: WatchReferenceSpecs
    public let submittedAt: String?
    public let resolvedAt: String?
}

/// The ten spec fields as the owner typed them. Blank fields are left out of
/// the request rather than sent empty: an untouched field is not an
/// instruction to clear one.
public struct WatchReferenceSpecsDraft: Equatable, Sendable {
    public var material = ""
    public var bezel = ""
    public var glass = ""
    public var back = ""
    public var shape = ""
    public var diameterMm = ""
    public var finish = ""
    public var dial = ""
    public var indexes = ""
    public var hands = ""

    public init() {}

    public var isEmpty: Bool {
        [material, bezel, glass, back, shape, diameterMm, finish, dial, indexes, hands]
            .allSatisfy { !InputValidation.isNonBlank($0) }
    }
}

/// One in-app notification (server-side inbox shared with the web bell).
public struct ServerNotification: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let category: String
    public let title: String
    public let body: String
    public let route: String
    public let readAt: String?
    public let createdAt: String?
}

public struct ServerNotificationList: Decodable, Equatable, Sendable {
    public let results: [ServerNotification]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let unreadCount: Int
}

public struct SavedSearchSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let lastMatchedAt: String?
    public let createdAt: String?
}
