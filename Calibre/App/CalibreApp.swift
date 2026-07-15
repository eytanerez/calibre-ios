import CalibreDesign
import CalibreKit
import Nuke
import SwiftUI

@main
struct CalibreApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate

    init() {
        CalibreFonts.register()

        // Keep original image bytes in an app-owned disk cache so the same
        // watch is not downloaded again for card, row, and gallery sizes.
        // Progressive decoding makes large JPEGs useful before the full body
        // arrives; background preparation keeps final display off the main
        // thread. LazyImage still owns visibility-based request cancellation.
        var imageConfiguration = ImagePipeline.Configuration.withDataCache(
            name: "com.buycalibre.calibre.images",
            sizeLimit: 250 * 1_024 * 1_024
        )
        imageConfiguration.isProgressiveDecodingEnabled = true
        imageConfiguration.isUsingPrepareForDisplay = true
        ImagePipeline.shared = ImagePipeline(configuration: imageConfiguration)

        #if DEBUG
        // UI-test hook: wipe onboarding state so a launch starts at the
        // intro. (Argument-domain defaults can't work here — they shadow
        // the app's own writes, freezing the phase machine.)
        if ProcessInfo.processInfo.arguments.contains("-resetAppState") {
            UserDefaults.standard.set(false, forKey: "hasSeenIntro")
            UserDefaults.standard.set(false, forKey: "guestChosen")
            KeychainTokenStore().clear()
            TutorialLedger.shared.resetAll()
        }
        // Independent hook so a run can replay first-run tutorials without
        // wiping auth/intro state.
        if ProcessInfo.processInfo.arguments.contains("-resetTutorials") {
            TutorialLedger.shared.resetAll()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The app's four lives: waking up, the first-run intro, the sign-in gate,
/// and the tab shell. Transitions are a quiet crossfade with a whisper of
/// scale — never a slide.
struct RootView: View {
    private enum Phase: Equatable {
        case booting, intro, gate, main
    }

    @State private var services = AppServices()
    @State private var bootstrapped = false
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false
    @AppStorage("guestChosen") private var guestChosen = false
    @AppStorage("appearancePreference") private var appearancePreference: AppearancePreference = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: Phase {
        if !bootstrapped { return .booting }
        if services.auth.isAuthenticated { return .main }
        if !hasSeenIntro { return .intro }
        if guestChosen { return .main }
        return .gate
    }

    /// The one sheet the root can present. A reset link outranks the guest
    /// gate; consolidating into a single `.sheet(item:)` avoids the chained
    /// double-sheet trap.
    private var activeSheet: RootSheet? {
        if let token = services.router.passwordResetToken {
            return .resetPassword(token)
        }
        if services.auth.pendingIntent != nil, phase == .main {
            return .authGate
        }
        return nil
    }

    var body: some View {
        // Read observable state HERE so body tracks it — reads buried inside
        // Binding getters don't register with @Observable, and the sheet
        // would never present.
        let sheet = activeSheet

        ZStack {
            Color.calibre.background.ignoresSafeArea()

            switch phase {
            case .booting:
                BootSplash()
                    .transition(phaseTransition)
            case .intro:
                IntroPager {
                    hasSeenIntro = true
                }
                .transition(phaseTransition)
            case .gate:
                NavigationStack {
                    LoginScreen(context: .gate)
                }
                .transition(phaseTransition)
            case .main:
                MainTabView()
                    .transition(phaseTransition)
            }
        }
        .animation(Motion.easeSlow, value: phase)
        // Applied once at the root — sheets and every tab inherit it via the
        // environment, same as the rest of SwiftUI's environment propagation.
        .preferredColorScheme(appearancePreference.colorScheme)
        .toastHost(services.toasts)
        .sheet(item: Binding(
            get: { sheet },
            set: { newValue in
                guard newValue == nil, let dismissed = sheet else { return }
                switch dismissed {
                case .authGate: services.auth.pendingIntent = nil
                case .resetPassword: services.router.passwordResetToken = nil
                }
            }
        )) { presented in
            switch presented {
            case .authGate:
                AuthGateSheet()
            case .resetPassword(let token):
                NavigationStack {
                    ResetPasswordScreen(token: token)
                }
            }
        }
        .onOpenURL { url in
            services.router.handle(url: url)
        }
        .onAppear {
            // Hand the live coordinator to the UIKit app delegate and let it
            // route pushes into the shell.
            PushAppDelegate.coordinator = services.push
            services.push.attach(router: services.router, alerts: services.alerts)
        }
        // Environment injection stays OUTERMOST so sheet content (presented
        // from a node above the injection point otherwise) inherits it too.
        .environment(services)
        .environment(services.auth)
        .environment(services.router)
        .environment(services.toasts)
        .task {
            await services.auth.bootstrap()
            bootstrapped = true
            if services.auth.isAuthenticated {
                services.push.refreshRegistration()
            }
            services.push.drainPendingRoute()
            #if DEBUG
            // UI-test/screenshot hook: raise the guest gate on launch.
            if ProcessInfo.processInfo.arguments.contains("-openGate") {
                services.auth.require("Sign in to save this watch") { [toasts = services.toasts] in
                    toasts.show(
                        title: "Saved",
                        message: "We'll keep an eye on this one for you.",
                        tone: .success
                    )
                }
            }
            // Screenshot hook: `-selectTab home|discover|sell|activity|you`
            // jumps straight to a tab without scripted touch input.
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-selectTab"),
               ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                switch ProcessInfo.processInfo.arguments[index + 1] {
                case "home": services.router.selectedTab = .home
                case "discover": services.router.selectedTab = .discover
                case "sell": services.router.selectedTab = .sell
                case "activity": services.router.selectedTab = .activity
                case "you": services.router.selectedTab = .you
                default: break
                }
            }
            #endif
        }
    }

    /// Opacity plus a 0.98 scale breath; plain crossfade under Reduce Motion.
    private var phaseTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }
}

/// Everything the root can present modally, as one identity.
private enum RootSheet: Identifiable, Equatable {
    case authGate
    case resetPassword(String)

    var id: String {
        switch self {
        case .authGate: "auth-gate"
        case .resetPassword(let token): "reset-\(token)"
        }
    }
}

/// Shown only for the breath it takes `bootstrap()` to restore a session.
private struct BootSplash: View {
    var body: some View {
        CalibreWordmark(size: 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.calibre.background)
    }
}

/// One place that wires configuration → session → client → stores.
@MainActor
@Observable
final class AppServices {
    let auth: AuthSession
    let client: APIClient
    let catalog: CatalogStore
    let commerce: CommerceStore
    let seller: SellerStore
    let account: AccountStore
    let support: SupportStore
    let signals: LocalSignals
    let alerts = AlertsInbox()
    let router = AppRouter()
    let toasts = ToastCenter()
    let push: PushCoordinator

    init() {
        let configuration = APIConfiguration.fromInfoPlist()
        let auth = AuthSession(configuration: configuration)
        let client = APIClient(configuration: configuration, auth: auth)
        self.auth = auth
        self.client = client
        self.catalog = CatalogStore(client: client)
        self.commerce = CommerceStore(client: client)
        self.seller = SellerStore(client: client)
        let account = AccountStore(client: client)
        self.account = account
        self.support = SupportStore(client: client)
        self.signals = LocalSignals()
        self.push = PushCoordinator(account: account)

        // A cleared session (manual sign-out, a rejected refresh token, or a
        // failed bootstrap validation) must not leave the previous account's
        // cart/watchlist/addresses cached — and an in-flight request from
        // that account must not repopulate them afterward. `CommerceStore`
        // enforces the latter itself; this just triggers it at the one real
        // moment a session actually ends, store-level rather than tied to
        // whichever view happens to be on screen.
        let commerce = self.commerce
        auth.onSessionCleared = { [weak commerce] in
            commerce?.reset()
        }
    }
}
