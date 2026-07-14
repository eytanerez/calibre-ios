import CalibreKit
import Foundation
import Nuke
import Observation

/// One request shape for deck imagery. `LazyImage` and the prefetcher must
/// build identical requests or warmed images miss the memory cache.
enum DeckImage {
    static func request(for url: URL) -> ImageRequest {
        ImageRequest(url: url, processors: [.resize(width: 380, unit: .points, upscale: false)])
    }
}

/// The Discover deck's card queue: pages `/listings` (card view, sorted by
/// popularity), locally excluding everything the user has already passed on
/// or saved, refilling when the unseen buffer runs low and looping pages
/// until the market is exhausted.
@MainActor
@Observable
final class DeckFeed {
    enum Phase: Equatable {
        /// First fill in flight — the deck shows skeleton cards.
        case loading
        /// Cards available (a background refill may still be catching up).
        case ready
        /// Every live listing has been seen, passed, or saved.
        case exhausted
        /// The initial load failed and there is nothing to show.
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    /// The unseen queue — index 0 is the top of the deck.
    private(set) var cards: [Listing] = []

    /// Refill failed while cards are still on screen — the screen toasts it.
    @ObservationIgnored var onTransientError: ((String) -> Void)?

    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let signals: LocalSignals
    @ObservationIgnored private let session: AuthSession

    @ObservationIgnored private var nextPage = 1
    @ObservationIgnored private var pagesExhausted = false
    /// Every id ever enqueued this session — the popular ordering drifts
    /// while we swipe, so later pages can resurface earlier watches.
    @ObservationIgnored private var enqueuedIDs: Set<String> = []
    @ObservationIgnored private var refillTask: Task<Void, Never>?
    @ObservationIgnored private let prefetcher = ImagePrefetcher()
    @ObservationIgnored private var prefetchedURLs: Set<URL> = []

    private static let pageSize = 24
    private static let refillThreshold = 8
    private static let prefetchDepth = 6

    init(catalog: CatalogStore, commerce: CommerceStore, signals: LocalSignals, session: AuthSession) {
        self.catalog = catalog
        self.commerce = commerce
        self.signals = signals
        self.session = session
    }

    var topCard: Listing? { cards.first }

    /// True while there is anything to reset — drives the empty state's CTA.
    var hasPasses: Bool { !signals.discoverPassed.isEmpty }

    // MARK: - Lifecycle

    func start() async {
        #if DEBUG
        // Screenshot/UI-test hook: jump straight to the exhausted state.
        if ProcessInfo.processInfo.arguments.contains("-deckExhausted") {
            pagesExhausted = true
            phase = .exhausted
            return
        }
        // Critical-path UI tests must be able to exercise the real deck and
        // guest save gate even when the development API is offline. These
        // decoded card models use no remote images and never ship in Release.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            cards = Self.uiTestCards
            enqueuedIDs = Set(cards.map(\.id))
            pagesExhausted = true
            phase = cards.isEmpty ? .failed("The UI test deck could not be prepared.") : .ready
            return
        }
        #endif
        if session.isAuthenticated {
            _ = try? await commerce.loadWatchlist()
        }
        await fill()
    }

    /// Retry after a failed initial load, or reload after resetting passes.
    func restart() async {
        refillTask?.cancel()
        refillTask = nil
        catalog.invalidateBrowseCache()
        cards = []
        enqueuedIDs = []
        nextPage = 1
        pagesExhausted = false
        stopPrefetching()
        phase = .loading
        await start()
    }

    /// Clears the local pass-list and deals the market again.
    func resetPassesAndReload() async {
        signals.resetDiscoverPasses()
        await restart()
    }

    /// Called when a sign-in lands mid-session: the watchlist is now real, so
    /// drop anything the account already saved.
    func handleAuthChange() async {
        guard session.isAuthenticated else { return }
        _ = try? await commerce.loadWatchlist()
        cards.removeAll { commerce.watchedListingIDs.contains($0.id) }
        settlePhase()
        refillIfNeeded()
        updatePrefetch()
    }

    // MARK: - Queue

    /// Pops the top card after its fly-off completes.
    @discardableResult
    func removeTop() -> Listing? {
        guard !cards.isEmpty else { return nil }
        let top = cards.removeFirst()
        settlePhase()
        refillIfNeeded()
        updatePrefetch()
        return top
    }

    /// Puts an undone card back on top of the deck.
    func reinsertTop(_ listing: Listing) {
        guard !cards.contains(where: { $0.id == listing.id }) else { return }
        cards.insert(listing, at: 0)
        enqueuedIDs.insert(listing.id)
        if phase == .exhausted || phase == .loading { phase = .ready }
        updatePrefetch()
    }

    /// Tops the buffer back up when ≤8 unseen cards remain.
    func refillIfNeeded() {
        guard !pagesExhausted, refillTask == nil, cards.count <= Self.refillThreshold else { return }
        refillTask = Task { [weak self] in
            await self?.fill()
            self?.refillTask = nil
        }
    }

    // MARK: - Fetch

    private func fill() async {
        do {
            while !pagesExhausted, cards.count <= Self.refillThreshold {
                let query = ListingQuery(
                    sort: .popular,
                    page: nextPage,
                    pageSize: Self.pageSize,
                    view: .card
                )
                let page = try await catalog.browse(query)
                nextPage += 1

                let served = page.pagination.page * page.pagination.pageSize
                if page.results.isEmpty || page.pagination.total.map({ served >= $0 }) == true {
                    pagesExhausted = true
                }

                let fresh = page.results.filter(isEligible)
                enqueuedIDs.formUnion(fresh.map(\.id))
                cards.append(contentsOf: fresh)
            }
            settlePhase()
        } catch is CancellationError {
            return
        } catch {
            let message = error.localizedDescription
            if cards.isEmpty {
                phase = .failed(message)
            } else {
                onTransientError?(message)
            }
        }
        updatePrefetch()
    }

    private func isEligible(_ listing: Listing) -> Bool {
        listing.status == .active
            && !enqueuedIDs.contains(listing.id)
            && !signals.hasPassed(listing.id)
            && !commerce.watchedListingIDs.contains(listing.id)
    }

    private func settlePhase() {
        if cards.isEmpty {
            if pagesExhausted { phase = .exhausted }
            // Otherwise a refill is (about to be) in flight — stay put.
        } else {
            phase = .ready
        }
    }

    // MARK: - Prefetch

    /// Warms the next few card images so swipes never reveal a blank well.
    func updatePrefetch() {
        let urls = cards.prefix(Self.prefetchDepth).compactMap { $0.images.first?.url }
        let fresh = urls.filter { !prefetchedURLs.contains($0) }
        guard !fresh.isEmpty else { return }
        prefetchedURLs.formUnion(fresh)
        prefetcher.startPrefetching(with: fresh.map(DeckImage.request(for:)))
    }

    /// Cancels in-flight warming when the tab goes away.
    func stopPrefetching() {
        prefetcher.stopPrefetching()
        prefetchedURLs.removeAll()
    }

    #if DEBUG
    /// Using the production `Listing` decoder keeps this fixture aligned with
    /// the card model without adding test-only initializers to CalibreKit.
    private static var uiTestCards: [Listing] {
        let json = """
        [
          {
            "id": "ui-test-discover-1",
            "listing_number": 9001,
            "seller_id": "ui-test-seller",
            "title": "Black Bay Fifty-Eight",
            "brand": "Tudor",
            "model": "Black Bay Fifty-Eight",
            "reference_number": "M79030N",
            "price": "4200.00",
            "currency": "USD",
            "condition": { "overall": "Like New" },
            "box_papers": true,
            "production_year": 2023,
            "status": "active",
            "images": []
          },
          {
            "id": "ui-test-discover-2",
            "listing_number": 9002,
            "seller_id": "ui-test-seller",
            "title": "Speedmaster Moonwatch",
            "brand": "Omega",
            "model": "Speedmaster Moonwatch",
            "reference_number": "310.30.42.50.01.002",
            "price": "6850.00",
            "currency": "USD",
            "condition": { "overall": "Very Good" },
            "box_papers": true,
            "production_year": 2022,
            "status": "active",
            "images": []
          },
          {
            "id": "ui-test-discover-3",
            "listing_number": 9003,
            "seller_id": "ui-test-seller",
            "title": "Santos de Cartier",
            "brand": "Cartier",
            "model": "Santos de Cartier",
            "reference_number": "WSSA0029",
            "price": "7450.00",
            "currency": "USD",
            "condition": { "overall": "Excellent" },
            "box_papers": true,
            "production_year": 2024,
            "status": "active",
            "images": []
          }
        ]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode([Listing].self, from: Data(json.utf8))) ?? []
    }
    #endif
}
