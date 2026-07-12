import CalibreDesign
import CalibreKit
import SwiftUI

/// The Sell tab root. Guests get the warm explainer with a sign-in gate;
/// signed-in members see the onboarding gate until Stripe Connect payouts
/// are ready (`can_list`), then the seller dashboard.
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
                Color.calibre.background
                    .onAppear { sell = SellSession(services: services) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Sell")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(session.isAuthenticated)-\(retryToken)") {
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
                        phase = readiness.canList ? .dashboard : .gate
                    }
                }))
            case .dashboard:
                SellerDashboardScreen()
            case .failed(let message):
                EmptyState(
                    icon: "wifi.slash",
                    title: "We couldn't reach your shop",
                    message: message,
                    actionTitle: "Try again",
                    action: {
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
            withAnimation(Motion.easeMedium) {
                phase = readiness.canList ? .dashboard : .gate
            }
        } catch {
            // A transient readiness hiccup shouldn't blank an already-showing
            // dashboard.
            if phase != .dashboard {
                phase = .failed(sellErrorMessage(error))
            }
        }
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
