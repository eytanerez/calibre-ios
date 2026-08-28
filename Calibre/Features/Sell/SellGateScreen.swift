import CalibreDesign
import CalibreKit
import SwiftUI

/// "Start selling on Calibre" — the Sell tab root until Connect payouts are
/// ready. Guests see the same story with a sign-in gate on the CTA.
///
/// A signed-in seller sees their setup instead of the pitch: two steps,
/// payouts then the card, with step one rendering whichever of the backend's
/// six states they are actually in (`ConnectSetupStatus`). Nothing here traps
/// anyone — the tab bar stays put, every sheet dismisses, and the card step
/// can be taken before or after payouts.
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
                pitch

                switch mode {
                case .guest:
                    storyRow
                    guestCTA
                case .onboarding:
                    setupSection
                }

                if showWebFallback {
                    CalloutBand(
                        icon: "safari",
                        message: "Finish setting up payouts on the web — your progress is saved."
                    )
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

    // MARK: - The pitch

    private var pitch: some View {
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

    // MARK: - The guest story

    /// How selling works, for someone who hasn't signed in. A member sees
    /// their own two steps instead — the pitch has already been made to them.
    private var storyRow: some View {
        HStack(alignment: .top, spacing: Space.m) {
            gateStep(icon: "building.columns", title: "Payouts with Stripe", caption: "Verify your details once")
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

    private var guestCTA: some View {
        VStack(spacing: Space.m) {
            Button {
                session.require("Sign in to start selling on Calibre") {}
            } label: {
                Text("Set up payouts")
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))

            payoutDisclosures
        }
    }

    private var payoutDisclosures: some View {
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

    // MARK: - The seller's own two steps

    @ViewBuilder
    private var setupSection: some View {
        // `SellScreen` loads readiness before it shows this mode, so there is
        // no state here to invent one for. A missing payload is a load still
        // in flight, and a shimmer says that better than a made-up step would.
        if let connect = services.seller.readiness?.connect {
            let step = connect.payoutStep
            VStack(alignment: .leading, spacing: Space.l) {
                Eyebrow("Setting up your shop")

                payoutStepCard(step)
                cardStepCard(payoutsComplete: step.isComplete)

                // A rejected account is a dead end, and a promise about payout
                // timing on top of it would read as a suggestion to try again.
                if step.status != .rejected {
                    payoutDisclosures
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Space.l) {
                Rectangle().frame(maxWidth: .infinity).frame(height: 150).shimmer()
                Rectangle().frame(maxWidth: .infinity).frame(height: 96).shimmer()
            }
        }
    }

    // MARK: Step 1 — payouts

    private func payoutStepCard(_ step: PayoutSetupStep) -> some View {
        SetupStepCard(
            number: 1,
            of: 2,
            name: "Payouts with Stripe",
            state: step.isComplete ? .done : (step.tone == .attention ? .attention : .current)
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                if let title = step.title {
                    Text(title)
                        .font(CalibreType.bodySemiBold)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(step.body)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if let itemsTitle = step.itemsTitle {
                    Text(itemsTitle)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !step.items.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(step.items) { item in
                            requirementRow(item, checking: step.status == .underReview)
                        }
                    }
                }

                // Never an empty checklist: a cached read remembers that
                // something was outstanding, not what it was called.
                if let withheld = step.itemsWithheldNote {
                    Text(withheld)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let upcoming = step.upcomingNote {
                    Text(upcoming)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                payoutAction(step.action)

                if let footnote = step.footnote {
                    Text(footnote)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func requirementRow(_ item: ConnectRequirementItem, checking: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: checking ? "hourglass" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
                .padding(.top, 3)
                .accessibilityHidden(true)
            Text(item.label)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func payoutAction(_ action: PayoutSetupStep.Action) -> some View {
        switch action {
        case .collectSSN(let title):
            Button {
                beginOnboarding()
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .openForm(let title):
            Button {
                resumeOnboarding()
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .refresh(let title):
            Button {
                Task { await refreshReadiness() }
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .contactSupport(let title):
            // No form and no retry. Stripe's answer here is terminal, and a
            // button that mints another session would only walk the seller
            // back into an account that cannot be approved.
            NavigationLink {
                SupportChatScreen(seed: payoutRejectedSupportMessage)
            } label: {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))

        case .none:
            EmptyView()
        }
    }

    // MARK: Step 2 — the card on file

    private func cardStepCard(payoutsComplete: Bool) -> some View {
        let onFile = sellerCard?.present == true && sellerCard?.needsAttention == false
        return SetupStepCard(
            number: 2,
            of: 2,
            name: "Card on file",
            state: onFile ? .done : (payoutsComplete ? .current : .waiting)
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(cardStepBody)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if !onFile {
                    Button {
                        showCardStep = true
                    } label: {
                        Text(sellerCard?.present == true ? "Replace your card" : "Add your card")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.calibre(payoutsComplete ? .primary : .secondary, fullWidth: true))
                }
            }
        }
    }

    private var cardStepBody: String {
        guard let sellerCard, sellerCard.present else {
            return "Sellers keep a credit card on file — credit only, no debit or prepaid. It is what an authentication charge would land on, and you can add it before or after payouts."
        }
        if sellerCard.valid == false {
            return "\(sellerCard.displayName) can't be charged any more. Replacing it puts your listings back on the market."
        }
        if sellerCard.expiringSoon == true {
            return "\(sellerCard.displayName) expires soon. Replacing it now keeps your listings live."
        }
        return "\(sellerCard.displayName) is on file. An ordinary sale never touches it."
    }

    // MARK: - Flow

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

    /// The first onboarding session — server truth, not a client guess. (The
    /// seam also latches it, covering the other entries into onboarding.)
    private func beginOnboarding() {
        showWebFallback = false
        Analytics.sellerStarted()
        showSSNStep = true
    }

    /// With an existing Connect account the backend ignores the SSN field,
    /// so we can mint a session directly.
    private func resumeOnboarding() {
        showWebFallback = false
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

// MARK: - One numbered step

/// A step in seller setup, said as "Step 1 of 2" so neither half looks like
/// the whole job. The marker carries the state; the content is the step's own.
private struct SetupStepCard<Content: View>: View {
    enum State {
        /// Finished.
        case done
        /// The step to take now.
        case current
        /// Reachable, but not what we're asking for yet.
        case waiting
        /// Something is wrong with this step.
        case attention
    }

    let number: Int
    let of: Int
    let name: String
    let state: State
    @ViewBuilder var content: Content

    var body: some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    marker
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step \(number) of \(of)")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Text(name)
                            .font(CalibreType.bodyMedium)
                            .foregroundStyle(Color.calibre.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Space.s)
                }

                content
            }
            .padding(Space.l)
        }
        .opacity(state == .waiting ? 0.72 : 1)
    }

    private var marker: some View {
        Group {
            switch state {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.calibre.success)
            case .attention:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.calibre.destructive)
            case .current, .waiting:
                Text("\(number)")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(
                        state == .current ? Color.calibre.accentForeground : Color.calibre.mutedForeground
                    )
            }
        }
        .frame(width: 32, height: 32)
        .background(
            Color.calibre.accent.opacity(state == .waiting ? 0.5 : 1),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .accessibilityHidden(true)
    }
}

/// Identity for the fullScreenCover pairing an account session with the key.
private struct ConnectPresentation: Identifiable {
    let session: ConnectAccountSession
    let key: String
    var id: String { session.clientSecret }
}
