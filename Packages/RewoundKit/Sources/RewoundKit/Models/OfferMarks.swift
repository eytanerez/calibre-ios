import Foundation

/// Which illustrated marks the offer screen is allowed to draw, and what they
/// read. The screen already spends its one mark on the seal at
/// `accepted_pending_payment`; the gauge below is for a different status, so
/// the two can never share a screen.
///
/// Lives in the domain package rather than the view so the gate can be tested
/// without a screen; `RewoundDesign` is what draws it.
public extension Offer {
    /// How much of the seller's first-round window is still ahead, 0 (spent)
    /// to 1 (the whole window), or nil when there is no such window to read.
    ///
    /// The gate is the first round only: `pending_seller` with nothing in the
    /// negotiation history. A countered offer is a different conversation
    /// and the band that owns those screens says so in words.
    ///
    /// Both ends are the server's — the offer's own `created_at` and
    /// `expires_at` — so this is two timestamps and a clock rather than a
    /// guess at what an offer window ought to be. A missing end, a pair that
    /// describes no window, or a window that has already closed returns nil
    /// and the caller draws nothing: a needle standing at a deadline that has
    /// passed, beside a chip that no longer counts, is worse than no gauge.
    func firstRoundWindowRemaining(now: Date = .now) -> Double? {
        guard status == .pendingSeller, negotiationHistory.isEmpty,
              let created = createdAt, let expires = expiresAt,
              expires > now
        else { return nil }
        let total = expires.timeIntervalSince(created)
        guard total > 0 else { return nil }
        return min(max(expires.timeIntervalSince(now) / total, 0), 1)
    }
}
