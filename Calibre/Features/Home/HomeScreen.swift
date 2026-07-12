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
    @Namespace private var zoomNamespace

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
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushed) { destination in
            BrowseDestinationView(destination: destination)
        }
        .environment(\.browsePush) { pushed = $0 }
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
        .sheet(isPresented: $showCart) {
            CartSheet(
                openListing: { id in pushAfterDismiss(.listing(id, zoom: nil)) },
                openSaved: { pushAfterDismiss(.saved) }
            )
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            CalibreWordmark(size: 26)

            Spacer()

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
                zoomNamespace: zoomNamespace
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
                zoomNamespace: zoomNamespace
            )
            .fadeUpEntrance(index: 2)
        }

        if !model.popular.isEmpty {
            ListingLaneRow(
                title: "Popular right now",
                listings: model.popular,
                laneKey: "popular",
                zoomNamespace: zoomNamespace
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
                zoomNamespace: zoomNamespace
            )
            .fadeUpEntrance(index: 5)
        }
    }

    private func brandRail(_ brands: [BrandGroup]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Browse by brand")
                .padding(.horizontal, Space.margin)
            ChipRail {
                ForEach(brands, id: \.brand) { group in
                    FilterChip(group.brand, isSelected: false) {
                        pushed = .brand(group.brand)
                    }
                }
            }
        }
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

    /// Sheet callbacks land here: let the sheet slide away, then push.
    private func pushAfterDismiss(_ destination: BrowseDestination) {
        Task {
            try? await Task.sleep(for: .milliseconds(380))
            pushed = destination
        }
    }
}
