import CalibreDesign
import CalibreKit
import SwiftUI

/// Home: wordmark and bag up top, search, anything still in motion, then the
/// page — the **server-composed feed's** modules placed between the shelves
/// that are plain queries.
///
/// The shelves that used to live here scored listings on the phone — their own
/// profile, their own weights, their own brand cap — and then padded each lane
/// out of a second query when it came up short. That is why this app could
/// never show the same Home as the site, and why "For you" could quietly fill
/// with popular inventory while keeping a personal heading. Ranking now runs
/// once, on the server; every title, every selection reason and every omission
/// that came from the feed is the server's, printed as sent.
///
/// The page's running order is decided once, in `HomeRunningOrder`, and it is
/// the same skeleton the web page runs for both audiences, so the two read
/// alike: this screen only says which sections have something to show. A
/// module the server omitted is absent from that list rather than padded, and
/// a module type this build has never heard of is not in it at all.
struct HomeScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var model: HomeModel?
    @State private var pushed: BrowseDestination?
    @State private var openedBite: BiteRoute?
    @State private var showCart = false
    /// Set by a `CartSheet` callback (which has already called its own
    /// `dismiss()`); consumed by `.sheet(onDismiss:)` once SwiftUI reports
    /// the dismissal animation actually finished — no fixed delay to guess.
    @State private var pendingPushAfterCartDismiss: BrowseDestination?
    @Namespace private var zoomNamespace
    @State private var tutorial = TutorialController(
        id: "home.deck",
        steps: [
            TutorialStep(
                id: "deck",
                anchor: "home.deck",
                title: "Swipe the deck",
                message: "This opens the deck — watches picked for you, one card at a time. Swipe right to save, left to pass.",
                advance: .tapToContinue,
                hint: .tap,
                cutout: .circle
            )
        ]
    )

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.l) {
                    headerRow
                    searchButton
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s)

                // Anything still in motion sits above the page — "where's my
                // watch" beats "here's another watch". The orders the feed is
                // already asking about are left to it, so an awaiting-wire
                // order is not stated twice on one screen.
                ShipmentTrackerSection(handledByFeed: model?.orderIDsInFeed ?? [])

                ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                    sectionView(section)
                        .fadeUpEntrance(index: index)
                }
            }
            .padding(.bottom, Space.xxl)
        }
        .calibrePageBackground()
        .tutorialOverlay(tutorial)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushed) { destination in
            BrowseDestinationView(destination: destination)
        }
        .navigationDestination(item: $openedBite) { route in
            BiteScreen(slug: route.slug, preloaded: route.preloaded)
        }
        .environment(\.browsePush) { pushed = $0 }
        .onAppear { tutorial.startIfNeeded() }
        .refreshable {
            await model?.load(refresh: true)
        }
        .task {
            if model == nil {
                model = HomeModel(services: services)
            }
            await model?.load()
        }
        .onChange(of: session.isAuthenticated) {
            // A feed is composed for one particular reader. Signing in or out
            // does not update it — it replaces it.
            Task { await model?.reloadForSessionChange() }
        }
        .onChange(of: services.signals.recentlyViewed) {
            Task { await model?.loadRecentlyViewed() }
        }
        .sheet(isPresented: $showCart, onDismiss: {
            if let destination = pendingPushAfterCartDismiss {
                pendingPushAfterCartDismiss = nil
                pushed = destination
            }
        }) {
            CartSheet(
                openListing: { id in pendingPushAfterCartDismiss = .listing(id, zoom: nil) },
                openSaved: { pendingPushAfterCartDismiss = .saved }
            )
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            CalibreWordmark(size: 26)

            Spacer()

            // The deck lives one tap from Home — the Journal moved to the
            // Community tab, and its old header slot now opens the swipe deck.
            Button {
                Haptics.shared.play(.press)
                services.router.deckPresented = true
            } label: {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.calibre.foreground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Open the deck")
            .accessibilityIdentifier("home.deck.button")
            .tutorialAnchor("home.deck")

            Button {
                Haptics.shared.play(.press)
                openBag()
            } label: {
                Image(systemName: "bag")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.calibre.foreground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .overlay(alignment: .topTrailing) {
                        if bagCount > 0 {
                            Text("\(bagCount)")
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.primaryForeground)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Color.calibre.primary, in: Circle())
                                .offset(x: -2, y: 4)
                        }
                    }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(bagLabel)
        }
    }

    private var bagCount: Int {
        session.isAuthenticated ? services.commerce.cart.count : 0
    }

    /// The badge is a numeral; VoiceOver reads the sentence, and the sentence
    /// was "Bag, 2 item" for every count above one.
    private var bagLabel: String {
        switch bagCount {
        case 0: "Cart"
        case 1: "Cart, 1 item"
        default: "Cart, \(bagCount) items"
        }
    }

    private var searchButton: some View {
        Button {
            pushed = .search
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
                Text("Search watches")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.placeholder)
                Spacer()
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: Space.touchTarget)
            .background(
                Color.calibre.secondary,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Search watches")
    }

    // MARK: - The running order

    /// Which page to draw. The session decides, as the site decides it; the
    /// feed's own `audience` says what the server composed, which is a
    /// different question.
    private var audience: HomeAudience {
        session.isAuthenticated ? .member : .guest
    }

    /// No model yet is a load in flight, not a feed that failed.
    private var feedState: HomeFeedLoadState {
        switch model?.phase {
        case .loaded: .loaded
        case .failed: .failed
        case .loading, nil: .loading
        }
    }

    /// The sections that have something to show. The order they are drawn in
    /// is not decided here; `HomeRunningOrder` places them, and drops the ones
    /// the audience does not get.
    private var presentSections: Set<HomeSection> {
        guard let model else { return [] }
        var present: Set<HomeSection> = []
        if model.nextStep != nil { present.insert(.nextStep) }
        if model.watchesForYou != nil { present.insert(.watchesForYou) }
        if !model.recentlyViewed.isEmpty { present.insert(.recentlyViewed) }
        if !model.topBrands.isEmpty { present.insert(.brands) }
        if !model.popular.isEmpty { present.insert(.popular) }
        if !model.fresh.isEmpty { present.insert(.freshArrivals) }
        if model.savedSearches != nil { present.insert(.savedSearches) }
        if model.bite != nil { present.insert(.bite) }
        if model.poll != nil { present.insert(.poll) }
        if model.collection != nil { present.insert(.collection) }
        if model.endOfFeed != nil { present.insert(.endOfFeed) }
        return present
    }

    private var sections: [HomeSection] {
        HomeRunningOrder.sections(audience: audience, feed: feedState, present: presentSections)
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section {
        case .feedLoading:
            ListingLaneSkeleton()
            ListingLaneSkeleton()

        case .feedUnavailable:
            // A request that failed is not a quiet day. It says so, and offers
            // the only useful thing.
            EmptyState(
                icon: "wifi.slash",
                title: "The market is out of reach",
                message: "We couldn't load your home feed. Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                Task { await model?.load() }
            }

        case .nextStep:
            if let module = model?.nextStep { moduleView(module) }
        case .watchesForYou:
            if let module = model?.watchesForYou { moduleView(module) }
        case .bite:
            if let module = model?.bite { moduleView(module) }
        case .poll:
            if let module = model?.poll { moduleView(module) }
        case .savedSearches:
            if let module = model?.savedSearches { moduleView(module) }
        case .collection:
            if let module = model?.collection { moduleView(module) }
        case .endOfFeed:
            if let module = model?.endOfFeed { moduleView(module) }

        case .recentlyViewed:
            ListingLaneRow(
                title: "Recently viewed",
                listings: model?.recentlyViewed ?? [],
                laneKey: "recent",
                zoomNamespace: zoomNamespace,
                onViewAll: { pushed = .recentlyViewed }
            )

        case .brands:
            brandRail(model?.topBrands ?? [])

        case .popular:
            ListingLaneRow(
                title: "Popular right now",
                listings: model?.popular ?? [],
                laneKey: "popular",
                zoomNamespace: zoomNamespace,
                onViewAll: {
                    pushed = .results(BrowseFilters(sort: .popular), title: "Popular Right Now")
                }
            )

        case .freshArrivals:
            // The guest page opens with this shelf and heads it as the site
            // does; the member meets the same query further down, under the
            // name the rest of the app uses for it.
            ListingLaneRow(
                title: audience == .guest ? "New this week" : "Fresh arrivals",
                listings: model?.fresh ?? [],
                laneKey: "fresh",
                zoomNamespace: zoomNamespace,
                onViewAll: {
                    pushed = .results(BrowseFilters(sort: .createdDesc), title: "Fresh Arrivals")
                }
            )
        }
    }

    @ViewBuilder
    private func moduleView(_ module: HomeFeedModule) -> some View {
        switch module.body {
        case .nextStep(let step):
            FeedNextStepCard(module: module, step: step, onAction: open)
        case .listings:
            // The two listing-bearing modules are drawn differently on
            // purpose: one is a shop window and one is an answer to a question
            // the reader asked us to keep asking.
            if module.type == "saved_search_matches" {
                FeedSavedSearchModule(module: module, onAction: open)
            } else {
                FeedShopWindowModule(module: module, zoomNamespace: zoomNamespace, onAction: open)
            }
        case .bite(let slot, let bite):
            FeedBiteModule(module: module, slot: slot, bite: bite) { target in
                // The copy on hand rides along when the route names the Bite
                // the module carries, so it draws the moment it opens rather
                // than after a round trip.
                if case .bite(let slug) = target, slug == bite.id {
                    openedBite = BiteRoute(slug: slug, preloaded: bite)
                } else {
                    open(target)
                }
            }
        case .poll(let prompt):
            FeedPollModule(module: module, prompt: prompt) { voted in
                model?.applyVote(voted)
            }
        case .collection(let collection):
            FeedCollectionModule(module: module, collection: collection, onAction: open)
        case .endOfFeed(let state):
            FeedEndModule(module: module, state: state, onAction: open) {
                Task { await model?.load() }
            }
        case .unrecognized:
            // Filtered out above; the switch has to stay exhaustive so a new
            // case here is a compile error rather than a silent omission.
            EmptyView()
        }
    }

    private func open(_ target: FeedActionTarget) {
        switch target {
        case .browse(let destination):
            pushed = destination
        case .route(let route):
            services.router.push(route)
        case .tab(let tab):
            services.router.selectedTab = tab
        case .bite(let slug):
            openedBite = BiteRoute(slug: slug, preloaded: nil)
        }
    }

    // MARK: - Shop by brand

    /// Two across only while a half-width card can still hold a brand name.
    /// At an accessibility size it cannot — "Jaeger-LeCoultre" in half a phone
    /// is a stack of fragments — so the rail becomes one column. At every
    /// default size these are the two flexible columns that ship.
    private var brandColumns: [GridItem] {
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: Space.m)]
        }
        return [
            GridItem(.flexible(), spacing: Space.m),
            GridItem(.flexible(), spacing: Space.m),
        ]
    }

    private func brandRail(_ brands: [BrandGroup]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Browse by brand")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Spacer()
                Button("View all") {
                    pushed = .brands
                }
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.primary)
                .buttonStyle(PressableStyle())
                .accessibilityLabel("View all watch brands")
            }

            LazyVGrid(columns: brandColumns, spacing: Space.m) {
                ForEach(brands.prefix(6), id: \.brand) { group in
                    Button {
                        pushed = .brand(group.brand)
                    } label: {
                        HStack(spacing: Space.s) {
                            Text(group.brand)
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                                // One line with an 0.8 floor is the shipped
                                // look and stays it; past that floor a long
                                // brand name is truncated rather than shrunk,
                                // so above the accessibility threshold the
                                // name wraps instead.
                                .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                                .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                        .padding(.horizontal, Space.m)
                        .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
                        .background(
                            Color.calibre.card,
                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Color.calibre.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Shows watches from \(group.brand)")
                }
            }
        }
        .padding(.horizontal, Space.margin)
    }

    // MARK: - Actions

    private func openBag() {
        let cartPresented = $showCart
        session.requireThenPresent("Sign in to see your cart") {
            cartPresented.wrappedValue = true
        }
    }
}

/// One Bite, pushed from Home.
///
/// Carries the copy the feed already had so today's Bite draws the moment it
/// opens; a Bite named only by an action's route arrives with nothing and the
/// reader fetches it.
struct BiteRoute: Identifiable, Hashable {
    let slug: String
    let preloaded: Bite?

    var id: String { slug }
}
