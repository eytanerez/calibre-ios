import Foundation

/// Listing lifecycle as the backend's `ListingStatus` enum sends it.
public enum ListingStatus: String, Codable, Sendable {
    case draft
    case pendingReview = "pending_review"
    case active
    case reserved
    case sold
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
    public let description: String?
    public let price: APIDecimal
    public let currency: String
    public let condition: ListingCondition?
    public let boxPapers: Bool?
    public let productionYear: Int?
    public let status: ListingStatus
    public let reviewStatus: ListingStatus?
    /// Derived seller-facing status string, e.g. "live" — display-only.
    public let sellerStatus: String?
    public let reviewEvents: [ListingReviewEvent]?
    public let estimatedShipping: ShippingEstimate?
    public let metrics: ListingMetricCounts?
    public let createdAt: Date?
    public let updatedAt: Date?

    private let imageList: ListingImageList

    /// Gallery images, absolutized at decode time. `front` sorts first
    /// server-side.
    public var images: [MediaURL] { imageList.urls }

    enum CodingKeys: String, CodingKey {
        case id, listingNumber, sellerId, seller, variantId, title, brand, model
        case referenceNumber, description, price, currency, condition, boxPapers
        case productionYear, status, reviewStatus, sellerStatus, reviewEvents
        case estimatedShipping, metrics, createdAt, updatedAt
        case imageList = "images"
    }
}

public struct ListingSeller: Codable, Sendable {
    public let id: String
    public let username: String
    public let reputation: SellerReputation?
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
