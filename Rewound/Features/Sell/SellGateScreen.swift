import RewoundDesign
import RewoundKit
import SwiftUI

/// "Start selling on Rewound" — the Sell tab root until Connect payouts are
/// ready. Guests see the same story with a sign-in gate on the CTA.
///
/// A signed-in seller sees their setup instead of the pitch: payouts, then the
/// card, with the payouts step rendering whichever of the backend's states they
/// are actually in (`ConnectSetupStatus`). The card is only drawn where it is
/// still something to do — see `setupSection`. Nothing here traps anyone: the
/// tab bar stays put, every sheet dismisses, and the card step can be taken
/// before or after payouts.
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
    @Environment(\.openURL) private var openURL

    @State private var accountSession: ConnectAccountSession?
    @State private var stripeKey: String?
    @State private var showWebFallback = false
    @State private var refreshingReadiness = false
    @State private var showCardStep = false
    @State private var sellerCard: SellerCardState?
    /// How far setup has got, held at its peak so the crown never winds back.
    @State private var setupProgress = SellerSetupProgress()

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
                        message: "Open Stripe's secure website to finish setup — your progress is saved.",
                        action: { Task { await openHostedOnboarding() } }
                    )
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        // `initial`, so a seller arriving with a step already finished sees
        // the crown standing at that fact rather than winding for old news —
        // the announcement is keyed to the count, and the first claim of a
        // key is the one that plays.
        .onChange(of: setupStepsDone, initial: true) { _, done in
            if let done { setupProgress.record(stepsDone: done) }
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
            Text("Start selling on Rewound")
                .font(RewoundType.title)
                .foregroundStyle(Color.rewound.foreground)
            Text("List your watch in minutes. Every sale is authenticated before it reaches the buyer, we handle the buyer for you, and your money goes straight to your bank account.")
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text(keepClaim)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Free to list. No monthly fees. No buyer premium.")
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                FeeBreakdownScreen()
            } label: {
                Label("See the fee breakdown", systemImage: "percent")
                    .font(RewoundType.label)
                    .foregroundStyle(Color.rewound.primary)
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

    /// How selling works, for someone who hasn't signed in. A member sees their
    /// own setup instead — the pitch has already been made to them.
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
            .foregroundStyle(Color.rewound.mutedForeground)
            .padding(.top, 14)
            .accessibilityHidden(true)
    }

    private func gateStep(icon: String, title: String, caption: String) -> some View {
        VStack(spacing: Space.s) {
            IconTile(systemName: icon)
            Text(title)
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.foreground)
            Text(caption)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var guestCTA: some View {
        VStack(spacing: Space.m) {
            Button {
                session.require("Sign in to start selling on Rewound") {}
            } label: {
                Text("Set up payouts")
            }
            .buttonStyle(.rewound(.primary, fullWidth: true))

            payoutDisclosures
        }
    }

    private var payoutDisclosures: some View {
        VStack(spacing: Space.s) {
            Text("You verify your details once with our payments partner. Rewound never sees your banking information.")
            // Disclosed during onboarding, not after the first sale.
            Text("Your first payout may take about two weeks while your account is established. After that, payouts arrive on the normal schedule.")
        }
        .font(RewoundType.caption)
        .foregroundStyle(Color.rewound.mutedForeground)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The seller's own setup

    @ViewBuilder
    private var setupSection: some View {
        // `SellScreen` loads readiness before it shows this mode, so there is
        // no state here to invent one for. A missing payload is a load still
        // in flight, and a shimmer says that better than a made-up step would.
        if let connect = services.seller.readiness?.connect {
            let step = connect.payoutStep
            // Two reasons the card is not drawn. A rejected account can never
            // list, so the card is not this screen's business in any card
            // state. And a card already on file while payouts are the thing
            // actually outstanding is a finished step, not a step — showing it
            // is what told a seller arriving from the dealer application's
            // seller-setup link that there were two things to do when there
            // was one. `cardStepIsRedundant` keeps the expiring-card warning
            // out of that rule.
            let showsCard = step.status != .rejected
                && !SellerSetupSteps.cardStepIsRedundant(card: sellerCard, payoutsComplete: step.isComplete)
            let stepsShown = showsCard ? 2 : 1
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .center, spacing: Space.m) {
                    Eyebrow("Setting up your storefront")
                    Spacer(minLength: Space.s)
                    // A step finished: the crown winds a click past its
                    // detent and catches. Keyed to the peak count, so a
                    // refetch that briefly reports less neither unwinds it
                    // nor takes it away, and announced once per session per
                    // count. Nothing is drawn until something has finished —
                    // a wound crown beside an untouched setup would be a
                    // fact nobody established. The cards beneath say which
                    // step, in words; the mark has no label.
                    if let windKey = setupProgress.markKey {
                        RewoundMark.crown(size: 36, trigger: windKey)
                            .markAnnounces(windKey)
                    }
                }

                payoutStepCard(step, of: stepsShown)
                if showsCard {
                    cardStepCard(payoutsComplete: step.isComplete)
                }

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

    /// How many of setup's steps stand finished on the readiness on hand, or
    /// nil while readiness has not loaded — a load in flight is not zero
    /// steps done. The count is `SellerSetupSteps.stepsDone`, which counts a
    /// step only when it is drawn as finished: payouts on the server's own
    /// `isComplete`, the card as the finished card beside them — and not the
    /// card `cardStepIsRedundant` folds away, which the web does not count
    /// either, so both platforms wind the crown on the same key.
    private var setupStepsDone: Int? {
        guard let step = services.seller.readiness?.connect.payoutStep else { return nil }
        return SellerSetupSteps.stepsDone(
            card: sellerCard,
            payoutsComplete: step.isComplete,
            payoutsRejected: step.status == .rejected
        )
    }

    // MARK: Step 1 — payouts

    private func payoutStepCard(_ step: PayoutSetupStep, of stepsShown: Int) -> some View {
        SetupStepCard(
            number: 1,
            of: stepsShown,
            name: "Payouts with Stripe",
            state: step.isComplete ? .done : (step.tone == .attention ? .attention : .current)
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                if let title = step.title {
                    Text(title)
                        .font(RewoundType.bodySemiBold)
                        .foregroundStyle(Color.rewound.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(step.body)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if let itemsTitle = step.itemsTitle {
                    Text(itemsTitle)
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.foreground)
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
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let upcoming = step.upcomingNote {
                    Text(upcoming)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                payoutAction(step.action)

                if let footnote = step.footnote {
                    Text(footnote)
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func requirementRow(_ item: ConnectRequirementItem, checking: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: checking ? "hourglass" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.rewound.mutedForeground)
                .padding(.top, 3)
                .accessibilityHidden(true)
            Text(item.label)
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.foreground)
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
            .buttonStyle(.rewound(.primary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .openForm(let title):
            Button {
                resumeOnboarding()
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.rewound(.primary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .refresh(let title):
            Button {
                Task { await refreshReadiness() }
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.rewound(.secondary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .contactSupport(let title):
            // No form and no retry. Stripe's answer here is terminal, and a
            // button that mints another session would only walk the seller
            // back into an account that cannot be approved.
            NavigationLink {
                SupportChatScreen(seed: payoutRejectedSupportMessage)
                    .routeStackNode()
            } label: {
                Text(title).frame(maxWidth: .infinity)
            }
            .buttonStyle(.rewound(.primary, fullWidth: true))

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
            state: cardStepState(payoutsComplete: payoutsComplete)
        ) {
            VStack(alignment: .leading, spacing: Space.m) {
                // A card already on file is shown rather than described. The
                // step is finished, and the seller should see the thing they
                // put there instead of being asked for it a second time.
                if let card = sellerCard, card.present {
                    GuaranteeCard(
                        brand: GuaranteeCard.Brand(stripeBrand: card.brand),
                        last4: card.last4,
                        expiry: card.expiryLabel,
                        status: cardStepStatus(card),
                        size: .compact
                    )
                }

                Text(cardStepBody)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if onFile {
                    // Still reachable, but as an option rather than an ask: a
                    // finished step with a full-width CTA under it reads as
                    // unfinished no matter what the marker says.
                    Button {
                        showCardStep = true
                    } label: {
                        Text("Replace card")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.primary)
                            .frame(minHeight: Space.touchTarget, alignment: .leading)
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    Button {
                        showCardStep = true
                    } label: {
                        Text(sellerCard?.present == true ? "Replace your card" : "Add your card")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rewound(payoutsComplete ? .primary : .secondary, fullWidth: true))
                }
            }
        }
    }

    /// A card that is on file and working is a finished step. A lapsed one is
    /// the only card state that gets the alarm marker: an expiring card is
    /// work to do, not something already broken.
    private func cardStepState(payoutsComplete: Bool) -> SetupStepState {
        guard let sellerCard, sellerCard.present else {
            return payoutsComplete ? .current : .waiting
        }
        if sellerCard.valid == false { return .attention }
        if sellerCard.expiringSoon == true { return .current }
        return .done
    }

    private func cardStepStatus(_ card: SellerCardState) -> GuaranteeCard.Status {
        if card.valid == false { return .lapsed }
        if card.expiringSoon == true { return .expiringSoon }
        return .onFile
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
    ///
    /// There was an SSN step here, gating the very first Connect account. The
    /// backend dropped that field along with `users.ssn_hash` (contracts §2:
    /// identity now runs on card/bank fingerprints and Stripe's own KYC) — so
    /// the first-time and returning-seller paths both just mint a session.
    private func beginOnboarding() {
        Analytics.sellerStarted()
        resumeOnboarding()
    }

    private func openHostedOnboarding() async {
        do {
            openURL(try await sell.ops.connectAccountLink())
        } catch {
            toasts.show(
                title: "We couldn't open Stripe",
                message: sellErrorMessage(error),
                tone: .error
            )
        }
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
                    message: "Your storefront is open — list your first watch whenever you like.",
                    tone: .success
                )
            }
        } catch {
            toasts.show(title: "Couldn't refresh your status", message: sellErrorMessage(error), tone: .error)
        }
    }
}

// MARK: - One numbered step

/// Where a setup step stands. Outside the card because the card is generic
/// over its content, and a step's state is worth naming in a function's return
/// type without dragging that generic along.
private enum SetupStepState {
    /// Finished.
    case done
    /// The step to take now.
    case current
    /// Reachable, but not what we're asking for yet.
    case waiting
    /// Something is wrong with this step.
    case attention
}

/// A step in seller setup, said as "Step 1 of 2" while there are two, so
/// neither half looks like the whole job. Where only one is drawn the counter
/// is dropped: "Step 1 of 1" is a stepper for a job with no steps in it, and it
/// leaves a seller looking for the one that is missing. The marker carries the
/// state; the content is the step’s own.
private struct SetupStepCard<Content: View>: View {
    let number: Int
    let of: Int
    let name: String
    let state: SetupStepState
    @ViewBuilder var content: Content

    var body: some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    marker
                    VStack(alignment: .leading, spacing: 2) {
                        if of > 1 {
                            Text("Step \(number) of \(of)")
                                .font(RewoundType.caption)
                                .foregroundStyle(Color.rewound.mutedForeground)
                        }
                        Text(name)
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
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
                    .foregroundStyle(Color.rewound.success)
            case .attention:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rewound.destructive)
            case .current, .waiting:
                Text("\(number)")
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(
                        state == .current ? Color.rewound.accentForeground : Color.rewound.mutedForeground
                    )
            }
        }
        .frame(width: 32, height: 32)
        .background(
            Color.rewound.accent.opacity(state == .waiting ? 0.5 : 1),
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
