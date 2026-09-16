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
