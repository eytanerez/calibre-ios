import Foundation

/// Listing lifecycle as the backend's `ListingStatus` enum sends it.
public enum ListingStatus: String, Codable, Sendable {
    case draft
    case pendingReview = "pending_review"
    case active
    case reserved
    case sold
    /// Rewound took the listing down because the seller's guarantee card
    /// lapsed. Never a seller action, and never the same thing as archived —
    /// it comes back on its own once a valid credit card is on file.
    case pausedCard = "paused_card"
    case archived
    case rejected
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// A listing as `/listings` (card + full view), `/listings/{id}` and
/// `/account/listings` serialize it. Card view sends `description: null` and a
/// single image; full view sends everything. One model covers both.
public struct Listing: Codable, Sendable, Identifiable {
    public let id: String
    public let listingNumber: Int
    public let sellerId: String
    public let seller: ListingSeller?
    public let variantId: String?
    public let title: String
    public let brand: String?
    public let model: String?
    public let referenceNumber: String?
    /// The seller's own shelf label. Present only when the reader is the
    /// seller — a buyer's payload omits the key entirely. Bulk import matches
    /// on this and only this; `referenceNumber` never identifies a watch.
    public let sellerSku: String?
    /// The watch in the seller's own Collection this listing is, when they
    /// said so. Like `sellerSku`, present only when the reader is the seller —
    /// a buyer's payload omits the key entirely.
    public let vaultWatchId: String?
    public let description: String?
    public let price: APIDecimal
    public let currency: String
    public let condition: ListingCondition?
    public let boxPapers: Bool?
    /// The seller's three answers, separately.
    ///
    /// `boxPapers` above is the derived summary the cards and the search facets
    /// read; these are what was actually asked. `nil` is "nobody was asked",
    /// which is every listing made before the clients started sending them, and
    /// it is not the same as `false` — it must never be drawn as an unticked
    /// box.
    public let boxIncluded: Bool?
    public let papersIncluded: Bool?
    public let bookletsIncluded: Bool?
    /// What the watch IS, as opposed to what condition it is in.
    ///
    /// The reference's own specs, overridden where this one watch differs. The
    /// server merges the two and sends the answer; which side won is not a
    /// buyer's business.
    ///
    /// Nil on a server old enough not to send the key, which renders exactly as
    /// it did before the key existed: the columns alone.
    public let specs: ListingSpecs?
    public let productionYear: Int?
    public let status: ListingStatus
    public let reviewStatus: ListingStatus?
    /// Derived seller-facing status string, e.g. "live" — display-only.
    public let sellerStatus: String?
    public let reviewEvents: [ListingReviewEvent]?
    public let estimatedShipping: ShippingEstimate?
    public let metrics: ListingMetricCounts?
    /// The seller's return terms, chosen at listing time and visible to the
    /// buyer before purchase. Nil on payloads recorded before returns shipped.
    public let returns: ListingReturnTerms?
    public let countryOfOrigin: String?
    public let htsCode: String?
    /// The seller's own marks on their photos, keyed to photo position.
    ///
    /// Nil and empty are different answers and the gallery needs both: the
    /// card view does not carry this key at all, so nil means "this payload
    /// was not asked about marks" while `[]` means "this seller drew none".
    /// Reading nil as none would blank the marks off every card-sourced
    /// gallery without anything going wrong.
    public let annotations: [ListingAnnotation]?
    public let createdAt: Date?
    public let updatedAt: Date?

    private let imageList: ListingImageList

    /// Gallery images, absolutized at decode time. `front` sorts first
    /// server-side.
    public var images: [MediaURL] { imageList.urls }

    enum CodingKeys: String, CodingKey {
        case id, listingNumber, sellerId, seller, variantId, title, brand, model
        case referenceNumber, sellerSku, vaultWatchId, description, price, currency, condition, boxPapers
        case boxIncluded, papersIncluded, bookletsIncluded, specs
        case productionYear, status, reviewStatus, sellerStatus, reviewEvents
        case estimatedShipping, metrics, returns, countryOfOrigin, htsCode
        case annotations, createdAt, updatedAt
        case imageList = "images"
    }
}

/// The watch's specifications, as the catalog holds them.
///
/// Sixteen fields, in the order a spec sheet is read. Four are numbers and the
/// rest are phrases, which is why each is decoded leniently: a value arriving as
/// the other kind renders rather than failing the whole listing.
///
/// Every field is optional and `nil` means nobody has filled it in — the detail
/// screen drops the row rather than printing a dash, because a spec sheet of
/// em-dashes reads as a broken page rather than as a catalog still being
/// written.
public struct ListingSpecs: Codable, Sendable {
    public let material: String?
    public let bezel: String?
    public let glass: String?
    public let back: String?
    public let shape: String?
    public let diameterMm: Int?
    public let finish: String?
    public let dial: String?
    public let indexes: String?
    public let hands: String?
    public let movement: String?
    public let calibre: String?
    public let bracelet: String?
    public let thicknessMm: Double?
    public let lugWidthMm: Int?
    /// Zero is a real answer — a dress watch that holds no pressure — and reads
    /// "Not water resistant". Nil is "nobody has said".
    public let waterResistanceM: Int?

    /// Label and value for every filled field, in spec-sheet order.
    ///
    /// The rows a screen prints, built here rather than in the view so the
    /// storefront, this app and Android cannot come to disagree about what the
    /// word for a field is or where the unit goes.
    public var rows: [(label: String, value: String)] {
        var out: [(String, String)] = []
        func add(_ label: String, _ value: String?) {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            out.append((label, value))
        }
        func add(_ label: String, _ value: Int?, unit: String) {
            guard let value else { return }
            out.append((label, "\(value)\(unit)"))
        }
        add("Case material", material)
        add("Bezel", bezel)
        add("Glass", glass)
        add("Case back", back)
        add("Shape", shape)
        add("Diameter", diameterMm, unit: "mm")
        add("Finish", finish)
        add("Dial", dial)
        add("Indexes", indexes)
        add("Hands", hands)
        add("Movement", movement)
        add("Calibre", calibre)
        add("Bracelet", bracelet)
        if let thicknessMm {
            // Trailing ".0" is noise on a measurement quoted to one place.
            let text = thicknessMm == thicknessMm.rounded()
                ? String(Int(thicknessMm))
                : String(format: "%.1f", thicknessMm)
            out.append(("Thickness", "\(text)mm"))
        }
        add("Lug width", lugWidthMm, unit: "mm")
        if let waterResistanceM {
            out.append(("Water resistance", waterResistanceM == 0 ? "Not water resistant" : "\(waterResistanceM)m"))
        }
        return out
    }
}

public struct ListingSeller: Codable, Sendable {
    public let id: String
    public let username: String
    public let reputation: SellerReputation?
    /// Drives the dealer badge on listing cards and the PDP.
    public let isVerifiedDealer: Bool?
}

public struct SellerReputation: Codable, Sendable {
    public let salesCount: Int
    public let ratingCount: Int
    public let averageRating: Double?
}

/// Per-part condition breakdown; values are one of
/// "New" / "Like New" / "Very Good" / "Good" / "Worn".
public struct ListingCondition: Codable, Sendable {
    public let overall: String?
    public let crystal: String?
    public let bezel: String?
    public let bracelet: String?
    public let clasp: String?
    public let caseback: String?
    public let caseCondition: String?
    public let dial: String?

    enum CodingKeys: String, CodingKey {
        case overall, crystal, bezel, bracelet, clasp, caseback, dial
        case caseCondition = "case"
    }
}

public struct ListingMetricCounts: Codable, Sendable {
    public let views: Int
    public let watchers: Int
}

/// Moderation audit entry surfaced on `/account/listings`.
public struct ListingReviewEvent: Codable, Sendable {
    public let fromStatus: String?
    public let toStatus: String?
    public let notes: String?
    public let createdAt: Date?
}

/// One image row from `/account/listings/{id}/images` (seller management).
public struct ListingImage: Codable, Sendable, Identifiable {
    public let id: String
    public let listingId: String?
    public let url: MediaURL
    public let sortIndex: Int?
    /// One of front / caseback / left_profile / right_profile / clasp /
    /// full_set, or nil for bulk-imported photos.
    public let category: String?
}

/// The six categorized shots a wizard-created listing needs before it can be
/// submitted for review.
public enum ListingImageCategory: String, CaseIterable, Sendable {
    case front, caseback, leftProfile = "left_profile"
    case rightProfile = "right_profile", clasp, fullSet = "full_set"
}

/// Compact listing embedded in cart/watchlist/order payloads.
public struct ListingSummary: Codable, Sendable, Identifiable {
    public struct Seller: Codable, Sendable {
        public let id: String
        public let username: String
        public let isVerifiedDealer: Bool?
    }

    public let id: String
    public let listingNumber: Int?
    public let title: String
    public let price: APIDecimal
    public let currency: String
    public let status: ListingStatus
    public let productionYear: Int?
    public let image: MediaURL?
    public let seller: Seller?
}

/// Shipping estimate quotes: `estimate_to_buyer` (order_id keyed) and the
/// seller's `estimate_to_auth_center` (quote_id keyed) share this shape.
public struct ShippingEstimate: Codable, Sendable {
    public let orderId: String?
    public let quoteId: String?
    public let amount: APIDecimal
    public let currency: String
    public let provider: String?
    public let fallbackReason: String?
    public let originPostalCode: String?
    public let destinationPostalCode: String?
}
