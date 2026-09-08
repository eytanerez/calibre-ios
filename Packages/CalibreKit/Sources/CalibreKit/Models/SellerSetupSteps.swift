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
        guard !payoutsComplete, let card, card.present else { return false }
        return card.valid != false && card.expiringSoon != true
    }
}
