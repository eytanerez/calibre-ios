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
    @State private var showCardStep = false
    @State private var sellerCard: SellerCardState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Start selling on Calibre")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                    Text("List your watch in minutes. Every sale is authenticated before it reaches the buyer, we handle the buyer for you, and your money goes straight to your bank account.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(keepClaim)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Free to list. No monthly fees. No buyer premium.")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    NavigationLink {
                        FeeBreakdownScreen()
                    } label: {
                        Label("See the fee breakdown", systemImage: "percent")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.primary)
                    }
                    .buttonStyle(PressableStyle())
                }

                stepsRow

                if inProgress {
                    CalloutBand(
                        icon: "hourglass",
                        title: "Payouts are almost set up",
                        message: "A detail or two is still being verified. Pick up where you left off whenever you're ready."
                    )
                }

                if let sellerCard, sellerCard.needsAttention {
                    Button {
                        showCardStep = true
                    } label: {
                        CalloutBand(
                            icon: "creditcard",
                            title: sellerCard.present ? "Your card on file needs attention" : "Add your card on file",
                            message: "Sellers keep a credit card on file — credit only, no debit or prepaid. It is what an authentication charge would land on, and you can add it before or after payouts."
                        )
                    }
                    .buttonStyle(PressableStyle())
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

                    VStack(spacing: Space.s) {
                        Text("You verify your details once with our payments partner. Calibre never sees your banking information.")
                        // Disclosed during onboarding, not after the first sale.
                        Text("Your first payout may take 7 to 14 days while your account is established. After that, payouts arrive on the normal schedule.")
                    }
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
                        title: "Payout setup couldn't load",
                        message: message,
                        tone: .error
                    )
                }
            )
        }
        .sheet(isPresented: $showCardStep) {
            SellerCardScreen { saved in
                sellerCard = saved
            }
        }
        .task(id: accountSession?.clientSecret) {
            // The Connect SDK needs the publishable key before it can present.
            guard accountSession != nil, stripeKey == nil else { return }
            do {
                stripeKey = try await sell.stripeKey()
            } catch {
                accountSession = nil
                showWebFallback = true
                toasts.show(
                    title: "We couldn't reach payout setup",
                    message: sellErrorMessage(error),
                    tone: .error
                )
            }
        }
        .task {
            // The card gates listing, not payouts, so its absence is shown as
            // a step to take rather than as a blocked screen.
            if case .onboarding = mode {
                sellerCard = try? await services.seller.sellerCard()
            }
        }
    }

    /// "You keep 94%…" — derived from the server's own rates, and only
    /// falling back to the canonical figures when the config hasn't landed.
    /// No minimum here: this is a fee headline, not a payout figure.
    private var keepClaim: String {
        let config = services.config.config
        let member = config?.sellerFeePercentMember.map { keepPercentText($0.value) } ?? "94"
        let dealer = config?.sellerFeePercentDealer.map { keepPercentText($0.value) } ?? "96"
        return "Private sellers keep \(member)%. Verified dealers keep \(dealer)%."
    }

    /// 100 minus the server's rate, rendered without trailing zeros. This is
    /// presentation of a server figure, not a fee computed on device.
    private func keepPercentText(_ percent: Decimal) -> String {
        let keep = Decimal(100) - percent
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: keep as NSDecimalNumber) ?? "\(keep)"
    }

    // MARK: - Steps

    private var stepsRow: some View {
        HStack(alignment: .top, spacing: Space.m) {
            gateStep(icon: "building.columns", title: "Connect payouts", caption: "Verify your details once")
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
                // The payouts account exists — skip straight to verification.
                resumeOnboarding()
            } else {
                // No Connect account yet, so this is the first onboarding
                // session — server truth, not a client guess. (The seam also
                // latches it, covering the other entries into onboarding.)
                Analytics.sellerStarted()
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
                // Listing readiness can fail on the card rather than on
                // payouts — route to the step that actually unblocks them.
                if (error as? APIError)?.serverCode == "seller_card_required" {
                    showCardStep = true
                    return
                }
                toasts.show(
                    title: "We couldn't start payout setup",
                    message: sellErrorMessage(error),
                    tone: .error
                )
            }
        }
    }

    private func refreshReadiness() async {
        refreshingReadiness = true
        defer { refreshingReadiness = false }
        do {
            let readiness = try await services.seller.loadReadiness()
            sellerCard = try? await services.seller.sellerCard()
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
