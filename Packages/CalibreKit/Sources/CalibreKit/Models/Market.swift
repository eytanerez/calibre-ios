import Foundation

/// The Market Data page payload — everything computed from Calibre's own
/// listings and completed sales (no external data).
public struct MarketOverview: Decodable, Equatable, Sendable {
    public struct TrendPoint: Decodable, Equatable, Sendable {
        public let date: String
        public let askMedian: Double?
    }

    public struct BrandStat: Decodable, Equatable, Sendable, Identifiable {
        public let brand: String
        public let brandKey: String
        public let activeCount: Int
        public let askMin: Double?
        public let askMedian: Double?
        public let askMax: Double?
        public let soldCount: Int
        public let soldMedian: Double?
        public let medianDaysToSell: Double?
        public let trend: [TrendPoint]

        public var id: String { brandKey }
    }

    public struct RecentSale: Decodable, Equatable, Sendable {
        public let brand: String?
        public let model: String?
        public let reference: String?
        public let price: Double?
        public let soldOn: String?
    }

    public struct Totals: Decodable, Equatable, Sendable {
        public let activeListings: Int
        public let soldLast90Days: Int
        public let brands: Int
        public let references: Int
    }

    public let asOf: String?
    public let brands: [BrandStat]
    public let recentlySold: [RecentSale]
    public let totals: Totals
}

/// Sell-flow pricing guidance computed from Calibre's own listings and sales.
/// `available == false` means the sample was too thin to be worth showing.
public struct PricingGuidance: Decodable, Equatable, Sendable {
    public let available: Bool
    public let reason: String?
    /// "reference" | "brand_model" | "brand" — how narrow the comparable set is.
    public let scope: String?
    public let sampleSize: Int?
    public let askMin: Double?
    public let askMedian: Double?
    public let askMax: Double?
    public let soldMedian: Double?
    public let medianDaysToSell: Double?

    public init(
        available: Bool,
        reason: String? = nil,
        scope: String? = nil,
        sampleSize: Int? = nil,
        askMin: Double? = nil,
        askMedian: Double? = nil,
        askMax: Double? = nil,
        soldMedian: Double? = nil,
        medianDaysToSell: Double? = nil
    ) {
        self.available = available
        self.reason = reason
        self.scope = scope
        self.sampleSize = sampleSize
        self.askMin = askMin
        self.askMedian = askMedian
        self.askMax = askMax
        self.soldMedian = soldMedian
        self.medianDaysToSell = medianDaysToSell
    }
}

/// A reference's published price, as `GET /market/reference-prices` sends it.
///
/// `history` is sparse: one point per change, oldest first, always ending on
/// the current price. Between two points the price simply held — it is a step
/// series, not a daily one, and anything that draws it has to say so.
public struct MarketReferencePrice: Decodable, Equatable, Sendable, Identifiable {
    public struct HistoryPoint: Decodable, Equatable, Sendable {
        /// "YYYY-MM-DD" — a calendar day, not a timestamp.
        public let date: String
        public let price: APIDecimal
    }

    public let id: String
    public let brand: String
    public let model: String?
    public let reference: String
    public let slug: String
    public let price: APIDecimal
    public let currency: String
    public let setAt: String?
    public let specs: WatchReferenceSpecs
    public let history: [HistoryPoint]
}

/// `GET /market/reference-prices` — every reference that publishes a price.
public struct MarketReferencePriceList: Decodable, Equatable, Sendable {
    public let asOf: String?
    public let references: [MarketReferencePrice]
}
