import CalibreDesign
import CalibreKit
import SwiftUI

/// The listings-first home: wordmark and bag up top, search, a quiet
/// greeting, then shelves of real watches — never a pitch.
struct HomeScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var model: HomeModel?
    @State private var pushed: BrowseDestination?
    @State private var showCart = false
    /// Set by a `CartSheet` callback (which has already called its own
    /// `dismiss()`); consumed by `.sheet(onDismiss:)` once SwiftUI reports
    /// the dismissal animation actually finished — no fixed delay to guess.
    @State private var pendingPushAfterCartDismiss: BrowseDestination?
    @Namespace private var zoomNamespace
    @State private var tutorial = TutorialController(
        id: "home.journal",
        steps: [
            TutorialStep(
                id: "journal",
                anchor: "home.journal",
                title: "Read The Journal",
                message: "This newspaper icon opens The Journal — our stories on the watches and the market. It's always one tap away, right here.",
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
                    greeting
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s)

                shelves
            }
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background)
        .tutorialOverlay(tutorial)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushed) { destination in
            BrowseDestinationView(destination: destination)
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
            Task { await model?.loadAccountBits() }
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

            // A persistent header icon so the Journal reads as its own
            // section — reachable in one tap, not something you have to
            // scroll past a wall of listings to discover.
            Button {
                Haptics.shared.play(.press)
                pushed = .journalIndex
            } label: {
                Image(systemName: "newspaper")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.calibre.foreground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("The Journal")
            .tutorialAnchor("home.journal")

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
            .accessibilityLabel(bagCount > 0 ? "Bag, \(bagCount) item" : "Bag")
        }
    }

    private var bagCount: Int {
        session.isAuthenticated ? services.commerce.cart.count : 0
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

    @ViewBuilder
    private var greeting: some View {
        if session.isAuthenticated, let name = model?.greetingName {
            let hour = Calendar.current.component(.hour, from: .now)
            Text("\(HomeModel.greetingPrefix(hour: hour)), \(name).")
                .font(CalibreType.serif(.regular, 20, relativeTo: .title3))
                .foregroundStyle(Color.calibre.secondaryForeground)
        }
    }

    // MARK: - Shelves

    @ViewBuilder
    private var shelves: some View {
        switch model?.phase ?? .loading {
        case .loading:
            ListingLaneSkeleton()
            ListingLaneSkeleton()
        case .failed:
            EmptyState(
                icon: "wifi.slash",
                title: "The market is out of reach",
                message: "We couldn't load the home feed. Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                Task { await model?.load() }
            }
        case .loaded:
            if let model {
                loadedShelves(model)
                browseAllButton
                    .fadeUpEntrance(index: 6)
            }
        }
    }

    @ViewBuilder
    private func loadedShelves(_ model: HomeModel) -> some View {
        if !model.forYou.isEmpty {
            ListingLaneRow(
                title: "For you",
                listings: model.forYou,
                laneKey: "forYou",
                zoomNamespace: zoomNamespace,
                onViewAll: { pushed = .results(BrowseFilters(sort: .popular), title: "For You") }
            )
            .fadeUpEntrance(index: 0)
        }

        if !model.topBrands.isEmpty {
            brandRail(model.topBrands)
                .fadeUpEntrance(index: 1)
        }

        if !model.fresh.isEmpty {
            ListingLaneRow(
                title: "Fresh arrivals",
                listings: model.fresh,
                laneKey: "fresh",
                zoomNamespace: zoomNamespace,
                onViewAll: { pushed = .results(BrowseFilters(sort: .createdDesc), title: "Fresh Arrivals") }
            )
            .fadeUpEntrance(index: 2)
        }

        if !model.popular.isEmpty {
            ListingLaneRow(
                title: "Popular right now",
                listings: model.popular,
                laneKey: "popular",
                zoomNamespace: zoomNamespace,
                onViewAll: { pushed = .results(BrowseFilters(sort: .mostViewed), title: "Popular Right Now") }
            )
            .fadeUpEntrance(index: 3)
        }

        journalTeaser
            .fadeUpEntrance(index: 4)

        if !model.recentlyViewed.isEmpty {
            ListingLaneRow(
                title: "Recently viewed",
                listings: model.recentlyViewed,
                laneKey: "recent",
                zoomNamespace: zoomNamespace,
                onViewAll: { pushed = .recentlyViewed }
            )
            .fadeUpEntrance(index: 5)
        }
    }

    /// The catalog's front door, always reachable from the bottom of a
    /// loaded home feed — not just from a shelf's "view all".
    private var browseAllButton: some View {
        Button {
            Haptics.shared.play(.press)
            pushed = .results(BrowseFilters(), title: "All Watches")
        } label: {
            Text("Browse all watches")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.calibre(.primary, fullWidth: true))
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.s)
        .accessibilityLabel("Browse all watches")
        .accessibilityHint("Opens the full watch catalog")
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

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.m),
                    GridItem(.flexible(), spacing: Space.m),
                ],
                spacing: Space.m
            ) {
                ForEach(brands.prefix(6), id: \.brand) { group in
                    Button {
                        pushed = .brand(group.brand)
                    } label: {
                        HStack(spacing: Space.s) {
                            Text(group.brand)
                                .font(CalibreType.bodyMedium)
                                .foregroundStyle(Color.calibre.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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

    @ViewBuilder
    private var journalTeaser: some View {
        if let article = JournalStore.shared.latest {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The Journal")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)
                    Spacer()
                    Button("All stories") {
                        pushed = .journalIndex
                    }
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.primary)
                    .buttonStyle(PressableStyle())
                }

                JournalCard(article: article) {
                    pushed = .journalArticle(article.id)
                }
            }
            .padding(.horizontal, Space.margin)
        }
    }

    // MARK: - Actions

    private func openBag() {
        let cartPresented = $showCart
        session.requireThenPresent("Sign in to see your bag") {
            cartPresented.wrappedValue = true
        }
    }
}
