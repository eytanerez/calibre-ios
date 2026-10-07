import Foundation

/// Which of seller setup's steps are worth putting in front of a seller.
///
/// A finished step that cannot be redone is not a step. The gate used to show
/// the card beside payouts unconditionally, so a seller who gave a card in an
/// earlier pass — the usual shape of arriving from the dealer application's
/// seller-setup link — was told there were two things to do when there was
/// one, and the "done" marker beside the outstanding one read as an ask.
///
/// The authority is the web's `cardStepIsRedundant` in
/// `components/SellerStripeOnboarding.tsx`.
public enum SellerSetupSteps {
    /// True when the card step should not be drawn at all.
    ///
    /// Three things have to hold. The card is genuinely finished — present,
    /// not lapsed, and not about to lapse. Payouts are not, so the card is the
    /// completed half of a job the seller is still in the middle of. And a
    /// card about to expire is the one carve-out: that is a live problem on its
    /// own account, independent of payouts, so this rule never hides it.
    ///
    /// A rejected payout account is handled at the call site rather than here:
    /// nobody who has been turned down can list, so the card is not that
    /// screen's business in any card state.
    public static func cardStepIsRedundant(card: SellerCardState?, payoutsComplete: Bool) -> Bool {
        !payoutsComplete && cardStepIsFinished(card)
    }

    /// True when the card step stands finished on its own terms: a card on
    /// file, working, and not about to lapse. What the gate draws as done.
    public static func cardStepIsFinished(_ card: SellerCardState?) -> Bool {
        guard let card, card.present else { return false }
        return card.valid != false && card.expiringSoon != true
    }

    /// How many of setup's steps stand finished — the count the crown winds
    /// on, and so the number in its key.
    ///
    /// A step counts only when it is drawn as done. The web's `SetupStepper`
    /// counts the rows it draws in state "done", and a card
    /// `cardStepIsRedundant` folds away is not drawn there, so it counts for
    /// nothing: finished long before, it is not a step and not news. The same
    /// here, or the two platforms wind the crown on different keys for the
    /// same seller — a card on file beside outstanding payouts is 0, not 1,
    /// and payouts then finishing is `seller-setup:1` on both. A rejected
    /// account counts neither: the card is not drawn, and not because it is
    /// finished.
    public static func stepsDone(card: SellerCardState?, payoutsComplete: Bool, payoutsRejected: Bool) -> Int {
        let cardDrawnAsDone = !payoutsRejected
            && !cardStepIsRedundant(card: card, payoutsComplete: payoutsComplete)
            && cardStepIsFinished(card)
        return (payoutsComplete ? 1 : 0) + (cardDrawnAsDone ? 1 : 0)
    }
}

extension SellerSetupSteps {
    /// Whether the seller has done their half of setup: payouts handed to
    /// Stripe and a card on file. Listing can still be shut after this —
    /// Stripe switching payouts on is nobody's to finish — but there is
    /// nothing left to ask the seller for, so this is when setup hands them to
    /// their dashboard (Eytan, 2026-10-06: "you do the card and straight to
    /// dashboard"). The web's `sellerFinishedSetup` is the authority.
    ///
    /// `missingRequirements` answers it when the server sends it: done means
    /// nothing is owed but `payouts_enabled`. Against a server that does not,
    /// payouts are read off the status and the card off `card`; a card that
    /// could not be read is not a card on file.
    public static func finishedBySeller(_ readiness: SellerReadiness, card: SellerCardState?) -> Bool {
        if readiness.canList { return true }
        let connect = readiness.connect
        if connect.status == .rejected { return false }
        if let missing = readiness.missingRequirements {
            return missing.allSatisfy { $0 == "payouts_enabled" }
        }
        let payoutsDone = connect.status == .complete
            || connect.status == .underReview
            || (connect.onboardingComplete && connect.payoutsEnabled)
        guard payoutsDone, let card, card.present else { return false }
        return card.valid != false
    }

    /// Whether payouts need nothing more from the seller, so the card is the
    /// step to take now. `underReview` counts: Stripe is reading what the
    /// seller already sent, and a slow review must not hold the card back.
    public static func payoutsNeedNothingFromSeller(_ step: PayoutSetupStep) -> Bool {
        step.isComplete || step.status == .underReview
    }
}

/// What the crown beside seller setup announces: a step finishing.
///
/// Held at its peak rather than read live. Readiness is refetched, and a
/// refetch that briefly reports fewer finished steps — a cached read, a card
/// that lapses — must not wind the crown backwards or take it off the screen;
/// nor can a crown wind for a step that was already finished when the seller
/// arrived. So the count only ever rises, and the key is the count it rose
/// to. The web's `SetupStepper` holds the same peak in a ref and keys the same
/// way.
public struct SellerSetupProgress: Equatable, Sendable {
    public private(set) var peakStepsDone = 0

    public init() {}

    /// Record how many steps stand finished right now. A lower count than the
    /// peak changes nothing.
    public mutating func record(stepsDone: Int) {
        peakStepsDone = max(peakStepsDone, stepsDone)
    }

    /// The event the crown winds on, or nil while nothing has finished — and
    /// nothing is drawn for nil.
    public var markKey: String? {
        peakStepsDone > 0 ? "seller-setup:\(peakStepsDone)" : nil
    }
}

// MARK: - The finish

/// Whether saving a card should play setup's finish: the card collapses into
/// itself, leaves the screen, and "Welcome to selling on Rewatch" plays before
/// the dashboard opens (Eytan, 2026-10-06). The web's `startFinish` in
/// `SellerStripeOnboarding.tsx` is the authority.
///
/// Only the save that completes the seller's half plays it: payouts already
/// need nothing from them, and this card is the last thing. Replacing a card
/// that was working is not finishing anything, and a rejected account never
/// finishes. `enabled` is the host's say — the dashboard's own setup sheet
/// passes false, because that seller already has a shop.
public enum SellerSetupFinishRule {
    public static func playsFinish(
        enabled: Bool,
        readiness: SellerReadiness?,
        cardBefore: SellerCardState?,
        saved: SellerCardState
    ) -> Bool {
        guard saved.present, saved.valid != false else { return false }
        return wouldPlay(enabled: enabled, readiness: readiness, cardBefore: cardBefore)
    }

    /// Whether a successful save, made now, would play the finish — asked
    /// before the card sheet opens, so the sheet can leave its own "Card
    /// saved" toast to the welcome.
    public static func wouldPlay(
        enabled: Bool,
        readiness: SellerReadiness?,
        cardBefore: SellerCardState?
    ) -> Bool {
        guard enabled, let readiness else { return false }
        guard readiness.connect.status != .rejected else { return false }
        // A working card already on file means this save replaced it.
        if let cardBefore, cardBefore.present, cardBefore.valid != false {
            return false
        }
        return SellerSetupSteps.payoutsNeedNothingFromSeller(readiness.connect.payoutStep)
    }
}

/// One playing of the finish, resolved exactly once.
///
/// Two things have to have happened before the dashboard opens: the animation
/// has ended (or been skipped by a tap), and the readiness re-read the save
/// set off has come back. They arrive in either order. Whichever is second
/// resolves the run, and nothing after that resolves it again — so the
/// dashboard can never be opened twice, or opened by the re-read while the
/// card is still on its way off the screen.
public struct SellerSetupFinishRun: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Still waiting on the other half.
        case wait
        /// Both in, and setup is finished: open the dashboard.
        case openDashboard
        /// Both in, and the server disagrees (or could not be reached): put
        /// the gate back, with whatever it now says.
        case returnToGate
    }

    public private(set) var animationEnded = false
    public private(set) var readinessFinished: Bool?
    public private(set) var resolved = false

    public init() {}

    public mutating func endAnimation() -> Outcome {
        animationEnded = true
        return resolve()
    }

    public mutating func readinessLanded(finished: Bool) -> Outcome {
        if readinessFinished == nil {
            readinessFinished = finished
        }
        return resolve()
    }

    private mutating func resolve() -> Outcome {
        guard !resolved, animationEnded, let finished = readinessFinished else { return .wait }
        resolved = true
        return finished ? .openDashboard : .returnToGate
    }
}

/// The card the setup gate draws, held back until readiness has caught up.
///
/// The gate used to draw a saved card the moment the card sheet handed it
/// over, while readiness still said the card was owed — so for the length of
/// the re-read the card step showed its finished face behind the closing
/// sheet, and then the screen swapped to the dashboard. The same flash the
/// web had. Held here, the card and the readiness answer change together.
public struct SellerCardSaveHold: Sendable {
    public private(set) var shown: SellerCardState?
    public private(set) var pending: SellerCardState?

    public init(shown: SellerCardState? = nil) {
        self.shown = shown
    }

    /// A card was saved: remembered, not drawn.
    public mutating func cardSaved(_ card: SellerCardState) {
        pending = card
    }

    /// Readiness has been re-read: the saved card (or a fresher read of it)
    /// is drawn now, in the same change as the readiness answer.
    public mutating func readinessLanded(cardRead: SellerCardState?) {
        if let cardRead {
            shown = cardRead
        } else if let pending {
            shown = pending
        }
        pending = nil
    }

    /// A plain read with no save in flight.
    public mutating func show(_ card: SellerCardState?) {
        guard pending == nil else { return }
        shown = card
    }
}
