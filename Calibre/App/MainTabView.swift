import CalibreDesign
import CalibreKit
import SwiftUI

/// The five-tab shell. Every tab is a NavigationStack bound to its path in
/// the shared router, so deep links and pushes work from anywhere.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.homePath) {
                HomeScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.discoverPath) {
                DiscoverScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
            }
            .tabItem { Label("Discover", systemImage: "rectangle.stack") }
            .tag(AppTab.discover)

            NavigationStack(path: $router.sellPath) {
                SellScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
            }
            .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
            .tag(AppTab.sell)

            NavigationStack(path: $router.activityPath) {
                ActivityScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
            }
            .tabItem { Label("Activity", systemImage: "bell") }
            .tag(AppTab.activity)

            NavigationStack(path: $router.youPath) {
                YouScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
            }
            .tabItem { Label("You", systemImage: "person") }
            .tag(AppTab.you)
        }
        .tint(Color.calibre.primary)
    }
}

/// Placeholder destinations for routed pushes. The P3–P7 feature tracks
/// replace these cases with the real screens.
struct RouteDestinationView: View {
    let route: Route

    var body: some View {
        Group {
            switch route {
            case .listing(let id):
                placeholder(
                    icon: "clock",
                    title: "Listing detail",
                    message: "The listing page arrives with the Browse build.",
                    detail: id
                )
            case .seller(let id):
                placeholder(
                    icon: "person.crop.square",
                    title: "Seller profile",
                    message: "Seller profiles arrive with the Browse build.",
                    detail: id
                )
            case .brand(let id):
                placeholder(
                    icon: "crown",
                    title: "Brand",
                    message: "Brand pages arrive with the Browse build.",
                    detail: id
                )
            case .order(let id):
                placeholder(
                    icon: "shippingbox",
                    title: "Order",
                    message: "Order tracking arrives with the Activity build.",
                    detail: id
                )
            case .offer(let id):
                placeholder(
                    icon: "arrow.left.arrow.right",
                    title: "Offer",
                    message: "Negotiations arrive with the Offers build.",
                    detail: id
                )
            case .journalArticle(let id):
                placeholder(
                    icon: "text.book.closed",
                    title: "Journal",
                    message: "The Journal reader arrives with a later build.",
                    detail: id
                )
            case .supportChat:
                placeholder(
                    icon: "bubble.left.and.bubble.right",
                    title: "Support",
                    message: "Support chat arrives with the Activity build.",
                    detail: nil
                )
            case .alerts:
                // P5 TEMP WIRING — revert before landing: calibre://alerts
                // opens the money-track verification harness in DEBUG builds.
                #if DEBUG
                P5DebugHarness()
                #else
                placeholder(
                    icon: "bell",
                    title: "Alerts",
                    message: "Your alerts inbox arrives with the Activity build.",
                    detail: nil
                )
                #endif
            case .checkout(let listingID, _):
                placeholder(
                    icon: "creditcard",
                    title: "Checkout",
                    message: "Checkout arrives with the Checkout and Offers build.",
                    detail: listingID
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
    }

    private func placeholder(icon: String, title: String, message: String, detail: String?) -> some View {
        VStack(spacing: Space.l) {
            EmptyState(icon: icon, title: title, message: message)
            if let detail {
                Eyebrow(detail)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
