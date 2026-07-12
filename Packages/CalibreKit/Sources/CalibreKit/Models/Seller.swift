import Foundation

// FIXTURE-PENDING: authenticated captures blocked by the backend
// mid-migration; shape from `_readiness_payload` in app/api/views/stripe.py.
/// `/stripe/seller-readiness` — Connect status, synced from Stripe on read.
public struct SellerReadiness: Codable, Sendable {
    public let connect: ConnectStatus
    /// True once onboarding is complete and payouts are enabled.
    public let canList: Bool
}

public struct ConnectStatus: Codable, Sendable {
    public let accountId: String?
    public let onboardingComplete: Bool
    public let detailsSubmitted: Bool
    public let chargesEnabled: Bool
    public let payoutsEnabled: Bool
    public let lastCheckedAt: Date?
    public let requirementsCurrentlyDue: [String]
    public let requirementsEventuallyDue: [String]
}

// FIXTURE-PENDING: shape from `SellerDashboardView.get` in
// app/api/views/payouts.py.
/// `/account/dashboard` — seller KPIs, action queue, received offers and
/// dealer unlock progress.
public struct SellerDashboard: Codable, Sendable {
    public let dealer: DealerUnlock?
    public let metrics: SellerDashboardMetrics
    public let actionQueue: [DashboardAction]
    public let offers: [Offer]
    public let whatToList: [ListingSuggestion]
    public let recentOrders: [DashboardOrder]
    public let recentListings: [DashboardListing]
}

public struct SellerDashboardMetrics: Codable, Sendable {
    public let activeListings: Int
    public let pendingReviewListings: Int
    public let draftListings: Int
    public let rejectedListings: Int
    public let archivedListings: Int
    public let soldListings: Int
    public let totalViews: Int
    public let totalWatchers: Int
    public let ordersTotal: Int
    public let conversionRatePercent: Double?
    public let grossSales: APIDecimal
    public let netSales: APIDecimal
    public let pendingPayoutTotal: APIDecimal
    public let pendingActionsTotal: Int
    public let offersWaiting: Int
    public let soldAwaitingLabel: Int
}

/// One row in the dashboard action queue (respond to offer, buy a label,
/// finish a draft, fix a rejection).
public struct DashboardAction: Codable, Sendable {
    public let kind: String
    public let label: String
    public let priority: String
    public let title: String
    public let description: String
    public let href: String?
    public let listingId: String?
    public let listingNumber: Int?
    public let orderId: String?
    public let offerId: String?
}

/// "What to list" market-demand suggestion.
public struct ListingSuggestion: Codable, Sendable {
    public let brand: String
    public let model: String?
    public let referenceNumber: String?
    public let reason: String
    public let activeSupply: Int?
    public let views: Int?
    public let watchers: Int?
}

public struct DashboardOrder: Codable, Sendable, Identifiable {
    public let id: String
    public let listingId: String
    public let status: OrderStatus
    public let subtotal: APIDecimal
    public let currency: String
    public let createdAt: Date?
}

public struct DashboardListing: Codable, Sendable, Identifiable {
    public let id: String
    public let listingNumber: Int?
    public let title: String
    public let price: APIDecimal
    public let currency: String
    public let status: ListingStatus
    public let brand: String?
    public let model: String?
    public let referenceNumber: String?
    public let createdAt: Date?
    public let updatedAt: Date?
}

/// `/sellers/{username}` — public storefront header. The seller's active
/// listings come from `/listings?seller=<username>`.
public struct SellerStorefront: Codable, Sendable, Identifiable {
    public let id: String
    public let username: String
    public let memberSince: Date?
    public let isVerifiedDealer: Bool
    public let dealerStatus: String?
    public let bio: String?
    public let responseRate: Double?
    public let activeListingCount: Int
    public let reputation: SellerReputation
    public let reviews: [StorefrontReview]
}

public struct StorefrontReview: Codable, Sendable, Identifiable {
    public let id: String
    public let rating: Int
    public let comment: String?
    public let createdAt: Date?
    public let verifiedPurchase: Bool?
}

public enum WatchRequestStatus: String, Codable, Sendable {
    case open
    case fulfilled
    case cancelled
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

// FIXTURE-PENDING: shape from `_serialize_watch_request` in
// app/api/views/watch_requests.py.
/// A buyer's watch sourcing request; dealers browse and fulfill open ones.
public struct WatchRequest: Codable, Sendable, Identifiable {
    public let id: String
    public let requesterId: String
    /// Present on the dealer feed.
    public let requesterUsername: String?
    public let brand: String
    public let model: String?
    public let reference: String?
    public let productionYear: Int?
    public let maxBudget: APIDecimal?
    public let currency: String?
    public let notes: String?
    public let status: WatchRequestStatus
    public let fulfilledListingId: String?
    public let createdAt: Date?
    public let updatedAt: Date?
}

public enum ImportJobStatus: String, Codable, Sendable {
    case mappingPending = "mapping_pending"
    case processing
    case completed
    case completedWithErrors = "completed_with_errors"
    case failed
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

// FIXTURE-PENDING: shape from `_serialize_job` in
// app/api/views/listing_imports.py.
/// A bulk CSV/XLSX inventory import job.
public struct ListingImportJob: Codable, Sendable, Identifiable {
    public let id: String
    public let status: ImportJobStatus
    public let originalFilename: String?
    public let totalRows: Int?
    public let processedRows: Int?
    public let createdCount: Int?
    public let updatedCount: Int?
    public let errorCount: Int?
    public let errorMessage: String?
    public let createdAt: Date?
    public let completedAt: Date?
}

/// One imported listing still missing required data/photos
/// (`/account/listing-imports/{id}/completion-queue`).
public struct ImportCompletionItem: Codable, Sendable, Identifiable {
    public let id: String
    public let listingNumber: Int?
    public let status: ListingStatus
    public let title: String?
    public let brand: String?
    public let model: String?
    public let reference: String?
    public let price: APIDecimal?
    public let description: String?
    public let productionYear: Int?
    public let imageCount: Int
    /// Field keys the listing still needs before submission.
    public let missing: [String]
}

/// Create/update body for `/account/listings` (draft wizard + partial PATCH).
/// Optionals are omitted from the JSON, so the same struct drives partial
/// updates and the submit-for-review status flip.
public struct ListingDraftPayload: Encodable, Sendable {
    public var title: String?
    public var description: String?
    public var brand: String?
    public var model: String?
    public var reference: String?
    /// Serialized as a string to keep Decimal exactness on the wire.
    public var price: String?
    public var currency: String?
    public var conditionOverall: String?
    public var conditionCase: String?
    public var conditionBracelet: String?
    public var conditionDial: String?
    public var conditionBezel: String?
    public var conditionCrystal: String?
    public var conditionClasp: String?
    public var conditionCaseback: String?
    public var boxPapers: Bool?
    public var productionYear: Int?
    /// Seller may set draft / pending_review / archived.
    public var status: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        brand: String? = nil,
        model: String? = nil,
        reference: String? = nil,
        price: Decimal? = nil,
        currency: String? = nil,
        conditionOverall: String? = nil,
        conditionCase: String? = nil,
        conditionBracelet: String? = nil,
        conditionDial: String? = nil,
        conditionBezel: String? = nil,
        conditionCrystal: String? = nil,
        conditionClasp: String? = nil,
        conditionCaseback: String? = nil,
        boxPapers: Bool? = nil,
        productionYear: Int? = nil,
        status: ListingStatus? = nil
    ) {
        self.title = title
        self.description = description
        self.brand = brand
        self.model = model
        self.reference = reference
        self.price = price.map { "\($0)" }
        self.currency = currency
        self.conditionOverall = conditionOverall
        self.conditionCase = conditionCase
        self.conditionBracelet = conditionBracelet
        self.conditionDial = conditionDial
        self.conditionBezel = conditionBezel
        self.conditionCrystal = conditionCrystal
        self.conditionClasp = conditionClasp
        self.conditionCaseback = conditionCaseback
        self.boxPapers = boxPapers
        self.productionYear = productionYear
        self.status = status?.rawValue
    }
}
