import CalibreDesign
import CalibreKit
import SwiftUI
import UIKit

/// The five-tab shell. Every tab is a NavigationStack bound to its path in
/// the shared router, so deep links and pushes work from anywhere.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AuthSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    /// The vault's biometric gate lives here, above the Vault tab's whole
    /// navigation stack, so everything the tab can show is behind it — see
    /// `vaultGate`.
    @State private var vaultLock = VaultLock()

    var body: some View {
        @Bindable var router = router

        TabView(selection: router.tabSelection) {
            NavigationStack(path: $router.homePath) {
                HomeScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.communityPath) {
                CommunityScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .tabItem { Label("Community", systemImage: "bubble.left.and.bubble.right") }
            .tag(AppTab.community)

            NavigationStack(path: $router.sellPath) {
                SellScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
            .tag(AppTab.sell)

            NavigationStack(path: $router.collectionPath) {
                CollectionScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .environment(vaultLock)
            .vaultGate(vaultLock, signedIn: session.isAuthenticated)
            .tabItem { Label("Vault", systemImage: "latch.2.case") }
            .tag(AppTab.collection)

            NavigationStack(path: $router.youPath) {
                YouScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .tabItem {
                Label {
                    Text("Me")
                } icon: {
                    Image(uiImage: meTabIcon).renderingMode(.original)
                }
                .accessibilityLabel(hasNotifications ? "Me, notifications waiting" : "Me")
            }
            .tag(AppTab.you)
        }
        .tint(Color.calibre.primary)
        .task(id: notificationRefresh) {
            guard session.isAuthenticated, scenePhase == .active else { return }
            try? await services.serverAlerts.load()
        }
        // The fallback push, for a caller standing on a tab's root screen with
        // nothing above it: append to that tab's path. Every pushed screen
        // overrides this with a node of its own, so this is the only place a
        // push is still addressed to the tab rather than to the stack.
        .environment(\.routePush) { router.push($0) }
        // Checkout owns its own navigation stack, so it rides above the tabs
        // as a cover rather than pushing into one.
        .fullScreenCover(item: $router.checkoutRequest) { request in
            CheckoutFlow(listingIDs: request.listingIDs, offerID: request.offerID)
        }
        // The swipe deck — opened from the Home header, full-screen like the
        // dedicated tab it used to be. The deck hides the navigation bar and
        // draws its own close button in its header.
        .fullScreenCover(isPresented: $router.deckPresented) {
            NavigationStack(path: $router.deckPath) {
                DiscoverScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
            }
            // The deck raises guest gates of its own — Save, the Saved chip,
            // and every gated action on a listing opened inside it. The root's
            // sheet cannot reach over this cover, so the cover carries one.
            .authGate(for: .deck)
        }
    }

    /// A 4pt brand-colored dot, drawn into the native tab icon so the system
    /// does not replace it with its much larger red notification badge.
    private var meTabIcon: UIImage {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let tint = UIColor(router.selectedTab == .you ? Color.calibre.primary : Color.calibre.mutedForeground)
            .resolvedColor(with: traits)
        let person = UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { context in
            person?.draw(in: CGRect(x: 2, y: 3, width: 22, height: 23))
            if hasNotifications {
                UIColor(Color.calibre.primary).resolvedColor(with: traits).setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 23, y: 1, width: 4, height: 4))
            }
        }
    }

    private var hasNotifications: Bool {
        session.isAuthenticated
            ? services.serverAlerts.remainingCount > 0
            : services.alerts.remainingCount > 0
    }

    /// Refresh on sign-in, foregrounding, or an incoming push. Clearing the
    /// inbox already updates the observable store and removes the dot.
    private var notificationRefresh: NotificationRefresh {
        NotificationRefresh(
            userID: session.user?.id,
            active: scenePhase == .active,
            latestPushID: services.alerts.items.first?.id
        )
    }

    private struct NotificationRefresh: Hashable {
        let userID: String?
        let active: Bool
        let latestPushID: String?
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
            .calibrePageBackground()
            // Anything reached this way is standing above something, so its own
            // pushes have to land above it rather than rewrite the tab's path.
            .routeStackNode()
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
        case .poll(let prompt):
            PollDetailScreen(prompt: prompt)
        case .vaultWatch(let id):
            VaultWatchDetailScreen(vaultID: id)
        case .passport(let code):
            PassportScreen(publicCode: code)
        case .authenticationReport(let target):
            AuthenticationReportScreen(target: target)
        case .order(let id):
            OrderDetailScreen(orderID: id)
        case .offer(let id):
            OfferDetailScreen(offerID: id)
        case .supportChat:
            SupportThreadsScreen()
        case .supportThread(let id):
            SupportChatScreen(entry: .thread(id))
        case .messages:
            MessagesListScreen()
        case .messageThread(let id):
            MessageThreadScreen(threadID: id)
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
