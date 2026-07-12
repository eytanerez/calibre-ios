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

    func load(refresh: Bool = false) async {
        if refresh {
            services.catalog.invalidateBrowseCache()
        }
        do {
            let home = try await services.catalog.loadHome(forceRefresh: refresh)
            // The recommended lane is server-stubbed empty today; the popular
            // lane stands in so "For you" is never a blank shelf. "Popular
            // right now" then leans on trending (most viewed) to avoid two
            // identical rows.
            forYou = home.recommended.isEmpty ? home.popular : home.recommended
            popular = home.trending.isEmpty ? home.popular : home.trending
            phase = .loaded
        } catch {
            if forYou.isEmpty {
                phase = .failed
            }
        }

        _ = try? await services.catalog.loadMetadata(forceRefresh: refresh)
        await loadFresh(refresh: refresh)
        await loadRecentlyViewed()
        await loadAccountBits()
    }

    /// "Fresh arrivals" — the newest live listings; the home feed has no
    /// fresh lane, so this is a browse query sorted newest-first.
    private func loadFresh(refresh: Bool) async {
        let query = ListingQuery(sort: .createdDesc, pageSize: 12, includeTotal: false)
        if let page = try? await services.catalog.browse(query, refresh: refresh) {
            fresh = page.results
        }
    }

    /// LocalSignals ids → full listings, order preserved, failures dropped.
    func loadRecentlyViewed() async {
        let ids = Array(services.signals.recentlyViewed.prefix(8))
        guard !ids.isEmpty else {
            recentlyViewed = []
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
        recentlyViewed = ids.compactMap { byID[$0] }
    }

    /// Greeting name plus the cart/watchlist state the header and cards need.
    func loadAccountBits() async {
        guard services.auth.isAuthenticated else {
            greetingName = nil
            return
        }
        let client = services.client
        let commerce = services.commerce
        async let profile = try? client.accountProfile()
        async let cart = try? commerce.loadCart()
        async let watchlist = try? commerce.loadWatchlist()
        let loaded = await profile
        _ = await (cart, watchlist)
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
