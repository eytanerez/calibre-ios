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
    /// Narrowed by the server rather than renamed: it now carries a figure in
    /// the `ok` state and null in every other. Nothing consumer-facing prints
    /// it — see `VaultEstimate` for the whole answer and for why.
    public let estimatedValue: String?
    public let estimatedAt: String?
    /// Absent on a payload served by a deployment that predates the estimate
    /// block, and absent has to stay absent: inventing a state for it would
    /// put a sentence about evidence under a watch nobody looked up.
    public let estimate: VaultEstimate?
    public let createdAt: String?

    public var displayTitle: String {
        let joined = [brand, model].compactMap { $0 }.joined(separator: " ")
        return nickname ?? (joined.isEmpty ? "Watch" : joined)
    }

    /// True when `displayTitle` is the owner speaking rather than the
    /// catalog. The two read differently and are set differently: a nickname
    /// is written in the hand, a brand and model never are.
    public var isNicknamed: Bool { nickname != nil }

    /// The stamp's key on the vault detail, and the fact it stands for. Nil
    /// where Calibre does not vouch for this watch, and nil is the whole gate.
    ///
    /// Read `authenticated` literally. It is the server's own answer to "does
    /// Calibre stand behind this watch" (`_is_authenticated` in
    /// `app/api/views/vault.py`), computed there precisely so the claim cannot
    /// come to mean three slightly different things on three platforms — and
    /// re-deriving it here from `source` would be that second copy. It is
    /// **not** a passport code and it is not a position in any sequence: a
    /// mark keyed to a step of a journey stamps whatever is standing on that
    /// step, including a watch that got there by failing.
    ///
    /// It is also not `Order.authentication.verdict`, which is what the order
    /// screen's stamp reads. This payload carries no verdict string at all —
    /// `GET /vault/{id}` has no authentication block — so the two surfaces
    /// gate on the two different facts their two payloads actually carry,
    /// rather than one of them inferring the other's. The web's vault detail
    /// gates its stamp on this same flag.
    ///
    /// The key names the event and not the screen, so a watch already stamped
    /// in this session stands still when the screen is opened again.
    public var authenticationMarkKey: String? {
        guard authenticated else { return nil }
        return "vault-authenticated:\(id)"
    }
}

/// What Calibre will say about a watch's worth, or why it will not.
///
/// The server keeps the states apart because they are different sentences to
/// whoever reads them, and only `ok` carries a figure — so an absence can
/// never be read as a figure of zero, and a zero under `ok` is a real one.
///
/// `state` stays a `String` on the wire side. A state this build has never
/// heard of has to arrive as itself rather than throwing the whole collection
/// away or being folded into a neighbouring state that says something else.
public struct VaultEstimate: Decodable, Equatable, Sendable {
    public let state: String
    /// Carried only by `ok`. No Calibre surface prints it.
    public let value: String?
    public let asOf: String?
    public let scope: String?
    public let basis: String?
    public let sampleSize: Int?
    public let windowDays: Int?

    public var kind: VaultEstimateState? { VaultEstimateState(rawValue: state) }
}

/// The five answers `GET /vault` can give about a figure
/// (`app/services/market_stats.py`).
public enum VaultEstimateState: String, Sendable {
    case ok
    case stale
    case insufficientEvidence = "insufficient_evidence"
    case unidentified
    case notEstimated = "not_estimated"
}

public extension VaultEstimate {
    /// The sentence an owner is shown, or none.
    ///
    /// Calibre's estimate of somebody's own watch is never printed as a figure
    /// — that decision is settled and this property does not reopen it. What
    /// these sentences do is explain an ABSENCE the owner can already see, and
    /// only the two refusals have an absence to explain:
    ///
    /// - `ok` — there is a current figure and no surface prints one. "We have
    ///   it and will not show it" is worse than saying nothing.
    /// - `stale` — the same, about a figure that has outlived its window.
    ///   Fresh or stale is a distinction about a number nobody sees.
    /// - `notEstimated` — nobody has looked yet, so there is nothing to explain.
    /// - an unrecognised state — this build cannot know what it means, and a
    ///   guess would be a sentence about somebody's watch that Calibre never
    ///   said.
    ///
    /// The two that speak must never collapse into one line: not knowing WHICH
    /// watch this is and having looked at the right watch and found too little
    /// are different findings, and the second one means the reference is
    /// understood.
    ///
    /// So the two sentences are built to stay apart in the reading, not only in
    /// the switch:
    ///
    /// - `unidentified` names the failure — Calibre could not tell which watch
    ///   this is from the brand and reference on it — and says the consequence,
    ///   that it has not been valued. Nothing in it claims the reference is
    ///   known, because it is not.
    /// - `insufficientEvidence` opens by granting the reference ("We know this
    ///   reference") and only then withholds the figure, because that
    ///   concession is the whole difference between the two. It is worded
    ///   verbatim as the web words it in `frontend/src/lib/vaultApi.ts`: the
    ///   same refusal reaching the same owner through two surfaces has to
    ///   reach them in the same words.
    var note: String? {
        switch kind {
        case .unidentified:
            "Calibre could not tell which watch this is from the brand and reference on it, so it has not been valued."
        case .insufficientEvidence:
            "We know this reference, but too few have sold to show a price yet."
        case .ok, .stale, .notEstimated, .none:
            nil
        }
    }
}

/// The owner's photograph of their own watch, as a link.
///
/// Calibre has no endpoint that stores a picture for a watch in somebody's
/// vault — `vault_watches.photo_url` is a link and there is nothing behind it
/// that would take an upload. So the app asks for a link and says that is what
/// it is asking for; it does not offer a picker it could not honour.
public enum VaultPhotoLink {
    /// Only https, and only one that parses.
    ///
    /// Everything else a URL field can be handed — `http:` (which the app
    /// will not load), `javascript:`, `data:`, a bare filename — is not a
    /// photograph either, and saving one stores a value that renders as
    /// nothing.
    public static func usable(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }
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
        return reference ?? "A watch in your Vault"
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
    /// The query this search stands for, exactly as the server stores it —
    /// `brand`, `model`, `reference`, `search`, `condition`, `year`,
    /// `price_min`, `price_max`, `box_papers` (`SAVED_SEARCH_FILTER_KEYS` in
    /// Backend/app/api/views/alerts.py). `_serialize_saved_search` has always
    /// sent this key; the app simply never decoded it, which is why a saved
    /// search could be listed and deleted but never re-run.
    ///
    /// Values arrive typed as JSON — `year` is a number, `box_papers` a bool —
    /// so they are decoded loosely and normalised to the strings the browse
    /// query builder takes.
    public let filters: [String: String]
    public let lastMatchedAt: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, filters, lastMatchedAt, createdAt
    }

    public init(
        id: String,
        name: String,
        filters: [String: String] = [:],
        lastMatchedAt: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.filters = filters
        self.lastMatchedAt = lastMatchedAt
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        lastMatchedAt = try container.decodeIfPresent(String.self, forKey: .lastMatchedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        let raw = (try? container.decodeIfPresent([String: JSONScalar].self, forKey: .filters))
            .flatMap { $0 } ?? [:]
        filters = Dictionary(
            uniqueKeysWithValues: raw.compactMap { key, value in
                value.stringValue.map { (Self.wireKey(for: key), $0) }
            }
        )
    }

    /// `APIClient` decodes with `.convertFromSnakeCase`, and that strategy
    /// applies to **dictionary keys** as well as to coding keys — so the
    /// server's `price_min` arrives here already renamed to `priceMin`. The
    /// browse query builder and the create/update payload both speak the
    /// server's snake_case, so the keys are put back before anything reads
    /// them. Without this a saved search with a price range re-runs as a
    /// search with no price range: no crash, no error, just the wrong result
    /// set.
    private static func wireKey(for decodedKey: String) -> String {
        switch decodedKey {
        case "priceMin": "price_min"
        case "priceMax": "price_max"
        case "boxPapers": "box_papers"
        default: decodedKey
        }
    }
}

/// One JSON value of the handful of shapes a saved-search filter can hold.
/// Narrower than a general JSON decoder on purpose: a filter is a scalar, and
/// anything else is a payload this app does not understand.
enum JSONScalar: Decodable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: nil
        }
    }
}
