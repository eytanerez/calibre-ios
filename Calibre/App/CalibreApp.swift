import CalibreDesign
import CalibreKit
import SwiftUI

@main
struct CalibreApp: App {
    init() {
        CalibreFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Temporary P0/P1 root — design-system Gallery plus the CalibreKit API smoke
/// screen, until the real tab shell lands in P2.
struct RootView: View {
    private enum Tab: Hashable {
        case gallery, api
    }

    @State private var services = AppServices()
    // "-openAPITab" launch argument jumps straight to the API console —
    // used by automated smoke checks.
    @State private var selectedTab: Tab =
        ProcessInfo.processInfo.arguments.contains("-openAPITab") ? .api : .gallery

    var body: some View {
        TabView(selection: $selectedTab) {
            GalleryScreen()
                .tabItem {
                    Label("Gallery", systemImage: "paintpalette")
                }
                .tag(Tab.gallery)
            DebugConsoleView(catalog: services.catalog)
                .tabItem {
                    Label("API", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(Tab.api)
        }
        .task {
            await services.auth.bootstrap()
        }
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
