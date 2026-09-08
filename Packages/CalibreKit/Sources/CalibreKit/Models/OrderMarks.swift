import Foundation

/// Which illustrated mark the buyer's order screen draws, out of the three
/// that want it.
///
/// The budget is one illustrated moment per step of a journey
/// (`CALIBRE_BY_HAND_CONTRACTS.md` §4), so the precedence is written once here
/// and read in order rather than worked out again in the view. The order is
/// chosen so the mark is about the thing the reader is looking at right now.
///
/// The loupe is not in this list, and on iOS that is not an omission. The
/// authentication report opens in a sheet, which is its own surface with the
/// order screen behind it — so the loupe there can never be the order screen's
/// second mark. On the web the report is a panel on the page itself, which is
/// why `orderMarkFor` has a clause for it there and this does not.
///
/// Lives in the domain package rather than the view so it can be tested
/// without a screen; the names are the vocabulary's, and `CalibreDesign` is
/// what draws them.
public enum OrderMark: String, Sendable, Equatable {
    case box
    case stamp
    case dialArc
}

/// The verdict the stamp is allowed to assert, spelled exactly as the bench
/// records it (`VERDICT_AUTHENTICATED` in `app/services/auth_records.py`).
private let authenticatedVerdict = "authenticated"

public extension Order {
    /// The watch is with a carrier, in one direction or the other.
    ///
    /// The same two statuses the screen's own sixty-second refetch runs on, so
    /// the parcel and the poll can never disagree about whether a watch is
    /// travelling.
    var isTravelling: Bool {
        status == .toAuth || status == .toBuyer
    }

    /// Which mark this order gets, or none.
    ///
    /// - `box` while it is travelling. Never on `delivered`, `purchased`,
    ///   `authPass`, `cancelled`, `refunded` or `authFail`: a carton leaving
    ///   the frame on a delivered order reads as the watch going away again.
    /// - `stamp` on the bench's own positive verdict. Read that gate
    ///   literally: it is **not** `status == .authPass` and it is emphatically
    ///   not the checkpoint index — `trackerIndex` puts a failed order on the
    ///   same dot as a passed one, so a mark keyed to the rail would stamp a
    ///   watch that failed. A missing record is not a negative one either
    ///   (`verdict` is nil on payloads from deployments that predate it), and
    ///   nil is not a pass.
    /// - `dialArc` on an open return window whose two ends both parsed.
    ///   `remainingFraction` clamps a window that has run out to zero rather
    ///   than to nil, so `isOpen` is asked as well: a spent window reads as a
    ///   needle standing at a deadline that has already passed, beside a
    ///   sentence that no longer offers a return. Android's
    ///   `returnWindowReading` answers null for the same case and the web's
    ///   `returnOfferOpen` gates on the same fact.
    func mark(now: Date = .now) -> OrderMark? {
        if isTravelling {
            return .box
        }
        if authentication?.verdict == authenticatedVerdict {
            return .stamp
        }
        if status == .delivered,
           let terms = returns,
           terms.isOpen(now: now),
           terms.remainingFraction(now: now) != nil {
            return .dialArc
        }
        return nil
    }

    /// The lead's own mark, and the fact it stands for: the order is paid and
    /// nothing has shipped yet, so the parcel is being packed. Drawn in the
    /// lead rather than the journey header — the journey has no leg to show
    /// yet — and only while `mark(now:)` has nothing else to say, which keeps
    /// the screen at one mark: a bench verdict or a travelling parcel outranks
    /// the checkout moment. The web keys its `CheckoutSuccessMoment` on the
    /// same fact with the same key.
    func checkoutMarkKey(now: Date = .now) -> String? {
        guard status == .purchased, mark(now: now) == nil else { return nil }
        return "checkout:\(id)"
    }

    /// What the parcel's animation is keyed to: the milestone itself.
    ///
    /// Android's order screen keys its box the same way and its comment is the
    /// reason — the screen refetches every sixty seconds while a watch is
    /// travelling, and a correctly keyed mark ignores every one of those while
    /// still setting off again on a status that changes under the buyer.
    var transitMarkKey: String { "order-transit:\(id):\(status.rawValue)" }

    /// The stamp's key, and the fact it stands for. Nil when there is no
    /// positive verdict to announce.
    var verdictMarkKey: String? {
        guard let verdict = authentication?.verdict, verdict == authenticatedVerdict else { return nil }
        return "order-verdict:\(id):\(verdict)"
    }
}

public extension OrderReturnTerms {
    /// How much of the return window is still ahead, 0 to 1, or nil.
    ///
    /// Both ends come off the server — `OrderReturnTerms` carries the window's
    /// start and its end — so this is two timestamps and a clock rather than an
    /// assumption about what the window ought to be. A gauge with a guessed
    /// denominator is worse than no gauge, so a missing end, an unparseable
    /// pair, or a pair describing no window at all returns nil and the caller
    /// draws nothing.
    ///
    /// Clamped, because a window that closed while the screen was open reads
    /// below zero and a needle cannot travel past either stop.
    func remainingFraction(now: Date = .now) -> Double? {
        guard let started = windowStartedAt, let ends = windowEndsAt else { return nil }
        let total = ends.timeIntervalSince(started)
        guard total > 0 else { return nil }
        return min(max(ends.timeIntervalSince(now) / total, 0), 1)
    }
}
