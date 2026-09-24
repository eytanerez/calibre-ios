import RewoundDesign
import RewoundKit
import SwiftUI

/// The Sell tab root. Guests get the warm explainer with a sign-in gate;
/// signed-in members see the seller dashboard, or the onboarding gate where
/// there is nothing yet for the onboarding to be covering.
struct SellScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    private enum Phase: Equatable {
        case loading
        case guest
        case gate
        case dashboard
        case failed(String)
    }

    @State private var sell: SellSession?
    @State private var phase: Phase = .loading
    @State private var retryToken = 0

    var body: some View {
        Group {
            if let sell {
                content
                    .environment(sell)
            } else {
                Color.rewound.background
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewoundPageBackground()
        .navigationTitle("Sell")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(session.isAuthenticated)-\(retryToken)") {
            // The session is built here rather than in an `onAppear` on the
            // placeholder because `reload()` reads through it: the setup gate
            // below asks the seller-ops store whether this seller has sales,
            // and a session that had not been created yet would have made that
            // question unanswerable exactly when it is being asked.
            if sell == nil {
                sell = SellSession(services: services)
            }
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
            case .loading:
                gateSkeleton
            case .guest:
                SellGateScreen(mode: .guest)
            case .gate:
                SellGateScreen(mode: .onboarding(onReadinessChange: { readiness in
                    withAnimation(Motion.easeMedium) {
                        if readiness.canAccessDashboard { phase = .dashboard }
                    }
                }))
            case .dashboard:
                SellerDashboardScreen()
            case .failed(let message):
                EmptyState(
                    icon: "wifi.slash",
                    title: "We couldn't reach your storefront",
                    message: message,
                    actionTitle: "Try again",
                    retry: {
                        // Back to the skeleton at once, which is the visible
                        // reaction; the `.task(id:)` keyed on the token loads.
                        phase = .loading
                        retryToken += 1
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload() async {
        guard session.isAuthenticated else {
            phase = .guest
            return
        }
        do {
            let readiness = try await services.seller.loadReadiness()
            // Written out rather than as `canAccessDashboard || await …` so the
            // probe below is only made when the answer is still open — a
            // seller who can already reach their shop is not made to wait on
            // two more requests to be shown it.
            let openDashboard: Bool
            if readiness.canAccessDashboard {
                openDashboard = true
            } else {
                openDashboard = await hasWorkToProtect()
            }
            withAnimation(Motion.easeMedium) {
                phase = openDashboard ? .dashboard : .gate
            }
        } catch {
            // A transient readiness hiccup shouldn't blank an already-showing
            // dashboard.
            if phase != .dashboard {
                phase = .failed(sellErrorMessage(error))
            }
        }
    }

    /// Whether there is a shop underneath the onboarding worth keeping on
    /// screen.
    ///
    /// Setup-blocked and empty are different facts, and only together do they
    /// make the onboarding the whole page. A seller with nothing yet has
    /// nothing it could be covering. A seller who already has inventory or a
    /// sale — setup went stale, Stripe reopened a requirement — must still
    /// reach their listings, offers, sales and storefront; replacing all of it
    /// with "Start selling on Rewound" is what reads as having lost the
    /// account. Listing stays blocked either way; that is the readiness
    /// payload's call, not this one's, and the dashboard says so at the top.
    ///
    /// A read that failed is "unknown", not "nothing exists" — so only a pair
    /// of successful, empty reads collapses the tab. Anything else falls
    /// through to the dashboard, which is the safe default this screen had
    /// before the gate was narrowed.
    private func hasWorkToProtect() async -> Bool {
        guard let sell else { return true }
        async let listingsRead = try? services.seller.loadMyListings()
        // The same page size the dashboard loads, so this read is the one it
        // would have made rather than a smaller one that replaces its list.
        async let salesRead = try? sell.ops.loadSales(pageSize: 30)
        let (listings, sales) = await (listingsRead, salesRead)
        guard let listings, let sales else { return true }
        return !listings.isEmpty || !sales.results.isEmpty
    }

    /// The gate's shape, shimmering while readiness loads.
    private var gateSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Rectangle().frame(width: 240, height: 28).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 60).shimmer()
            HStack(spacing: Space.m) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle().frame(maxWidth: .infinity).frame(height: 110).shimmer()
                }
            }
            Rectangle().frame(maxWidth: .infinity).frame(height: 48).shimmer()
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xl)
    }
}
