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
        // Checkout owns its own navigation stack, so it rides above the tabs
        // as a cover rather than pushing into one.
        .fullScreenCover(item: $router.checkoutRequest) { request in
            CheckoutFlow(listingID: request.listingID, offerID: request.offerID)
        }
    }
}

/// Resolves a shared `Route` — cross-tab pushes, deep links, and push
/// notifications — to its real screen. Within-tab browse navigation uses the
/// browse track's own `browsePush` mechanism; this handles the rest.
struct RouteDestinationView: View {
    @Environment(AppServices.self) private var services
    let route: Route

    var body: some View {
        destination
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.calibre.background)
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .listing(let id):
            ListingDetailScreen(listingID: id)
        case .seller(let username):
            SellerStorefrontScreen(username: username)
                .browseStackNode()
        case .brand(let brand):
            BrandScreen(brand: brand)
                .browseStackNode()
        case .journal:
            JournalScreen()
                .browseStackNode()
        case .journalArticle(let id):
            JournalArticleScreen(articleID: id)
                .browseStackNode()
        case .order(let id):
            OrderDetailScreen(orderID: id)
        case .offer(let id):
            OfferDetailScreen(offerID: id)
        case .supportChat:
            SupportChatScreen()
        case .alerts:
            AlertsInboxScreen()
        case .checkout(let listingID, let offerID):
            // Reached only if something pushes .checkout directly; the router
            // normally presents it as a cover. Present-on-appear.
            CheckoutRedirect(listingID: listingID, offerID: offerID)
        }
    }
}

/// Safety net: if a `.checkout` route ever lands on a stack, bounce it up to
/// the cover the router owns.
private struct CheckoutRedirect: View {
    @Environment(AppServices.self) private var services
    let listingID: String
    let offerID: String?

    var body: some View {
        Color.calibre.background
            .onAppear {
                services.router.presentCheckout(listingID: listingID, offerID: offerID)
            }
    }
}
