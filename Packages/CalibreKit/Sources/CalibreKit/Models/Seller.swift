import Foundation

// FIXTURE-PENDING: authenticated captures need a signed-in seller; shape read
// off `_readiness_payload` in app/api/views/stripe.py and the status ladder in
// app/services/connect_status.py.
/// `/stripe/seller-readiness` — Connect status, synced from Stripe on read.
public struct SellerReadiness: Codable, Sendable {
    public let connect: ConnectStatus
    /// True once onboarding is complete, payouts are enabled and the card on
    /// file is valid. The gate reads this and nothing else — `connect.status`
    /// says how setup is going, never whether it is allowed to proceed.
    public let canList: Bool

    public init(connect: ConnectStatus, canList: Bool) {
        self.connect = connect
        self.canList = canList
    }

    /// Payout onboarding owns the shop gate; card readiness owns only new
    /// listing creation. An established seller whose card lapsed still needs
    /// their listings, offers, performance and storefront.
    public var canAccessDashboard: Bool {
        canList || connect.onboardingComplete
    }
}

public struct ConnectStatus: Codable, Sendable {
    public let accountId: String?
    public let onboardingComplete: Bool
    public let detailsSubmitted: Bool
    public let chargesEnabled: Bool
    public let payoutsEnabled: Bool
    public let lastCheckedAt: Date?
    /// The raw Stripe requirement keys. `missingItems` is the same list said
    /// in words a seller can read; these stay for anything that needs to match
    /// Stripe's own spelling.
    public let requirementsCurrentlyDue: [String]
    public let requirementsEventuallyDue: [String]
    /// The six-state answer — see `ConnectSetupStatus`.
    public let status: ConnectSetupStatus
    /// Whether `status` came from a live Stripe read or from the seller row.
    public let statusBasis: ConnectStatusBasis
    /// What Stripe is waiting on now, in words. Empty on a cached read by
    /// design: the row remembers that something was outstanding, not what.
    public let missingItems: [ConnectRequirementItem]
    /// What Stripe will likely ask for after this round.
    public let upcomingItems: [ConnectRequirementItem]
    /// What Stripe is reading right now. Only ever populated by a live read.
    public let reviewItems: [ConnectRequirementItem]
    /// Stripe's own machine reason, unhumanized. For support, never for the
    /// seller — `payoutStep` writes what the seller is shown.
    public let disabledReason: String?

    public init(
        accountId: String?,
        onboardingComplete: Bool,
        detailsSubmitted: Bool,
        chargesEnabled: Bool,
        payoutsEnabled: Bool,
        lastCheckedAt: Date? = nil,
        requirementsCurrentlyDue: [String] = [],
        requirementsEventuallyDue: [String] = [],
        status: ConnectSetupStatus,
        statusBasis: ConnectStatusBasis = .live,
        missingItems: [ConnectRequirementItem] = [],
        upcomingItems: [ConnectRequirementItem] = [],
        reviewItems: [ConnectRequirementItem] = [],
        disabledReason: String? = nil
    ) {
        self.accountId = accountId
        self.onboardingComplete = onboardingComplete
        self.detailsSubmitted = detailsSubmitted
        self.chargesEnabled = chargesEnabled
        self.payoutsEnabled = payoutsEnabled
        self.lastCheckedAt = lastCheckedAt
        self.requirementsCurrentlyDue = requirementsCurrentlyDue
        self.requirementsEventuallyDue = requirementsEventuallyDue
        self.status = status
        self.statusBasis = statusBasis
        self.missingItems = missingItems
        self.upcomingItems = upcomingItems
        self.reviewItems = reviewItems
        self.disabledReason = disabledReason
    }
}

// FIXTURE-PENDING: shape from `SellerDashboardView.get` in
// app/api/views/payouts.py.
/// `/account/dashboard` — seller KPIs, action queue, received offers and
/// where the seller stands in the dealer program.
public struct SellerDashboard: Codable, Sendable {
    /// Replaces the retired `dealer` unlock block.
    public let dealerApplication: DealerApplication?
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

/// The catalog row a request resolved to, when the buyer's free text could be
/// pinned to one. `null` on the wire when it never resolved — the request
/// still stands on its own.
public struct WatchReferenceSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let brand: String?
    public let model: String?
    public let reference: String?
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
    /// Set when the request's text was pinned to a catalog row.
    public let watchReferenceId: String?
    public let watchReference: WatchReferenceSummary?
    public let productionYear: Int?
    public let maxBudget: APIDecimal?
    public let currency: String?
    public let notes: String?
    public let status: WatchRequestStatus
    public let fulfilledListingId: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// Dealer feed only: how many of *my* listings are live against the same
    /// catalog row. Absent on `/account/watch-requests`, hence optional —
    /// synthesized `Decodable` ignores property defaults.
    public let matchingLiveListings: Int?

    /// Zero unless the dealer feed said otherwise.
    public var liveMatchCount: Int { matchingLiveListings ?? 0 }

    /// True when the buyer's text resolved to a catalog row.
    public var isCatalogMatched: Bool { watchReference != nil }
}

/// `GET /dealer/watch-requests` — a flat `{results, page, page_size, total}`
/// page rather than the `{results, pagination}` envelope the browse endpoints
/// use. Not interchangeable with `PageResponse`.
public struct DealerWatchRequestPage: Codable, Sendable {
    public let results: [WatchRequest]
    public let page: Int
    public let pageSize: Int
    public let total: Int

    public init(results: [WatchRequest], page: Int = 1, pageSize: Int = 25, total: Int = 0) {
        self.results = results
        self.page = page
        self.pageSize = pageSize
        self.total = total
    }
}

/// The orderings `/dealer/watch-requests` accepts.
public enum DealerRequestSort: String, Sendable, CaseIterable {
    case latest
    case budgetHigh = "budget_high"
    case budgetLow = "budget_low"
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
    /// How far the seller is through finishing what this import created,
    /// counted server-side: "finished" means the row's listing has left
    /// `draft`. Absent on a payload that predates the counters — in which
    /// case the job simply has no progress to report, and no client may
    /// reconstruct one from `created + updated`, which counts rows rather
    /// than listings and ignores skipped ones entirely.
    public let draftsTotal: Int?
    public let draftsRemaining: Int?
    public let createdAt: Date?
    public let completedAt: Date?

    /// Drafts already finished, when the server has stated both figures.
    public var draftsFinished: Int? {
        guard let draftsTotal, let draftsRemaining else { return nil }
        return max(0, draftsTotal - draftsRemaining)
    }
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
    /// The seller's own shelf label — the only key the import matched on.
    public let sellerSku: String?
    public let price: APIDecimal?
    public let description: String?
    public let productionYear: Int?
    public let conditionOverall: String?
    public let conditionCase: String?
    public let conditionBracelet: String?
    public let conditionDial: String?
    public let conditionBezel: String?
    public let conditionCrystal: String?
    public let conditionClasp: String?
    public let conditionCaseback: String?
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
    /// The seller's unique shelf label. Unique per seller where set; the
    /// server answers a collision with 409 `duplicate_sku`. Bulk import
    /// matches on this and only this — `reference` is descriptive.
    public var sellerSku: String?
    /// The watch in the seller's own Collection that this listing is — their
    /// answer to "is this that watch?", and the only thing that links the two.
    /// Omitting it is a decline and writes nothing, which is why every payload
    /// that isn't carrying an answer leaves it nil.
    public var vaultWatchId: String?
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
    /// Whether this listing accepts returns. Changing either return field on
    /// an active listing sends it back through review.
    public var returnsAccepted: Bool?
    /// 24, 48 or 72 — required by the server when `returnsAccepted` is true.
    public var returnWindowHours: Int?
    /// Seller may set draft / pending_review / archived.
    public var status: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        brand: String? = nil,
        model: String? = nil,
        reference: String? = nil,
        sellerSku: String? = nil,
        vaultWatchId: String? = nil,
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
        returnsAccepted: Bool? = nil,
        returnWindowHours: Int? = nil,
        status: ListingStatus? = nil
    ) {
        self.title = title
        self.description = description
        self.brand = brand
        self.model = model
        self.reference = reference
        self.sellerSku = sellerSku
        self.vaultWatchId = vaultWatchId
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
        self.returnsAccepted = returnsAccepted
        self.returnWindowHours = returnWindowHours
        self.status = status?.rawValue
    }
}
