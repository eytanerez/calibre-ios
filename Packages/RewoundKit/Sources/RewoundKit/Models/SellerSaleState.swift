import Foundation

/// A sale as the seller has to act on it: where the money stands, and whose
/// move it is.
///
/// Separate from `OrderState.swift`, which answers the same two questions for
/// the *buyer*. The facts are the same order; the readings are not. "With the
/// seller" is a sentence written for somebody waiting on a stranger, and the
/// seller reading it is that stranger. `OrderActor.label` is therefore not
/// reused here — a shared table that has to be true for two different readers
/// is a table that is wrong for one of them.
///
/// The authority for these decisions is the web's seller Orders tab
/// (`pages/account/sell/{OrdersTab,shared}.tsx`). Every figure a caller prints
/// beside these readings is the server's own: nothing here does arithmetic on
/// a seller's money, and nothing here claims a payout has landed anywhere.

// MARK: - Where a payout stands

/// The payout states a seller row can be in.
///
/// The server's `payout_status` is a longer list than this, and several of its
/// words mean the same thing to somebody asking "am I still owed this". They
/// are folded here, and a word this build does not recognise says so rather
/// than being folded into `scheduled` — which would promise a payout that may
/// not be coming.
public enum SellerPayoutState: String, Sendable, Equatable, CaseIterable {
    /// Priced and waiting on its release trigger.
    case scheduled
    /// Money Calibre is holding rather than sending — bank details outstanding,
    /// or a payment under review. The row's own status line says which.
    case held
    /// Sent. It has left Calibre; where it is after that is the bank's answer,
    /// never this app's.
    case released
    /// Calibre could not send it, or the bank sent it back. Different people to
    /// call, same answer to "am I still owed this": yes.
    case failed
    /// Cancelled, refunded or reversed. Nothing further is coming on this sale.
    case closed
    /// A word this build has not been taught.
    case unknown

    /// The short name for a state, for a chip beside the server's own
    /// sentence.
    public var label: String {
        switch self {
        case .scheduled: "Scheduled"
        case .held: "On hold"
        case .released: "On its way"
        case .failed: "Did not go through"
        case .closed: "Closed"
        case .unknown: "Status unclear"
        }
    }

    /// Whether a payout in this state is still expected to arrive. `false` for
    /// the two states where "not released yet" would be a promise: one that
    /// will not be released, and one this build cannot speak for.
    public var isStillComing: Bool {
        switch self {
        case .scheduled, .held, .released, .failed: true
        case .closed, .unknown: false
        }
    }

    public init(wireValue: String?) {
        switch (wireValue ?? "").trimmingCharacters(in: .whitespaces) {
        case "pending": self = .scheduled
        case "pending_connect", "blocked_dispute": self = .held
        case "released": self = .released
        case "failed", "failed_at_bank": self = .failed
        case "cancelled", "refunded", "reversed", "partially_reversed": self = .closed
        default: self = .unknown
        }
    }
}

// MARK: - Whose move it is

/// Who a sale is waiting on, and what for.
///
/// Read off the order's own state rather than a second copy of the fulfilment
/// rules: `sellerActionState` is the server saying the seller owes something,
/// and it is the only thing that puts a sale on the seller's own list.
public struct SellerSaleStep: Sendable, Equatable {
    /// "Waiting on you" / "Waiting on the buyer" / "Waiting on Calibre" /
    /// "Nothing needed from you".
    public let who: String
    /// The one line under it.
    public let what: String
    /// True when the seller has a form to fill in — the row's action changes
    /// with it.
    public let needsShippingDetails: Bool

    public init(who: String, what: String, needsShippingDetails: Bool = false) {
        self.who = who
        self.what = what
        self.needsShippingDetails = needsShippingDetails
    }
}

public extension Order {
    /// Where this sale's money stands.
    var sellerPayoutState: SellerPayoutState {
        SellerPayoutState(wireValue: payoutStatus)
    }

    /// The payout's own sentence, as the server wrote it, falling back to the
    /// state's name.
    ///
    /// Never a hard-coded "Scheduled": a payout that failed with no status
    /// line on the payload used to read as one still on its way.
    var sellerPayoutStatusLine: String {
        if let label = payoutBlock?.statusLabel, !label.isEmpty {
            return label
        }
        return sellerPayoutState.label
    }

    /// Whose move this sale is.
    var sellerNextStep: SellerSaleStep {
        if sellerActionState == "sold_awaiting_label_creation" {
            return SellerSaleStep(
                who: "Waiting on you",
                what: "Add the shipping details and Calibre buys the label.",
                needsShippingDetails: true
            )
        }
        if status == .awaitingWire || sellerActionState == "awaiting_wire_transfer" {
            return SellerSaleStep(who: "Waiting on the buyer", what: "Their wire transfer hasn't arrived yet.")
        }
        if status == .delivered {
            return SellerSaleStep(who: "Nothing needed from you", what: "The watch reached the buyer.")
        }
        if status == .cancelled || status == .refunded {
            return SellerSaleStep(who: "Nothing needed from you", what: "This sale is closed.")
        }
        return SellerSaleStep(who: "Waiting on Calibre", what: sellerCalibreLine)
    }

    /// What Calibre is doing with the watch, where the order status is the only
    /// thing that knows. `.unknown` is a status word this build has not been
    /// taught, so it says that the sale is moving and nothing more precise.
    private var sellerCalibreLine: String {
        switch status {
        case .purchased: "The sale is being prepared."
        case .toAuth: "On its way to the authentication center."
        case .authPass: "Authenticated. It goes out to the buyer next."
        case .authFail: "It didn't pass authentication. Someone here is in touch."
        case .toBuyer: "On its way to the buyer."
        case .awaitingWire, .delivered, .cancelled, .refunded, .unknown: "This sale is with Calibre."
        }
    }
}
