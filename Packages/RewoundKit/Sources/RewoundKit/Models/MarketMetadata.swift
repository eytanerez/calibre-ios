import Foundation

/// `/listings/metadata` — filter facets, cascading brand→model→reference
/// groups, price bounds and marketplace stats. Cached server-side for 300 s.
public struct MarketMetadata: Codable, Sendable {
    public let price: PriceBounds
    public let options: FacetOptions
    public let counts: MarketCounts
    public let stats: MarketStats?
}

public struct PriceBounds: Codable, Sendable {
    public let min: APIDecimal
    public let max: APIDecimal
}

public struct FacetOptions: Codable, Sendable {
    public let brands: [String]
    public let models: [String]
    public let references: [String]
    public let materials: [String]
    public let colors: [String]
    public let caseSizes: [String]
    public let movements: [String]
    public let bracelets: [String]
    public let thicknesses: [String]
    public let lugWidths: [String]
    public let waterResistances: [String]
    public let calibers: [String]
    /// Cascading facet groups: pick a brand, get its models; pick a model,
    /// get its references.
    public let byBrand: [BrandGroup]
}

public struct BrandGroup: Codable, Sendable {
    public let brand: String
    public let models: [BrandModelGroup]
    public let liveTotal: Int?
}

public struct BrandModelGroup: Codable, Sendable {
    public let model: String
    public let references: [String]
    public let liveTotal: Int?
}

public struct MarketCounts: Codable, Sendable {
    public let liveTotal: Int
}

public struct MarketStats: Codable, Sendable {
    public let averagePrice: APIDecimal?
    public let latestListingUpdatedAt: Date?
}

/// `/listings/home` — metadata plus curated lanes (12 listings each;
/// recommended/recently_viewed are server-stubbed empty today).
public struct HomeFeed: Codable, Sendable {
    public let metadata: MarketMetadata
    public let popular: [Listing]
    public let trending: [Listing]
    public let recommended: [Listing]
    public let recentlyViewed: [Listing]
}
