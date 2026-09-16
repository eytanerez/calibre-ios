import RewoundDesign
import RewoundKit
import SwiftUI

/// Home's model: the server-composed feed, plus the shelves that are plain
/// queries rather than a ranking.
///
/// **Nothing here ranks anything.** The order, the copy, the selection reasons
/// and the omissions all arrive decided from `GET /home/feed`; this class
/// fetches them, holds them, and patches one module in place after a vote. The
/// shelves that used to be scored on the phone are gone, and re-introducing a
/// local score would put this app back on a different Home from the site's.
///
/// The split is the same one the web page draws. "Recently viewed" is a list
/// this device kept; "popular" and "fresh arrivals" are sorted queries. None of
/// them re-orders the server's shelf, and none of them claims to be personal.
@MainActor
@Observable
final class HomeModel {
    enum Phase {
        case loading, loaded, failed
    }

    /// How deep the app's own shelves go. The feed's modules are sized by the
    /// server and this does not touch them.
    private static let shelfSize = 12

    private(set) var phase: Phase = .loading
    /// The feed as last served, or nil before the first load settles.
    private(set) var feed: ComposedHomeFeed?
    /// On-device history: the ids this device recorded, resolved to listings.
    private(set) var recentlyViewed: [Listing] = []
    /// What the market is looking at, from `/listings/home`'s curated lanes.
    private(set) var popular: [Listing] = []
    /// What arrived last, newest first.
    private(set) var fresh: [Listing] = []

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let feedStore: HomeFeedStore

    /// Guards `load()`'s final commit: a pull-to-refresh landing while the
    /// initial `.task`-triggered load is still in flight (or two overlapping
    /// refreshes) must not let the slower call's stale result win.
    @ObservationIgnored private var loadGeneration = 0
    /// `loadRecentlyViewed()` is also triggered standalone by an `.onChange`
    /// on the signal itself (independent of any `load()` call), so it gets its
    /// own generation rather than sharing `loadGeneration` — an unrelated feed
    /// refresh shouldn't drop a fresher signal-triggered update, and vice
    /// versa.
    @ObservationIgnored private var recentlyViewedGeneration = 0

    init(services: AppServices) {
        self.services = services
        self.feedStore = HomeFeedStore(client: services.client)
    }

    /// Top brands by live count for the chip rail.
    var topBrands: [BrandGroup] {
        (services.catalog.metadata?.options.byBrand ?? [])
            .sorted { ($0.liveTotal ?? 0) > ($1.liveTotal ?? 0) }
            .prefix(10)
            .map { $0 }
    }

    /// The orders the feed is already asking about, so the tracker above it
    /// doesn't say the same thing twice. Mirrors the server's own dedupe set,
    /// which drops the next step's subject listing before the shop window
    /// draws it.
    var orderIDsInFeed: Set<String> {
        guard let module = nextStep else { return [] }
        return Set(module.sourceRecords.filter { $0.type == "order" }.map(\.id))
    }

    // MARK: - The feed's modules, by name

    // Home places these between shelves of its own rather than stacking them,
    // so it asks for each one. A module the server did not send is nil here and
    // absent on screen.

    var nextStep: HomeFeedModule? { feed?.module(ofType: "your_next_step") }
    var bite: HomeFeedModule? { feed?.module(ofType: "todays_bite") }
    var poll: HomeFeedModule? { feed?.module(ofType: "todays_poll") }
    var savedSearches: HomeFeedModule? { listingModule("saved_search_matches") }
    var collection: HomeFeedModule? { feed?.module(ofType: "your_collection") }
    var endOfFeed: HomeFeedModule? { feed?.module(ofType: "end_of_feed") }

    /// The ranked shelf, under Home's greeting.
    ///
    /// Only the heading is this screen's. The cards, their order, their
    /// selection reasons and the route out are the server's and arrive
    /// composed; the greeting replaces the module's own title so the reader is
    /// greeted once rather than twice.
    var watchesForYou: HomeFeedModule? {
        listingModule("worth_a_look")?
            .retitled(HomeGreeting.watchesForYouTitle(addresses: services.commerce.addresses))
    }

    /// A listing-bearing module, or nil when it has no cards. A module whose
    /// watches have all sold is dropped rather than left as a heading over
    /// nothing — the same rule the server applies when it omits one.
    private func listingModule(_ type: String) -> HomeFeedModule? {
        guard let module = feed?.module(ofType: type), !module.cards.isEmpty else { return nil }
        return module
    }

    /// Loads the feed and the furniture around it. A partial success — the
    /// feed came through but the brand rail's metadata didn't — still flips
    /// `phase` once, so nothing pops in on top of an already-visible page.
    ///
    /// `refresh` clears this app's own caches. It is not the endpoint's
    /// `?refresh=1`, which discards the day's ordering — see `HomeFeedStore`
    /// for why a pull is not spent on that.
    func load(refresh: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if refresh {
            services.catalog.invalidateBrowseCache()
        }

        async let feedResult = fetchFeed()
        async let shelfResult = fetchShelves(refresh: refresh)
        async let metadataLoad: Void = loadMetadata(refresh: refresh)
        async let recentTask: Void = loadRecentlyViewed()
        async let accountTask: Void = loadAccountBits()

        let loadedFeed = await feedResult
        let loadedShelves = await shelfResult
        _ = await (metadataLoad, recentTask, accountTask)

        guard generation == loadGeneration, !Task.isCancelled else { return }
        // Nil is "the request did not come back", which is not the same answer
        // as "the market is empty": a shelf that failed keeps whatever it was
        // already showing rather than clearing itself under the reader.
        if let rows = loadedShelves.popular { popular = rows }
        if let rows = loadedShelves.fresh { fresh = rows }
        if let loadedFeed {
            feed = loadedFeed
            phase = .loaded
        } else if feed == nil {
            // A failed request is not an empty feed, and the two get different
            // words on screen.
            phase = .failed
        } else {
            // A refresh failed, but the page already has a feed from a prior
            // load — keep showing it rather than blanking it.
            phase = .loaded
        }
    }

    /// The session changed. Drop the previous reader's feed before fetching
    /// the next one: an ordering is about one particular person, and a feed
    /// left on screen across a sign-in is the previous account's answer.
    func reloadForSessionChange() async {
        feedStore.reset()
        feed = nil
        phase = .loading
        await load()
    }

    private func fetchFeed() async -> ComposedHomeFeed? {
        try? await feedStore.load(authenticated: services.auth.isAuthenticated)
    }

    /// The shelves that are sorted queries: what the market is looking at, and
    /// what arrived last. Nil for either means its request failed.
    private func fetchShelves(refresh: Bool) async -> (popular: [Listing]?, fresh: [Listing]?) {
        async let curated = try? services.catalog.loadHome(forceRefresh: refresh)
        async let arrivals = try? services.catalog.browse(
            ListingQuery(sort: .createdDesc, pageSize: Self.shelfSize, includeTotal: false),
            refresh: refresh
        )
        let (home, newest) = await (curated, arrivals)

        return (
            popular: home.map { Self.liveListings([$0.trending, $0.popular]) },
            fresh: newest.map { Self.liveListings([$0.results]) }
        )
    }

    /// Active listings, first appearance wins, capped at the shelf's depth. A
    /// watch that appears in both curated lanes is one watch.
    private static func liveListings(_ groups: [[Listing]]) -> [Listing] {
        var seen = Set<String>()
        var rows: [Listing] = []
        for group in groups {
            for listing in group where listing.status == .active {
                guard seen.insert(listing.id).inserted else { continue }
                rows.append(listing)
                if rows.count >= shelfSize { return rows }
            }
        }
        return rows
    }

    private func loadMetadata(refresh: Bool) async {
        _ = try? await services.catalog.loadMetadata(forceRefresh: refresh)
    }

    /// Folds a freshly voted question back into the poll module.
    ///
    /// The module is patched in place. Refetching the feed to redraw one bar
    /// chart would recompute every other module and would be entitled to drop
    /// a sold watch out from under the reader's thumb.
    func applyVote(_ prompt: CommunityPrompt) {
        feedStore.applyVote(prompt)
        feed = feedStore.feed
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

    /// The cart and watchlist state the header badge and the cards need, and
    /// the address book Home says hello out of.
    ///
    /// Nothing here lands on this model — the store owns all three — so there
    /// is no generation to guard. A reader with no address on file is greeted
    /// without a name rather than left waiting for one.
    func loadAccountBits() async {
        guard services.auth.isAuthenticated else { return }
        let commerce = services.commerce
        async let cart = try? commerce.loadCart()
        async let watchlist = try? commerce.loadWatchlist()
        async let addresses = try? commerce.loadAddresses()
        _ = await (cart, watchlist, addresses)
    }
}
