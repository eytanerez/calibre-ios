import CalibreDesign
import CalibreKit
import SwiftUI

/// Everything the home feed shows: the curated lanes, fresh arrivals, the
/// on-device recently-viewed lane, and the signed-in greeting.
@MainActor
@Observable
final class HomeModel {
    enum Phase {
        case loading, loaded, failed
    }

    private(set) var phase: Phase = .loading
    private(set) var forYou: [Listing] = []
    private(set) var fresh: [Listing] = []
    private(set) var popular: [Listing] = []
    private(set) var recentlyViewed: [Listing] = []
    private(set) var greetingName: String?

    @ObservationIgnored private let services: AppServices
    /// Guards `load()`'s final commit: a pull-to-refresh landing while the
    /// initial `.task`-triggered load is still in flight (or two overlapping
    /// refreshes) must not let the slower call's stale result win.
    @ObservationIgnored private var loadGeneration = 0
    /// `loadRecentlyViewed()`/`loadAccountBits()` are also triggered
    /// standalone by `.onChange` (independent of any `load()` call), so each
    /// gets its own generation rather than sharing `loadGeneration` — an
    /// unrelated shelf refresh shouldn't drop a fresher signal-triggered
    /// update, and vice versa.
    @ObservationIgnored private var recentlyViewedGeneration = 0
    @ObservationIgnored private var accountBitsGeneration = 0

    init(services: AppServices) {
        self.services = services
    }

    /// Top brands by live count for the chip rail.
    var topBrands: [BrandGroup] {
        (services.catalog.metadata?.options.byBrand ?? [])
            .sorted { ($0.liveTotal ?? 0) > ($1.liveTotal ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    /// Loads every shelf concurrently and reveals the page once — a partial
    /// success (say, fresh arrivals failed but the main feed came through)
    /// still flips `phase` a single time, so shelves/greeting/brand rail
    /// never pop in on top of an already-visible page. The three helpers
    /// return local snapshots rather than writing `fresh`/`recentlyViewed`/
    /// `greetingName` themselves, so a superseded `load()` can't commit a
    /// stale result after a newer one already won.
    func load(refresh: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if refresh {
            services.catalog.invalidateBrowseCache()
        }

        async let home = try? services.catalog.loadHome(forceRefresh: refresh)
        async let metadataLoad: Void = loadMetadata(refresh: refresh)
        async let freshResult = fetchFresh(refresh: refresh)
        async let recentTask: Void = loadRecentlyViewed()
        async let accountTask: Void = loadAccountBits()

        let loadedHome = await home
        let freshListings = await freshResult
        _ = await (metadataLoad, recentTask, accountTask)

        guard generation == loadGeneration, !Task.isCancelled else { return }
        if let freshListings {
            fresh = freshListings
        }
        if let loadedHome {
            // The recommended lane is server-stubbed empty today; the popular
            // lane stands in so "For you" is never a blank shelf. "Popular
            // right now" then leans on trending (most viewed) to avoid two
            // identical rows.
            forYou = loadedHome.recommended.isEmpty ? loadedHome.popular : loadedHome.recommended
            popular = loadedHome.trending.isEmpty ? loadedHome.popular : loadedHome.trending
            phase = .loaded
        } else if forYou.isEmpty {
            phase = .failed
        } else {
            // A refresh's home fetch failed, but the page already has content
            // from a prior successful load — keep showing it.
            phase = .loaded
        }
    }

    private func loadMetadata(refresh: Bool) async {
        _ = try? await services.catalog.loadMetadata(forceRefresh: refresh)
    }

    /// "Fresh arrivals" — the newest live listings; the home feed has no
    /// fresh lane, so this is a browse query sorted newest-first. Returns the
    /// snapshot instead of writing `fresh` directly; `load()` commits it.
    private func fetchFresh(refresh: Bool) async -> [Listing]? {
        let query = ListingQuery(sort: .createdDesc, pageSize: 12, includeTotal: false)
        guard let page = try? await services.catalog.browse(query, refresh: refresh) else { return nil }
        return page.results
    }

    /// LocalSignals ids → full listings, order preserved, failures dropped.
    /// Called both from `load()` and standalone from an `.onChange` on the
    /// signal itself — its own generation keeps those two triggers from
    /// clobbering each other.
    func loadRecentlyViewed() async {
        recentlyViewedGeneration += 1
        let generation = recentlyViewedGeneration
        let ids = Array(services.signals.recentlyViewed.prefix(8))
        guard !ids.isEmpty else {
            if generation == recentlyViewedGeneration, !Task.isCancelled {
                recentlyViewed = []
            }
            return
        }
        let catalog = services.catalog
        var byID: [String: Listing] = [:]
        await withTaskGroup(of: Listing?.self) { group in
            for id in ids {
                group.addTask {
                    try? await catalog.listing(id: id)
                }
            }
            for await listing in group {
                if let listing, listing.status == .active {
                    byID[listing.id] = listing
                }
            }
        }
        guard generation == recentlyViewedGeneration, !Task.isCancelled else { return }
        recentlyViewed = ids.compactMap { byID[$0] }
    }

    /// Greeting name plus the cart/watchlist state the header and cards need.
    /// Called both from `load()` and standalone from an `.onChange` on
    /// `isAuthenticated` — its own generation keeps those two triggers from
    /// clobbering each other.
    func loadAccountBits() async {
        accountBitsGeneration += 1
        let generation = accountBitsGeneration
        guard services.auth.isAuthenticated else {
            if generation == accountBitsGeneration, !Task.isCancelled {
                greetingName = nil
            }
            return
        }
        let client = services.client
        let commerce = services.commerce
        async let profile = try? client.accountProfile()
        async let cart = try? commerce.loadCart()
        async let watchlist = try? commerce.loadWatchlist()
        let loaded = await profile
        _ = await (cart, watchlist)
        guard generation == accountBitsGeneration, !Task.isCancelled else { return }
        if let first = loaded?.firstName, !first.isEmpty {
            greetingName = first
        } else {
            greetingName = services.auth.user?.username
        }
    }

    static func greetingPrefix(hour: Int) -> String {
        switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}
