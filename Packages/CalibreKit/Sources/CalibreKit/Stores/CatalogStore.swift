import Foundation
import Observation

/// Browse/search/metadata/home-feed state. Read-only marketplace data —
/// nothing here requires an account.
@MainActor
@Observable
public final class CatalogStore {
    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let metadataCache: DiskCache<MarketMetadata>
    @ObservationIgnored private let homeCache: DiskCache<HomeFeed>
    /// Disk entries older than this are served stale and refreshed in the
    /// background (stale-while-revalidate).
    @ObservationIgnored private let cacheTTL: TimeInterval

    /// In-memory page cache, keyed by the full query. Cleared by
    /// `invalidateBrowseCache()` (pull-to-refresh).
    @ObservationIgnored private var pageCache: [ListingQuery: PageResponse<Listing>] = [:]
    @ObservationIgnored private var metadataRefresh: Task<MarketMetadata, Error>?
    @ObservationIgnored private var homeRefresh: Task<HomeFeed, Error>?

    public private(set) var metadata: MarketMetadata?
    public private(set) var home: HomeFeed?

    public init(client: APIClient, cacheDirectory: URL? = nil, cacheTTL: TimeInterval = 300) {
        self.client = client
        self.cacheTTL = cacheTTL
        self.metadataCache = DiskCache(filename: "market-metadata.json", directory: cacheDirectory)
        self.homeCache = DiskCache(filename: "home-feed.json", directory: cacheDirectory)
    }

    // MARK: - Browse

    /// One page of `/listings` for the given filters. Pages are cached
    /// in-memory per query; pass `refresh: true` to bypass and re-fetch.
    public func browse(_ query: ListingQuery, refresh: Bool = false) async throws -> PageResponse<Listing> {
        if !refresh, let cached = pageCache[query] {
            return cached
        }
        let page: PageResponse<Listing> = try await client.send(
            Endpoint(path: "/listings", query: query.queryItems)
        )
        pageCache[query] = page
        return page
    }

    /// Drops every cached browse page — call on pull-to-refresh so the next
    /// `browse` hits the network.
    public func invalidateBrowseCache() {
        pageCache.removeAll()
    }

    // MARK: - Search suggestions

    /// Typed-ahead suggestions matched locally against cached metadata
    /// (brands, then models, then references). Empty until metadata loads.
    public func suggestions(matching text: String, limit: Int = 8) -> [SearchSuggestion] {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty, let options = metadata?.options else { return [] }

        var results: [SearchSuggestion] = []
        for brand in options.brands where brand.lowercased().contains(needle) {
            results.append(SearchSuggestion(text: brand, kind: .brand))
            if results.count >= limit { return results }
        }
        for group in options.byBrand {
            for model in group.models where model.model.lowercased().contains(needle) {
                results.append(SearchSuggestion(text: model.model, kind: .model(brand: group.brand)))
                if results.count >= limit { return results }
            }
        }
        for group in options.byBrand {
            for model in group.models {
                for reference in model.references where reference.lowercased().contains(needle) {
                    results.append(
                        SearchSuggestion(text: reference, kind: .reference(brand: group.brand, model: model.model))
                    )
                    if results.count >= limit { return results }
                }
            }
        }
        return results
    }

    // MARK: - Metadata (disk-cached, stale-while-revalidate)

    /// Market metadata with a 5-minute disk cache: fresh cache returns
    /// immediately; a stale cache returns immediately *and* refreshes in the
    /// background; no cache fetches synchronously.
    @discardableResult
    public func loadMetadata(forceRefresh: Bool = false) async throws -> MarketMetadata {
        if !forceRefresh, let entry = metadataCache.load() {
            metadata = entry.value
            if !entry.isFresh(ttl: cacheTTL) {
                refreshMetadataInBackground()
            }
            return entry.value
        }
        let fresh = try await fetchMetadata()
        return fresh
    }

    private func refreshMetadataInBackground() {
        guard metadataRefresh == nil else { return }
        metadataRefresh = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchMetadata()
        }
        Task { [weak self] in
            _ = try? await self?.metadataRefresh?.value
            self?.metadataRefresh = nil
        }
    }

    private func fetchMetadata() async throws -> MarketMetadata {
        let fresh: MarketMetadata = try await client.send(
            Endpoint(path: "/listings/metadata", requiresAuth: false)
        )
        metadata = fresh
        metadataCache.save(fresh)
        return fresh
    }

    // MARK: - Home feed (same caching policy)

    @discardableResult
    public func loadHome(forceRefresh: Bool = false) async throws -> HomeFeed {
        if !forceRefresh, let entry = homeCache.load() {
            home = entry.value
            if entry.value.metadata.counts.liveTotal > 0, metadata == nil {
                metadata = entry.value.metadata
            }
            if !entry.isFresh(ttl: cacheTTL) {
                refreshHomeInBackground()
            }
            return entry.value
        }
        return try await fetchHome()
    }

    private func refreshHomeInBackground() {
        guard homeRefresh == nil else { return }
        homeRefresh = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.fetchHome()
        }
        Task { [weak self] in
            _ = try? await self?.homeRefresh?.value
            self?.homeRefresh = nil
        }
    }

    private func fetchHome() async throws -> HomeFeed {
        let fresh: HomeFeed = try await client.send(Endpoint(path: "/listings/home"))
        home = fresh
        homeCache.save(fresh)
        if metadata == nil {
            metadata = fresh.metadata
        }
        return fresh
    }

    // MARK: - Recommendations

    /// Personalized listings from the backend recommendation engine. `forYou`
    /// powers the home shelf; `discover` powers the swipe deck (paged). When
    /// the caller is signed in the ranking blends their brand/price affinity,
    /// popularity and freshness; guests get a popularity/freshness blend.
    public func recommendations(
        surface: RecommendationSurface,
        page: Int = 1,
        limit: Int = 24,
        recentlyViewedLimit: Int = 0,
        excluding excludeIDs: [String] = []
    ) async throws -> RecommendationFeed {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "surface", value: surface.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "recently_viewed_limit", value: String(recentlyViewedLimit)),
        ]
        if !excludeIDs.isEmpty {
            query.append(URLQueryItem(name: "exclude", value: excludeIDs.joined(separator: ",")))
        }
        return try await client.send(Endpoint(path: "/listings/recommendations", query: query))
    }

    // MARK: - Detail / storefront / similar

    /// Full listing detail. `includeShipping` adds a buyer shipping estimate
    /// when the caller is signed in with an address on file.
    public func listing(id: String, includeShipping: Bool = false) async throws -> Listing {
        var query: [URLQueryItem] = [URLQueryItem(name: "include_reputation", value: "true")]
        if includeShipping {
            query.append(URLQueryItem(name: "include_shipping", value: "true"))
        }
        return try await client.send(Endpoint(path: "/listings/\(id)", query: query))
    }

    /// Public seller storefront header (stats, reputation, recent reviews).
    public func sellerStorefront(username: String) async throws -> SellerStorefront {
        try await client.send(Endpoint(path: "/sellers/\(username)", requiresAuth: false))
    }

    /// A seller's active listings — one storefront page.
    public func sellerListings(username: String, page: Int = 1, pageSize: Int = 24) async throws -> PageResponse<Listing> {
        try await browse(ListingQuery(seller: username, page: page, pageSize: pageSize))
    }

    /// Listings similar to the given one: same brand+model first, falling
    /// back to same brand. The source listing itself is filtered out.
    public func similarListings(to listing: Listing, limit: Int = 12) async throws -> [Listing] {
        guard let brand = listing.brand else { return [] }
        var query = ListingQuery(brand: brand, pageSize: limit + 1, includeTotal: false)
        query.model = listing.model
        var results = try await browse(query).results.filter { $0.id != listing.id }
        if results.isEmpty, listing.model != nil {
            query.model = nil
            results = try await browse(query).results.filter { $0.id != listing.id }
        }
        return Array(results.prefix(limit))
    }
}

// MARK: - Recommendation types

/// Which recommendation surface to fetch. Matches the backend `surface` param.
public enum RecommendationSurface: String, Sendable {
    /// The home "For you" shelf — a single ranked page.
    case forYou = "for_you"
    /// The Discover deck — a ranked, paged stream.
    case discover
}

/// The recommendation payload: a ranked set plus the member's recent views.
public struct RecommendationFeed: Decodable, Sendable {
    public let recommended: [Listing]
    public let recentlyViewed: [Listing]

    public init(recommended: [Listing], recentlyViewed: [Listing]) {
        self.recommended = recommended
        self.recentlyViewed = recentlyViewed
    }

    // Tolerate either key being absent (e.g. discover omits recently viewed).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommended = try container.decodeIfPresent([Listing].self, forKey: .recommended) ?? []
        recentlyViewed = try container.decodeIfPresent([Listing].self, forKey: .recentlyViewed) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case recommended
        case recentlyViewed
    }
}
