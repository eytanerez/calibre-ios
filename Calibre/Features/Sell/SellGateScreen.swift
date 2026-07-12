import CalibreDesign
import CalibreKit
import SwiftUI

/// "Start selling on Calibre" — the Sell tab root until Connect payouts are
/// ready. Guests see the same story with a sign-in gate on the CTA.
struct SellGateScreen: View {
    enum Mode {
        case guest
        case onboarding(onReadinessChange: (SellerReadiness) -> Void)
    }

    let mode: Mode

    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts

    @State private var showSSNStep = false
    @State private var accountSession: ConnectAccountSession?
    @State private var stripeKey: String?
    @State private var showWebFallback = false
    @State private var refreshingReadiness = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Start selling on Calibre")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("List your watch in minutes. We authenticate every sale in-house, handle the buyer, and pay you out through Stripe.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Private sellers keep 92%. Dealers keep 95%.")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                }

                stepsRow

                if inProgress {
                    CalloutBand(
                        icon: "hourglass",
                        title: "Payouts are almost set up",
                        message: "Stripe is still verifying a detail or two. Pick up where you left off whenever you're ready."
                    )
                }

                if showWebFallback {
                    CalloutBand(
                        icon: "safari",
                        message: "Finish setting up payouts on the web — your progress is saved."
                    )
                }

                VStack(spacing: Space.m) {
                    Button {
                        beginOnboarding()
                    } label: {
                        if refreshingReadiness {
                            ProgressView().tint(Color.calibre.primaryForeground)
                        } else {
                            Text(inProgress ? "Continue setting up payouts" : "Set up payouts")
                        }
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(refreshingReadiness)

                    Text("Powered by Stripe. Your details stay between you and Stripe — Calibre never sees your banking information.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .sheet(isPresented: $showSSNStep) {
            SSNStepSheet { session in
                accountSession = session
            }
        }
        .fullScreenCover(item: connectItem) { item in
            ConnectOnboardingScreen(
                clientSecret: item.session.clientSecret,
                publishableKey: item.key,
                onExit: {
                    accountSession = nil
                    Task { await refreshReadiness() }
                },
                onLoadFailure: { message in
                    accountSession = nil
                    showWebFallback = true
                    toasts.show(
                        title: "Stripe couldn't load onboarding",
                        message: message,
                        tone: .error
                    )
                }
            )
        }
        .task(id: accountSession?.clientSecret) {
            // The Connect SDK needs the publishable key before it can present.
            guard accountSession != nil, stripeKey == nil else { return }
            do {
                stripeKey = try await sell.stripeKey()
            } catch {
                accountSession = nil
                showWebFallback = true
                toasts.show(title: "Stripe isn't reachable right now", message: sellErrorMessage(error), tone: .error)
            }
        }
    }

    // MARK: - Steps

    private var stepsRow: some View {
        HStack(alignment: .top, spacing: Space.m) {
            gateStep(icon: "building.columns", title: "Connect payouts", caption: "Verify once with Stripe")
            stepArrow
            gateStep(icon: "camera", title: "List your watch", caption: "Six photos, one calm flow")
            stepArrow
            gateStep(icon: "shippingbox", title: "Ship when it sells", caption: "Prepaid label to our vault")
        }
    }

    private var stepArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.calibre.mutedForeground)
            .padding(.top, 14)
            .accessibilityHidden(true)
    }

    private func gateStep(icon: String, title: String, caption: String) -> some View {
        VStack(spacing: Space.s) {
            IconTile(systemName: icon)
            Text(title)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.foreground)
            Text(caption)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Flow

    /// Onboarding was started earlier (a Connect account exists) but isn't
    /// complete yet.
    private var inProgress: Bool {
        services.seller.readiness?.connect.accountId != nil
    }

    private var connectItem: Binding<ConnectPresentation?> {
        Binding(
            get: {
                guard let accountSession, let stripeKey else { return nil }
                return ConnectPresentation(session: accountSession, key: stripeKey)
            },
            set: { newValue in
                if newValue == nil {
                    accountSession = nil
                }
            }
        )
    }

    private func beginOnboarding() {
        switch mode {
        case .guest:
            session.require("Sign in to start selling on Calibre") {}
        case .onboarding:
            showWebFallback = false
            if inProgress {
                // The Connect account exists — skip straight to Stripe.
                resumeOnboarding()
            } else {
                showSSNStep = true
            }
        }
    }

    /// With an existing Connect account the backend ignores the SSN field,
    /// so we can mint a session directly.
    private func resumeOnboarding() {
        refreshingReadiness = true
        Task {
            defer { refreshingReadiness = false }
            do {
                accountSession = try await sell.ops.connectAccountSession(ssn: "")
            } catch {
                toasts.show(title: "Couldn't reach Stripe", message: sellErrorMessage(error), tone: .error)
            }
        }
    }

    private func refreshReadiness() async {
        refreshingReadiness = true
        defer { refreshingReadiness = false }
        do {
            let readiness = try await services.seller.loadReadiness()
            if case .onboarding(let onReadinessChange) = mode {
                onReadinessChange(readiness)
            }
            if readiness.canList {
                Haptics.shared.play(.success)
                toasts.show(
                    title: "Payouts are ready",
                    message: "Your shop is open — list your first watch whenever you like.",
                    tone: .success
                )
            }
        } catch {
            toasts.show(title: "Couldn't refresh your status", message: sellErrorMessage(error), tone: .error)
        }
    }
}

/// Identity for the fullScreenCover pairing an account session with the key.
private struct ConnectPresentation: Identifiable {
    let session: ConnectAccountSession
    let key: String
    var id: String { session.clientSecret }
}
