import RewoundDesign
import RewoundKit
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

    @Environment(BetaStore.self) private var beta
    /// Shown once per install, like the intro carousel beside it. Per install
    /// rather than per account, because the letter has to arrive before there
    /// is an account — that is the moment a first impression exists, and a
    /// welcome behind a sign-in would only ever reach people who got past one.
    @AppStorage("hasSeenBetaWelcome") private var hasSeenBetaWelcome = false
    @State private var showsBetaWelcome = false
    @State private var showsBetaFeedback = false

    var body: some View {
        @Bindable var router = router

        TabView(selection: router.tabSelection) {
            NavigationStack(path: $router.homePath) {
                HomeScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .betaBarInset(onTapFeedback: { showsBetaFeedback = true }, onTapWelcome: { showsBetaWelcome = true })
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack(path: $router.communityPath) {
                CommunityScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .betaBarInset(onTapFeedback: { showsBetaFeedback = true }, onTapWelcome: { showsBetaWelcome = true })
            .tabItem { Label("Community", systemImage: "bubble.left.and.bubble.right") }
            .tag(AppTab.community)

            NavigationStack(path: $router.sellPath) {
                SellScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .betaBarInset(onTapFeedback: { showsBetaFeedback = true }, onTapWelcome: { showsBetaWelcome = true })
            .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
            .tag(AppTab.sell)

            NavigationStack(path: $router.collectionPath) {
                CollectionScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .environment(vaultLock)
            .vaultGate(vaultLock, signedIn: session.isAuthenticated)
            .betaBarInset(onTapFeedback: { showsBetaFeedback = true }, onTapWelcome: { showsBetaWelcome = true })
            .tabItem { Label("Vault", systemImage: "latch.2.case") }
            .tag(AppTab.collection)

            NavigationStack(path: $router.youPath) {
                YouScreen()
                    .navigationDestination(for: Route.self) { RouteDestinationView(route: $0) }
                    .tabJumpBack()
            }
            .betaBarInset(onTapFeedback: { showsBetaFeedback = true }, onTapWelcome: { showsBetaWelcome = true })
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
        .tint(Color.rewound.primary)
        .task(id: notificationRefresh) {
            guard session.isAuthenticated, scenePhase == .active else { return }
            try? await services.serverAlerts.load()
            services.push.updateApplicationBadge()
        }
        .onChange(of: services.serverAlerts.remainingCount) { _, _ in
            services.push.updateApplicationBadge()
        }
        .onChange(of: services.alerts.remainingCount) { _, _ in
            services.push.updateApplicationBadge()
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
        .sheet(isPresented: $showsBetaWelcome) {
            BetaWelcomeSheet()
        }
        .sheet(isPresented: $showsBetaFeedback) {
            BetaFeedbackSheet()
        }
        .task(id: beta.hasLoaded) {
            // Raised once the config has actually arrived, not on appear: the
            // fetch is in flight while this shell mounts, so asking earlier
            // would decide "no beta" for every tester on every launch.
            guard beta.isEnabled, !hasSeenBetaWelcome else { return }
            hasSeenBetaWelcome = true
            showsBetaWelcome = true
        }
    }

    /// A 4pt brand-colored dot, drawn into the native tab icon so the system
    /// does not replace it with its much larger red notification badge.
    private var meTabIcon: UIImage {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let tint = UIColor(router.selectedTab == .you ? Color.rewound.primary : Color.rewound.mutedForeground)
            .resolvedColor(with: traits)
        let person = UIImage(systemName: "person.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { context in
            person?.draw(in: CGRect(x: 2, y: 3, width: 22, height: 23))
            if hasNotifications {
                UIColor(Color.rewound.primary).resolvedColor(with: traits).setFill()
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
            .rewoundPageBackground()
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
        case .accountSettings:
            YouScreen()
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
        Color.rewound.background
            .onAppear {
                services.router.presentCheckout(listingID: listingID, offerID: offerID)
            }
    }
}

/// The beta bar, inset above a tab's own navigation bar.
///
/// A stack above the NavigationStack, not a safeAreaInset, and not on the
/// TabView.
///
/// A safeAreaInset reserves room inside SwiftUI content, but a
/// NavigationStack's navigation bar is UIKit and lays itself out against the
/// *window's* safe area, so it ignored the inset and drew underneath the bar.
/// On Home and Community that was invisible, because neither shows a system
/// navigation bar; on Vault, and on any pushed screen, it swallowed the title
/// and the back button (Eytan, 2026-09-22: "I noticed the beta thing on
/// vault"). Putting the bar in a VStack above the stack moves the stack's
/// whole frame down, and the navigation bar comes with it.
///
/// Still not a VStack around the TabView. Wrapping it changed the
/// accessibility hierarchy enough that `app.tabBars` began matching two "Me"
/// buttons and RewoundUITests could no longer tap the tab at all — a real
/// regression for anybody driving the app by VoiceOver, not just for the test
/// that caught it. TabView stays the root here.
///
/// The bar draws nothing when the programme is off, and an inset around an
/// empty view reserves no space, so this costs a tester-free build nothing.
private struct BetaBarInset: ViewModifier {
    let onTapFeedback: () -> Void
    let onTapWelcome: () -> Void

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            BetaBar(onTapFeedback: onTapFeedback, onTapWelcome: onTapWelcome)
            content
        }
    }
}

extension View {
    fileprivate func betaBarInset(
        onTapFeedback: @escaping () -> Void,
        onTapWelcome: @escaping () -> Void
    ) -> some View {
        modifier(BetaBarInset(onTapFeedback: onTapFeedback, onTapWelcome: onTapWelcome))
    }
}
