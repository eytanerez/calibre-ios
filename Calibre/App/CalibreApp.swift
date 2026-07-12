import CalibreDesign
import CalibreKit
import SwiftUI

@main
struct CalibreApp: App {
    init() {
        CalibreFonts.register()
        #if DEBUG
        // UI-test hook: wipe onboarding state so a launch starts at the
        // intro. (Argument-domain defaults can't work here — they shadow
        // the app's own writes, freezing the phase machine.)
        if ProcessInfo.processInfo.arguments.contains("-resetAppState") {
            UserDefaults.standard.removeObject(forKey: "hasSeenIntro")
            UserDefaults.standard.removeObject(forKey: "guestChosen")
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
        // Environment injection stays OUTERMOST so sheet content (presented
        // from a node above the injection point otherwise) inherits it too.
        .environment(services)
        .environment(services.auth)
        .environment(services.router)
        .environment(services.toasts)
        .task {
            await services.auth.bootstrap()
            bootstrapped = true
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
    let signals: LocalSignals
    let router = AppRouter()
    let toasts = ToastCenter()

    init() {
        let configuration = APIConfiguration.fromInfoPlist()
        let auth = AuthSession(configuration: configuration)
        let client = APIClient(configuration: configuration, auth: auth)
        self.auth = auth
        self.client = client
        self.catalog = CatalogStore(client: client)
        self.commerce = CommerceStore(client: client)
        self.seller = SellerStore(client: client)
        self.signals = LocalSignals()
    }
}
