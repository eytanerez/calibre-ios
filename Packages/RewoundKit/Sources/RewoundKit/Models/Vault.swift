import Foundation

/// A watch in the member's Collection. Rewound purchases arrive automatically
/// on delivery (authenticated, with their Passport); manual adds cover the
/// rest of the drawer.
public struct VaultWatch: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let source: String
    /// Server-computed. The rule ("it came from a Rewound order") lives on the
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
    /// The raw link column, kept and served for the row's own sake — a watch
    /// that arrived from a Rewound order carries the seller's photograph here.
    ///
    /// **Nothing draws this.** `coverUrl` is what a surface renders; a client
    /// that keeps drawing the link shows the seller's picture after the owner
    /// has uploaded their own. It is not writable from this app any more
    /// either: the link form is gone (contracts §9d) and the picker replaced
    /// it, so a PATCH from here never names the column and never wipes it.
    public let photoUrl: String?
    /// What the card and the hero draw: the owner's first uploaded photograph
    /// where they have one, and `photoUrl` until then. Resolved by the server
    /// (`_cover_url`) so the rule is stated once for every surface rather than
    /// three times slightly differently.
    ///
    /// Private-media covers are root-relative paths that need the member's own
    /// credential; `VaultCoverSource` is what decides which kind of address
    /// this is before anything fetches it.
    public private(set) var coverUrl: MediaURL?
    /// The owner's own gallery, in the order they arranged it — index zero is
    /// the cover. Optional because a payload served by a deployment that
    /// predates the gallery carries no key at all, and an absent gallery is
    /// not the same claim as an empty one.
    public private(set) var photos: [VaultPhoto]?
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

    /// The gallery as a list to draw. An absent key and an empty gallery are
    /// the same thing to a grid — both mean "nothing to lay out" — and only
    /// `photos` itself keeps the two apart for anyone who has to know.
    public var gallery: [VaultPhoto] { photos ?? [] }

    /// This row redrawn against the answer a gallery verb just gave.
    ///
    /// All four photo routes answer with the gallery AND the cover, precisely
    /// so the card behind the sheet does not have to re-fetch the watch to
    /// find out that the picture on it has changed. Nothing else on the row
    /// moved, so nothing else is touched.
    public func applying(_ gallery: VaultGallery) -> VaultWatch {
        var updated = self
        updated.coverUrl = gallery.coverUrl
        updated.photos = gallery.results
        return updated
    }

    /// The stamp's key on the vault detail, and the fact it stands for. Nil
    /// where Rewound does not vouch for this watch, and nil is the whole gate.
    ///
    /// Read `authenticated` literally. It is the server's own answer to "does
    /// Rewound stand behind this watch" (`_is_authenticated` in
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

    /// A stand-in row for the Vault's loading skeleton. Decoded the way the
    /// API decodes, so a field added to the model later does not break it:
    /// anything not named here is simply absent.
    public static func skeleton(_ index: Int = 0) -> VaultWatch {
        // Numbered, because each row registers its photograph as a zoom
        // source under its id and five rows sharing one would collide.
        let json = """
        {"id": "skeleton-\(index)", "source": "rewound_order", "authenticated": true,
         "brand": "Brand", "model": "Watch model name", "reference": "000000",
         "production_year": 2020, "estimated_value": "10000.00"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // The literal is fixed and covered by a test, so this cannot fail at
        // runtime short of the model losing one of these fields.
        return try! decoder.decode(VaultWatch.self, from: Data(json.utf8))
    }
}

/// What Rewound will say about a watch's worth, or why it will not.
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
    /// Carried only by `ok`. No Rewound surface prints it.
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
    /// Rewound's estimate of somebody's own watch is never printed as a figure
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
    ///   guess would be a sentence about somebody's watch that Rewound never
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
    /// - `unidentified` names the failure — Rewound could not tell which watch
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
            "Rewound could not tell which watch this is from the brand and reference on it, so it has not been valued."
        case .insufficientEvidence:
            "We know this reference, but too few have sold to show a price yet."
        case .ok, .stale, .notEstimated, .none:
            nil
        }
    }
}

/// One photograph the owner took of their own watch.
///
/// `url` is a path Rewound serves behind the member's session, never a signed
/// address anyone can open — see `VaultCoverSource` for what that costs a
/// client that wants to draw it. It is nil rather than a public fallback when
/// the stored object cannot be addressed at all, and a nil there means the
/// photograph is unreadable, not that it is public.
public struct VaultPhoto: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let url: MediaURL?
    public let contentType: String?
    public let sizeBytes: Int?
    /// Measured off the bytes that were stored, and both or neither.
    public let width: Int?
    public let height: Int?
    /// Zero-based and dense. The server renumbers the whole gallery on every
    /// insert, delete and move, so position zero is always occupied and is
    /// always the cover.
    public let position: Int
    public let createdAt: String?

    public init(
        id: String,
        url: MediaURL?,
        contentType: String? = nil,
        sizeBytes: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        position: Int,
        createdAt: String? = nil
    ) {
        self.id = id
        self.url = url
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.width = width
        self.height = height
        self.position = position
        self.createdAt = createdAt
    }
}

/// What every one of the four photo routes answers with — the gallery in its
/// arranged order, and the cover as it now stands.
///
/// One shape for list, add, delete and move, so there is one parser here and
/// no branch on which verb was just called. The cover rides along because all
/// four verbs can change it.
public struct VaultGallery: Decodable, Equatable, Sendable {
    /// How many photographs one watch may hold — `MAX_VAULT_PHOTOS` on the
    /// server, which is the authority. This copy exists so the picker can stop
    /// offering slots that would only be refused; a client that ever drifts
    /// from it is corrected by the refusal itself, which arrives with the
    /// server's own sentence and `details.code = "vault_photo_limit"`.
    public static let maximum = 8

    public let results: [VaultPhoto]
    public let coverUrl: MediaURL?

    public init(results: [VaultPhoto], coverUrl: MediaURL?) {
        self.results = results
        self.coverUrl = coverUrl
    }
}

/// `POST`'s answer: the gallery, plus the photograph that was just created so
/// a caller need not diff the list to find it.
public struct VaultGalleryAddition: Decodable, Equatable, Sendable {
    public let results: [VaultPhoto]
    public let coverUrl: MediaURL?
    public let photo: VaultPhoto

    public var gallery: VaultGallery { VaultGallery(results: results, coverUrl: coverUrl) }
}

/// Where a vault picture actually lives, and therefore how it may be fetched.
///
/// A `cover_url` can be any of three things, and they are not interchangeable:
///
/// - The owner's own photograph, served at `/secure-media/vault_photos/…` by
///   Rewound itself, behind the member's session. A plain image loader gets a
///   401 and draws nothing, so these have to be fetched by the app's
///   authenticated client and handed to the view as bytes.
/// - Rewound's own **public** media — `/media/…` on the same host, which is
///   what a seeded demo watch and a listing's own photographs are. Nothing
///   guards those, so nothing needs to send a credential to them, and they go
///   through the ordinary image pipeline like every other picture in the app.
/// - `photo_url` pointing at somebody else's host. That one must be loaded
///   WITHOUT the member's credential: attaching a bearer token to an
///   off-origin request hands the session to whoever runs that host, and the
///   picture is public anyway.
///
/// So the reserved prefix is the test, not merely the host — the second and
/// third of those are the same kind of fetch, and treating every same-origin
/// address as private would put the token on public files and hold them in a
/// cache meant for somebody's private pictures.
///
/// Anything that is none of the three — `javascript:`, `data:`, a bare
/// filename, an off-origin `http:` — resolves to nothing: none of them is a
/// photograph, and the app will not load them.
public enum VaultCoverSource: Equatable, Sendable {
    /// Rewound's own object, readable only with the member's credential.
    case privateMedia(URL)
    /// A picture anyone may fetch. No credential.
    case link(URL)

    /// The prefix Rewound serves permission-checked objects under
    /// (`register_private_media_resolver`). Everything behind it is somebody's
    /// in particular; everything outside it is not.
    static let privatePrefix = "/secure-media/"

    public var url: URL {
        switch self {
        case .privateMedia(let url), .link(let url): url
        }
    }

    /// Which kind of address this is, against the origin the app talks to.
    ///
    /// `MediaURL` has already rebased a root-relative path onto that origin by
    /// the time this is asked, so both halves of the question — whose host,
    /// and which prefix — can be read off the one URL.
    public static func resolve(_ url: URL?, apiOrigin: URL) -> VaultCoverSource? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host(), !host.isEmpty
        else { return nil }
        // `isSameOrigin` is the same predicate `PrivateMediaLoader` refuses
        // on, asked once. If this said "fetch it with the credential" about an
        // address the loader would then refuse to send one to, the picture
        // would simply never appear.
        if PrivateMediaLoader.isSameOrigin(url, as: apiOrigin) {
            return url.path.hasPrefix(privatePrefix) ? .privateMedia(url) : .link(url)
        }
        // Off Rewound's own host, so no credential — and then only over https,
        // because a page-level http link is one the app will not load and
        // storing it renders as nothing.
        return scheme == "https" ? .link(url) : nil
    }

    /// Convenience for the common call: a watch's cover.
    public static func cover(_ watch: VaultWatch, apiOrigin: URL) -> VaultCoverSource? {
        resolve(watch.coverUrl?.url, apiOrigin: apiOrigin)
    }

}

/// One of the seller's own watches that a listing being written might be —
/// `GET /vault/matches`.
///
/// Deliberately narrower than `VaultWatch`: the seller is being asked to
/// recognize a watch, not to browse their collection, so no valuation and no
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

/// The spec sheet Rewound keeps for a reference, in the order a sheet is
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

/// The catalog row a vault watch resolves to, if Rewound has one.
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
    /// Every photograph of the listing this watch was bought from, lead first.
    ///
    /// Read through `listing_id` when the detail is served, never copied onto
    /// the row, so a watch bought before the key existed has them too. Empty
    /// when the watch was not bought here, and empty on a server that predates
    /// the key: both are "no seller's photographs to show", and neither is an
    /// error.
    public let listingPhotos: [VaultListingPhoto]

    public var id: String { watch.id }

    private enum CodingKeys: String, CodingKey {
        case serviceRecords, referenceRow, pendingSuggestion, listingPhotos
    }

    public init(from decoder: Decoder) throws {
        watch = try VaultWatch(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serviceRecords = try container.decode([VaultServiceRecord].self, forKey: .serviceRecords)
        referenceRow = try container.decodeIfPresent(VaultReferenceRow.self, forKey: .referenceRow)
        pendingSuggestion = try container.decode(Bool.self, forKey: .pendingSuggestion)
        listingPhotos = try container.decodeIfPresent([VaultListingPhoto].self, forKey: .listingPhotos) ?? []
    }
}

/// One of the seller's photographs of the listing a vault watch was bought
/// from. Public media, the same `/media/` form a listing page draws, so it is
/// fetched like any other listing photograph and never with the member's
/// credential.
public struct VaultListingPhoto: Decodable, Equatable, Sendable {
    public let url: MediaURL?
    /// Measured by the server where it could; both or neither.
    public let width: Int?
    public let height: Int?

    public init(url: MediaURL?, width: Int? = nil, height: Int? = nil) {
        self.url = url
        self.width = width
        self.height = height
    }
}

public extension VaultWatch {
    /// Every picture of this watch, in the one order the detail shows them.
    ///
    /// The cover first, because it is the picture the owner already knows
    /// this watch by (their own first photograph, or the seller's lead until
    /// they have one). Then the owner's own photographs in the order they
    /// arranged them, then the seller's photographs from the listing it was
    /// bought from, lead first.
    ///
    /// The same picture is never shown twice. The cover IS one of the other
    /// two most of the time (position zero of the gallery, or the listing's
    /// lead carried as `photo_url`), so a list built without the check would
    /// open on the same photograph twice in a row. Compared as absolute
    /// addresses, after `MediaURL` has rebased `/media/` paths onto the API
    /// origin, so a relative and an absolute spelling of one file are one.
    ///
    /// An owner's photograph whose object cannot be addressed (`url == nil`)
    /// is left out rather than drawn as a blank page in the pager. Whether an
    /// address is safe to FETCH is not decided here: `VaultCoverSource` does
    /// that per picture, at draw time.
    func viewingGallery(listingPhotos: [VaultListingPhoto]) -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url else { return }
            let key = url.absoluteString
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            out.append(url)
        }
        add(coverUrl?.url)
        gallery.forEach { add($0.url?.url) }
        listingPhotos.forEach { add($0.url?.url) }
        return out
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
///
/// A notification is *cleared*, not read. `readAt` still exists and still
/// means "seen in the inbox", but the inbox is now emptied rather than
/// ticked off: clearing stamps `clearedAt` on the server and the row is never
/// listed again. There is no history view and no undo, by ruling — which is
/// why `clearedAt` is only ever non-nil on the response to the call that
/// cleared it, never on a row that came back from the list.
public struct ServerNotification: Decodable, Equatable, Sendable, Identifiable {
    public let id: String
    public let category: String
    public let title: String
    public let body: String
    public let route: String
    public let readAt: String?
    public let clearedAt: String?
    public let createdAt: String?
    public let payload: ServerNotificationPayload?

    public init(
        id: String,
        category: String,
        title: String,
        body: String,
        route: String,
        readAt: String? = nil,
        clearedAt: String? = nil,
        createdAt: String? = nil,
        payload: ServerNotificationPayload? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.route = route
        self.readAt = readAt
        self.clearedAt = clearedAt
        self.createdAt = createdAt
        self.payload = payload
    }
}

/// Extra navigation context persisted with a server notification. Most rows
/// have no payload; listing moderation rows use these fields so an unavailable
/// public listing can still open in its owner's editor.
public struct ServerNotificationPayload: Decodable, Equatable, Sendable {
    public let kind: String?
    public let listingId: String?
    public let listingStatus: String?

    public init(kind: String? = nil, listingId: String? = nil, listingStatus: String? = nil) {
        self.kind = kind
        self.listingId = listingId
        self.listingStatus = listingStatus
    }
}

public struct ServerNotificationList: Decodable, Equatable, Sendable {
    public let results: [ServerNotification]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    /// What is still in this member's inbox — the badge. Counts everything
    /// not cleared, whether or not it has been read.
    public let remainingCount: Int
    /// The same number under its old key. The server moved the value rather
    /// than the key so that a build shipped before the ruling keeps drawing a
    /// correct badge; nothing new should read this.
    public let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case results, page, pageSize, total, remainingCount, unreadCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decode([ServerNotification].self, forKey: .results)
        page = ((try? container.decodeIfPresent(Int.self, forKey: .page)) ?? nil) ?? 1
        pageSize = ((try? container.decodeIfPresent(Int.self, forKey: .pageSize)) ?? nil) ?? results.count
        total = ((try? container.decodeIfPresent(Int.self, forKey: .total)) ?? nil) ?? results.count
        let unread = (try? container.decodeIfPresent(Int.self, forKey: .unreadCount)) ?? nil
        // A server that predates the ruling sends only `unread_count`, and a
        // hard `decode` of the new key would empty the whole inbox screen
        // over a missing integer. The two keys carry the same number once
        // both sides have shipped.
        remainingCount = ((try? container.decodeIfPresent(Int.self, forKey: .remainingCount)) ?? nil)
            ?? unread
            ?? results.count
        unreadCount = unread ?? remainingCount
    }

    public init(
        results: [ServerNotification],
        page: Int = 1,
        pageSize: Int = 50,
        total: Int = 0,
        remainingCount: Int = 0
    ) {
        self.results = results
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.remainingCount = remainingCount
        self.unreadCount = remainingCount
    }
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
