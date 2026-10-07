import RewatchDesign
import RewatchKit
import SwiftUI

/// "Start selling on Rewatch" — the Sell tab root until Connect payouts are
/// ready. Guests see the same story with a sign-in gate on the CTA.
///
/// A signed-in seller sees their setup instead of the pitch: payouts, then the
/// card, with the payouts step rendering whichever of the backend's states they
/// are actually in (`ConnectSetupStatus`). The card is only drawn where it is
/// still something to do — see `setupSection` — and is the step to take once
/// payouts need nothing more from the seller. Nothing here traps anyone: the
/// tab bar stays put and every sheet dismisses.
///
/// Setup ends on the dashboard (Eytan, 2026-10-06: "you do the card and
/// straight to dashboard"). The moment the seller's half is done — Stripe has
/// their details and a card is on file — `onFinished` hands them over, even
/// while Stripe is still switching payouts on: the dashboard says that wait at
/// its top. There is no "list your first watch" stop in between.
struct SellGateScreen: View {
    enum Mode {
        case guest
        /// `playsFinish`: whether the save that completes setup plays the
        /// finish before `onFinished`. The Sell tab's gate does; the
        /// dashboard's own setup sheet does not — that seller has a shop.
        case onboarding(playsFinish: Bool = true, onFinished: () -> Void)
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
    /// Whether the card sheet should open straight onto Stripe's card form:
    /// true only when it was opened by a return from Stripe's payout form.
    @State private var cardStepOpensForm = false
    /// The card the card step draws. Held, not assigned: a saved card is
    /// drawn only once readiness has been re-read — see `SellerCardSaveHold`.
    @State private var cardHold = SellerCardSaveHold()
    private var sellerCard: SellerCardState? { cardHold.shown }
    /// The saved card the finish is playing for, while it plays.
    @State private var finishCard: SellerCardState?
    @State private var finishRun = SellerSetupFinishRun()
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
                    Task { await refreshReadiness(backFromStripe: true) }
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
            SellerCardScreen(
                onSaved: { saved in cardSaved(saved) },
                opensFormImmediately: cardStepOpensForm,
                announcesSave: !SellerSetupFinishRule.wouldPlay(
                    enabled: playsFinish,
                    readiness: services.seller.readiness,
                    cardBefore: sellerCard
                )
            )
        }
        // The finish plays over the gate, which stays exactly as it was
        // underneath until the run resolves.
        .overlay {
            if let finishCard {
                SellerSetupFinishView(card: finishCard) {
                    resolveFinish(finishRun.endAnimation())
                }
                .transition(.opacity)
            }
        }
        .onChange(of: showCardStep) { _, showing in
            if !showing { cardStepOpensForm = false }
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
                cardHold.show(try? await services.seller.sellerCard())
            }
        }
    }

    // MARK: - The pitch

    private var pitch: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Start selling on Rewatch")
                .font(RewatchType.title)
                .foregroundStyle(Color.rewatch.foreground)
            Text("List your watch in minutes. Every sale is authenticated before it reaches the buyer, we handle the buyer for you, and your money goes straight to your bank account.")
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text(keepClaim)
                .font(RewatchType.bodyMedium)
                .foregroundStyle(Color.rewatch.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Free to list. No monthly fees. No buyer premium.")
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                FeeBreakdownScreen()
            } label: {
                Label("See the fee breakdown", systemImage: "percent")
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.primary)
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
            gateStep(icon: "shippingbox", title: "Ship when it sells", caption: "Prepaid label to WPB Watch Co in West Palm Beach, Florida")
        }
    }

    private var stepArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.rewatch.mutedForeground)
            .padding(.top, 14)
            .accessibilityHidden(true)
    }

    private func gateStep(icon: String, title: String, caption: String) -> some View {
        VStack(spacing: Space.s) {
            IconTile(systemName: icon)
            Text(title)
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.foreground)
            Text(caption)
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var guestCTA: some View {
        VStack(spacing: Space.m) {
            Button {
                session.require("Sign in to start selling on Rewatch") {}
            } label: {
                Text("Set up payouts")
            }
            .buttonStyle(.rewatch(.primary, fullWidth: true))

            payoutDisclosures
        }
    }

    private var payoutDisclosures: some View {
        VStack(spacing: Space.s) {
            Text("You verify your details once with our payments partner. Rewatch never sees your banking information.")
            // Disclosed during onboarding, not after the first sale.
            Text("Your first payout may take about two weeks while your account is established. After that, payouts arrive on the normal schedule.")
        }
        .font(RewatchType.caption)
        .foregroundStyle(Color.rewatch.mutedForeground)
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
            let payoutsDone = SellerSetupSteps.payoutsNeedNothingFromSeller(step)
            let showsCard = step.status != .rejected
                && !SellerSetupSteps.cardStepIsRedundant(card: sellerCard, payoutsComplete: payoutsDone)
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
                        RewatchMark.crown(size: 36, trigger: windKey)
                            .markAnnounces(windKey)
                    }
                }

                payoutStepCard(step, of: stepsShown)
                if showsCard {
                    cardStepCard(payoutsComplete: payoutsDone)
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
                        .font(RewatchType.bodySemiBold)
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(step.body)
                    .font(RewatchType.body)
                    .foregroundStyle(Color.rewatch.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if let itemsTitle = step.itemsTitle {
                    Text(itemsTitle)
                        .font(RewatchType.label)
                        .foregroundStyle(Color.rewatch.foreground)
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
                        .font(RewatchType.body)
                        .foregroundStyle(Color.rewatch.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let upcoming = step.upcomingNote {
                    Text(upcoming)
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                payoutAction(step.action)

                if let footnote = step.footnote {
                    Text(footnote)
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func requirementRow(_ item: ConnectRequirementItem, checking: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: checking ? "hourglass" : "circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.rewatch.mutedForeground)
                .padding(.top, 3)
                .accessibilityHidden(true)
            Text(item.label)
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.foreground)
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
            .buttonStyle(.rewatch(.primary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .openForm(let title):
            Button {
                resumeOnboarding()
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.rewatch(.primary, fullWidth: true))
            .disabled(refreshingReadiness)

        case .refresh(let title):
            Button {
                Task { await refreshReadiness() }
            } label: {
                BusyLabel(title: title, busy: refreshingReadiness)
            }
            .buttonStyle(.rewatch(.secondary, fullWidth: true))
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
            .buttonStyle(.rewatch(.primary, fullWidth: true))

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
                    .font(RewatchType.body)
                    .foregroundStyle(Color.rewatch.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)

                if !payoutsComplete && sellerCard?.present != true {
                    // One thing at a time: while Stripe still needs the
                    // seller, this step says it is next rather than offering
                    // a second button beside Stripe's.
                    EmptyView()
                } else if onFile {
                    // Still reachable, but as an option rather than an ask: a
                    // finished step with a full-width CTA under it reads as
                    // unfinished no matter what the marker says.
                    Button {
                        showCardStep = true
                    } label: {
                        Text("Replace card")
                            .font(RewatchType.label)
                            .foregroundStyle(Color.rewatch.primary)
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
                    .buttonStyle(.rewatch(payoutsComplete ? .primary : .secondary, fullWidth: true))
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
            return "Sellers keep a credit card on file — credit only, no debit or prepaid. It is what an authentication charge would land on, and it is the last step: once it is on file, your dashboard opens."
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
        // No existing Connect account, so the endpoint requires the explicit
        // create flag (409 "Choose Start with Stripe..." otherwise) — it is a
        // guard against a retried request accidentally minting a second
        // account, not something the SSN step ever carried.
        mintOnboardingSession(createAccount: true)
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
        mintOnboardingSession(createAccount: false)
    }

    private func mintOnboardingSession(createAccount: Bool) {
        showWebFallback = false
        refreshingReadiness = true
        Task {
            defer { refreshingReadiness = false }
            do {
                accountSession = try await sell.ops.connectAccountSession(ssn: "", createAccount: createAccount)
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

    private var playsFinish: Bool {
        if case .onboarding(let plays, _) = mode { return plays }
        return false
    }

    /// The card sheet saved a card.
    ///
    /// It used to be drawn here at once, while readiness still said the card
    /// was owed: for the length of the re-read the card step behind the
    /// closing sheet showed the finished card, and then the screen swapped to
    /// the dashboard — the flash. Now it is held until readiness lands, and
    /// when this card completes setup the finish covers the gate meanwhile.
    private func cardSaved(_ saved: SellerCardState) {
        let plays = SellerSetupFinishRule.playsFinish(
            enabled: playsFinish,
            readiness: services.seller.readiness,
            cardBefore: sellerCard,
            saved: saved
        )
        cardHold.cardSaved(saved)
        if plays {
            Haptics.shared.play(.success)
            finishRun = SellerSetupFinishRun()
            withAnimation(.easeOut(duration: 0.2)) { finishCard = saved }
        }
        Task { await refreshReadiness() }
    }

    /// One outcome of the finish run; only the first resolving one acts.
    private func resolveFinish(_ outcome: SellerSetupFinishRun.Outcome) {
        switch outcome {
        case .wait:
            break
        case .openDashboard:
            if case .onboarding(_, let onFinished) = mode { onFinished() }
        case .returnToGate:
            withAnimation(Motion.easeMedium) { finishCard = nil }
        }
    }

    private func refreshReadiness(backFromStripe: Bool = false) async {
        refreshingReadiness = true
        defer { refreshingReadiness = false }
        do {
            // The card first, then readiness, then both drawn in one change:
            // there is no suspension between readiness landing in the store
            // and the hold releasing the card, so no frame shows one without
            // the other.
            let cardRead = try? await services.seller.sellerCard()
            let readiness = try await services.seller.loadReadiness()
            cardHold.readinessLanded(cardRead: cardRead)
            let finished = SellerSetupSteps.finishedBySeller(readiness, card: sellerCard)
            if finishCard != nil {
                // The finish opens the dashboard, once, when it ends — not
                // this re-read, mid-flourish.
                resolveFinish(finishRun.readinessLanded(finished: finished))
                return
            }
            // Straight to the dashboard once the seller's half is done. No
            // "now list your first watch" stop: the dashboard has its own way
            // to add a listing, and is where a pending Stripe check is said.
            if case .onboarding(_, let onFinished) = mode,
               SellerSetupSteps.finishedBySeller(readiness, card: sellerCard) {
                Haptics.shared.play(.success)
                // A title, not an errand: "list your first watch" is gone.
                // While Stripe is still verifying, the dashboard's own notice
                // says so, and a success toast here would contradict it.
                if readiness.canList {
                    toasts.show(title: "You're set up to sell", tone: .success)
                }
                onFinished()
            } else if backFromStripe,
                      readiness.connect.status != .rejected,
                      SellerSetupSteps.payoutsNeedNothingFromSeller(readiness.connect.payoutStep),
                      sellerCard?.present != true || sellerCard?.valid == false {
                // Back from Stripe with nothing more owed there: the card is
                // the one step left, so its form opens without a tap.
                cardStepOpensForm = true
                showCardStep = true
            }
        } catch {
            cardHold.readinessLanded(cardRead: nil)
            if finishCard != nil {
                resolveFinish(finishRun.readinessLanded(finished: false))
            }
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
                                .font(RewatchType.caption)
                                .foregroundStyle(Color.rewatch.mutedForeground)
                        }
                        Text(name)
                            .font(RewatchType.bodyMedium)
                            .foregroundStyle(Color.rewatch.foreground)
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
                    .foregroundStyle(Color.rewatch.success)
            case .attention:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rewatch.destructive)
            case .current, .waiting:
                Text("\(number)")
                    .font(RewatchType.bodyMedium)
                    .foregroundStyle(
                        state == .current ? Color.rewatch.accentForeground : Color.rewatch.mutedForeground
                    )
            }
        }
        .frame(width: 32, height: 32)
        .background(
            Color.rewatch.accent.opacity(state == .waiting ? 0.5 : 1),
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

// MARK: - The finish

/// The end of seller setup, played once the card that completes it is saved
/// (Eytan, 2026-10-06: "collapse into the card and slide off the side of the
/// screen, then open the dashboard, but first a nice 'welcome to selling on
/// Rewatch'"). The web's `SellerSetupFinish.tsx` is the authority on the
/// sequence and its timing:
///
///   0.05–0.50s  the saved card settles in as the card sheet closes
///   0.65–1.10s  it slides off the right edge with a slight tilt
///   1.00–1.50s  "Welcome to selling on Rewatch" rises in, copper rule above
///   2.15–2.40s  the welcome settles out, and `onDone` opens the dashboard
///
/// Reduce Motion: no card and no travel, the welcome fades in and out, 1.5s.
/// A tap anywhere skips to `onDone`. `onDone` may be called more than once
/// (a tap and the timer); `SellerSetupFinishRun` acts on the first only.
struct SellerSetupFinishView: View {
    let card: SellerCardState
    /// The DEBUG preview turns this off to hold on the welcome.
    var autoFinish = true
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardIn = false
    @State private var cardGone = false
    @State private var welcomeIn = false
    @State private var welcomeOut = false

    private static let easeOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.45)
    private static let easeIn = Animation.timingCurve(0.55, 0, 0.75, 0.2, duration: 0.45)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.rewatch.background.ignoresSafeArea()

                if !reduceMotion {
                    GuaranteeCard(
                        brand: GuaranteeCard.Brand(stripeBrand: card.brand),
                        last4: card.last4,
                        expiry: card.expiryLabel,
                        status: .onFile,
                        size: .compact
                    )
                    // Sized outright: the drawing fills whatever it is
                    // offered, and a GeometryReader offers the whole screen.
                    .frame(
                        width: min(300, proxy.size.width - Space.margin * 2),
                        height: min(300, proxy.size.width - Space.margin * 2) / (85.60 / 53.98)
                    )
                    .scaleEffect(cardIn ? 1 : 1.12)
                    .opacity(cardIn ? 1 : 0)
                    .rotationEffect(.degrees(cardGone ? -6 : 0))
                    .offset(x: cardGone ? proxy.size.width : 0)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                    .accessibilityHidden(true)
                }

                VStack(spacing: Space.m) {
                    Rectangle()
                        .fill(Color.rewatch.primary)
                        .frame(width: 40, height: 1)
                        .accessibilityHidden(true)
                    Text("Welcome to selling on Rewatch")
                        .font(RewatchType.display)
                        .foregroundStyle(Color.rewatch.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your card is on file. Opening your seller dashboard.")
                        .font(RewatchType.body)
                        .foregroundStyle(Color.rewatch.secondaryForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.margin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(welcomeIn && !welcomeOut ? 1 : 0)
                .offset(y: welcomeIn || reduceMotion ? 0 : 14)
                .accessibilityElement(children: .combine)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .accessibilityAction(named: "Open your dashboard") { onDone() }
        .task { await play() }
    }

    private func pause(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            return true
        } catch {
            return false
        }
    }

    private func play() async {
        if reduceMotion {
            guard await pause(0.15) else { return }
            withAnimation(.linear(duration: 0.3)) { welcomeIn = true }
            guard autoFinish, await pause(1.1) else { return }
            withAnimation(.linear(duration: 0.25)) { welcomeOut = true }
            guard await pause(0.25) else { return }
            onDone()
            return
        }
        guard await pause(0.05) else { return }
        withAnimation(Self.easeOut) { cardIn = true }
        guard await pause(0.60) else { return }
        withAnimation(Self.easeIn) { cardGone = true }
        guard await pause(0.35) else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.5)) { welcomeIn = true }
        guard autoFinish, await pause(1.15) else { return }
        withAnimation(.linear(duration: 0.25)) { welcomeOut = true }
        guard await pause(0.25) else { return }
        onDone()
    }
}

#if DEBUG
/// The finish without a Stripe card: `-sellerSetupFinishPreview` launches
/// straight into this. A beat of a stand-in card step, then the finish over
/// it, then a stand-in dashboard; a tap on the dashboard plays it again.
struct SellerSetupFinishPreviewScreen: View {
    @State private var playing = false
    @State private var finished = false
    @State private var round = 0

    private static let card: SellerCardState? = try? JSONDecoder().decode(
        SellerCardState.self,
        from: Data(#"{"present":true,"brand":"visa","last4":"4242","expMonth":4,"expYear":2030,"funding":"credit","valid":true,"expiringSoon":false}"#.utf8)
    )

    var body: some View {
        ZStack {
            Color.rewatch.background.ignoresSafeArea()
            if finished {
                VStack(spacing: Space.m) {
                    Text("Seller dashboard")
                        .font(RewatchType.title)
                        .foregroundStyle(Color.rewatch.foreground)
                    Text("Preview stand-in. Tap to play the finish again.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                }
                .transition(.opacity)
                .onTapGesture { replay() }
            } else {
                VStack(alignment: .leading, spacing: Space.l) {
                    Eyebrow("Setting up your storefront")
                    Text("Card on file")
                        .font(RewatchType.sectionTitle)
                        .foregroundStyle(Color.rewatch.foreground)
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .stroke(Color.rewatch.border)
                        .frame(height: 180)
                }
                .padding(Space.margin)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            if playing, let card = Self.card {
                SellerSetupFinishView(card: card) {
                    guard playing else { return }
                    withAnimation(Motion.easeMedium) {
                        playing = false
                        finished = true
                    }
                }
                .id(round)
                .transition(.opacity)
            }
        }
        .task(id: round) {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeOut(duration: 0.2)) { playing = true }
        }
    }

    private func replay() {
        finished = false
        round += 1
    }
}

#Preview("Seller setup finish") {
    SellerSetupFinishPreviewScreen()
}
#endif
