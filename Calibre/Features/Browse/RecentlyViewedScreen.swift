import CalibreDesign
import CalibreKit
import SwiftUI

/// Every on-device "recently viewed" id resolved to its full listing — the
/// "View all" destination for Home's Recently Viewed lane. There's no
/// server-side query for this (the ids live in `LocalSignals`, not a
/// filterable facet), so this fetches each listing directly, the same way
/// `HomeModel.loadRecentlyViewed()` does.
@MainActor
@Observable
final class RecentlyViewedModel {
    private(set) var listings: [Listing] = []
    private(set) var isLoading = true
    private(set) var failed = false

    @ObservationIgnored private let services: AppServices
    /// Guards the final commit below: a double-tapped "Try again" or a pull
    /// to refresh landing while the initial load is still in flight must not
    /// let the slower call win.
    @ObservationIgnored private var loadGeneration = 0

    init(services: AppServices) {
        self.services = services
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let ids = services.signals.recentlyViewed
        guard !ids.isEmpty else {
            listings = []
            failed = false
            isLoading = false
            return
        }

        isLoading = true
        failed = false
        let catalog = services.catalog
        var byID: [String: Listing] = [:]
        var anySucceeded = false
        await withTaskGroup(of: Listing?.self) { group in
            for id in ids {
                group.addTask { try? await catalog.listing(id: id) }
            }
            for await listing in group {
                if let listing {
                    anySucceeded = true
                    if listing.status == .active {
                        byID[listing.id] = listing
                    }
                }
            }
        }
        guard generation == loadGeneration else { return }
        listings = ids.compactMap { byID[$0] }
        failed = !anySucceeded
        isLoading = false
    }
}

struct RecentlyViewedScreen: View {
    @Environment(AppServices.self) private var services

    @State private var model: RecentlyViewedModel?
    @Namespace private var zoomNamespace

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ResultsGridSkeleton()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Recently Viewed")
        .navigationBarTitleDisplayMode(.inline)
        .browseStackNode()
        .task {
            if model == nil {
                model = RecentlyViewedModel(services: services)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: RecentlyViewedModel) -> some View {
        if model.isLoading, model.listings.isEmpty {
            ResultsGridSkeleton()
        } else if model.listings.isEmpty {
            EmptyState(
                icon: model.failed ? "wifi.slash" : "clock",
                title: model.failed ? "Couldn't load recently viewed" : "Nothing viewed yet",
                message: model.failed
                    ? "Check your connection and try again."
                    : "Watches you look at will show up here.",
                actionTitle: model.failed ? "Try again" : nil
            ) {
                Task { await model.load() }
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Space.l),
                        GridItem(.flexible(), spacing: Space.l),
                    ],
                    alignment: .leading,
                    spacing: Space.xl
                ) {
                    ForEach(model.listings) { listing in
                        ListingGridCard(listing: listing, laneKey: "recentGrid", zoomNamespace: zoomNamespace)
                    }
                }
                .padding(Space.margin)
            }
            .refreshable {
                await model.load()
            }
        }
    }
}
