import CalibreDesign
import CalibreKit
import SwiftUI

// MARK: - Paging model

/// One filtered, sorted, infinitely-scrolling slice of `/listings`.
@MainActor
@Observable
final class ResultsModel {
    private(set) var filters: BrowseFilters
    private(set) var listings: [Listing] = []
    private(set) var total: Int?
    private(set) var isLoadingFirst = false
    private(set) var isLoadingMore = false
    private(set) var failed = false

    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var generation = 0

    init(catalog: CatalogStore, filters: BrowseFilters) {
        self.catalog = catalog
        self.filters = filters
    }

    func loadFirstPageIfNeeded() async {
        guard listings.isEmpty, !isLoadingFirst else { return }
        await reload()
    }

    func reload(refresh: Bool = false) async {
        generation += 1
        let expected = generation
        isLoadingFirst = true
        failed = false
        page = 1
        reachedEnd = false
        if refresh {
            catalog.invalidateBrowseCache()
        }
        do {
            let response = try await catalog.browse(filters.query(page: 1))
            guard generation == expected else { return }
            listings = response.results
            total = response.pagination.total
            reachedEnd = response.results.count < response.pagination.pageSize
        } catch {
            guard generation == expected else { return }
            if !(error is CancellationError) {
                failed = true
            }
        }
        if generation == expected {
            isLoadingFirst = false
        }
    }

    func apply(_ newFilters: BrowseFilters) async {
        guard newFilters != filters else { return }
        filters = newFilters
        listings = []
        total = nil
        await reload()
    }

    /// Call from a cell near the tail; pages in the next batch once.
    func loadMoreIfNeeded(current listing: Listing) async {
        guard !reachedEnd, !isLoadingMore, !isLoadingFirst else { return }
        guard let index = listings.lastIndex(where: { $0.id == listing.id }),
              index >= listings.count - 6 else { return }
        isLoadingMore = true
        let expected = generation
        do {
            let response = try await catalog.browse(filters.query(page: page + 1))
            guard generation == expected else { return }
            page += 1
            // The backend can repeat rows across page boundaries when the
            // sort ties; keep ids unique so ForEach stays stable.
            let known = Set(listings.map(\.id))
            listings.append(contentsOf: response.results.filter { !known.contains($0.id) })
            if let total = response.pagination.total { self.total = total }
            reachedEnd = response.results.count < response.pagination.pageSize
        } catch {
            // Quietly stop; the next approach retries.
        }
        if generation == expected {
            isLoadingMore = false
        }
    }
}

// MARK: - Screen

/// The filtered 2-column marketplace grid, arrived at from search or a lane's
/// "view more". Owns a `ResultsModel` and the filter/sort controls.
struct ResultsScreen: View {
    @Environment(AppServices.self) private var services

    let filters: BrowseFilters
    let title: String

    @State private var model: ResultsModel?

    var body: some View {
        Group {
            if let model {
                ResultsContent(model: model, lockedBrand: nil)
            } else {
                ResultsGridSkeleton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .task {
            if model == nil {
                model = ResultsModel(catalog: services.catalog, filters: filters)
            }
            await model?.loadFirstPageIfNeeded()
        }
    }
}

// MARK: - Shared grid + controls

/// Count line, filter button, sort menu and the paging grid — shared by
/// `ResultsScreen` and `BrandScreen` (which locks the brand facet).
struct ResultsContent: View {
    @Environment(AppServices.self) private var services

    @Bindable var model: ResultsModel
    /// Non-nil when the brand is fixed by the screen (BrandScreen): the
    /// filter sheet hides the brand cascade and the badge ignores it.
    let lockedBrand: String?
    /// Slot rendered above the controls, inside the scroll (brand hero).
    var header: AnyView?

    @State private var showFilters = false
    @Namespace private var zoomNamespace

    private var countLine: String {
        if let total = model.total {
            return total == 1 ? "1 watch" : "\(total.formatted()) watches"
        }
        return model.isLoadingFirst ? "Counting the market…" : "Watches"
    }

    private var badgeCount: Int {
        model.filters.activeCount(countingBrand: lockedBrand == nil)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                if let header {
                    header
                }

                controls
                    .padding(.horizontal, Space.margin)
                    .padding(.vertical, Space.m)

                grid
            }
            .padding(.bottom, Space.xxl)
        }
        .refreshable {
            await model.reload(refresh: true)
        }
        .sheet(isPresented: $showFilters) {
            FilterSheet(
                metadata: services.catalog.metadata,
                filters: model.filters,
                lockedBrand: lockedBrand
            ) { applied in
                Task { await model.apply(applied) }
            }
        }
        .task {
            // The sheet's cascading pickers need metadata; usually warm.
            _ = try? await services.catalog.loadMetadata()
        }
    }

    private var controls: some View {
        HStack(spacing: Space.s) {
            Text(countLine)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .contentTransition(.numericText())
                .animation(Motion.easeMedium, value: model.total)

            Spacer(minLength: Space.s)

            Button {
                Haptics.shared.play(.press)
                showFilters = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .medium))
                    Text("Filter")
                        .font(CalibreType.label)
                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.primaryForeground)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Color.calibre.primary, in: Circle())
                    }
                }
                .foregroundStyle(Color.calibre.foreground)
                .padding(.horizontal, Space.m)
                .frame(minHeight: 36)
                .background(Color.calibre.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.calibre.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .frame(minHeight: Space.touchTarget)
            .accessibilityLabel(badgeCount > 0 ? "Filter, \(badgeCount) active" : "Filter")

            sortMenu
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                Text("Newest").tag(ListingQuery.Sort.createdDesc)
                Text("Price low to high").tag(ListingQuery.Sort.priceAsc)
                Text("Price high to low").tag(ListingQuery.Sort.priceDesc)
                Text("Most popular").tag(ListingQuery.Sort.popular)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .medium))
                Text("Sort")
                    .font(CalibreType.label)
            }
            .foregroundStyle(Color.calibre.foreground)
            .padding(.horizontal, Space.m)
            .frame(minHeight: 36)
            .background(Color.calibre.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.calibre.border, lineWidth: 1))
        }
        .frame(minHeight: Space.touchTarget)
        .accessibilityLabel("Sort")
    }

    private var sortSelection: Binding<ListingQuery.Sort> {
        Binding(
            get: { model.filters.sort ?? .createdDesc },
            set: { newSort in
                Haptics.shared.play(.selection)
                var filters = model.filters
                filters.sort = newSort
                Task { await model.apply(filters) }
            }
        )
    }

    @ViewBuilder
    private var grid: some View {
        if model.isLoadingFirst, model.listings.isEmpty {
            gridSkeleton
        } else if model.failed, model.listings.isEmpty {
            EmptyState(
                icon: "wifi.slash",
                title: "The market is out of reach",
                message: "We couldn't load these watches. Check your connection and try again.",
                actionTitle: "Try again"
            ) {
                Task { await model.reload() }
            }
        } else if model.listings.isEmpty {
            EmptyState(
                icon: "magnifyingglass",
                title: "No watches match",
                message: "Nothing in the market fits these filters right now. Loosen one or two and look again.",
                actionTitle: badgeCount > 0 ? "Clear filters" : nil
            ) {
                Task { await model.apply(model.filters.cleared(keepBrand: lockedBrand != nil)) }
            }
        } else {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.l),
                    GridItem(.flexible(), spacing: Space.l),
                ],
                alignment: .leading,
                spacing: Space.xl
            ) {
                ForEach(model.listings) { listing in
                    ListingGridCard(
                        listing: listing,
                        laneKey: "grid",
                        zoomNamespace: zoomNamespace
                    )
                    .task {
                        await model.loadMoreIfNeeded(current: listing)
                    }
                }
            }
            .padding(.horizontal, Space.margin)

            if model.isLoadingMore {
                HStack(spacing: Space.l) {
                    ListingCardSkeleton()
                    ListingCardSkeleton()
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.xl)
            }
        }
    }

    private var gridSkeleton: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.l),
                GridItem(.flexible(), spacing: Space.l),
            ],
            spacing: Space.xl
        ) {
            ForEach(0..<6, id: \.self) { _ in
                ListingCardSkeleton()
            }
        }
        .padding(.horizontal, Space.margin)
    }
}

/// Bare skeleton shown for the breath before the model exists.
struct ResultsGridSkeleton: View {
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.l),
                    GridItem(.flexible(), spacing: Space.l),
                ],
                spacing: Space.xl
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    ListingCardSkeleton()
                }
            }
            .padding(Space.margin)
        }
        .disabled(true)
    }
}
