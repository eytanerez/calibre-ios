import Foundation

// The seller-setup status model, as `app/services/connect_status.py` states it.
// Booleans could not tell "stopped partway through the form" apart from
// "finished the form and Stripe came back for more", so the backend answers
// with one word and the client renders one screen per word.

/// Where a seller's Stripe payout setup stands, in one word.
///
/// `ListingStatus` and the rest of the wire enums fall back to a payload-free
/// `.unknown` through `decodeWireStatus`, which keeps a new server word from
/// crashing the app but loses the word itself. This one keeps it. The states
/// here drive an entire screen rather than a badge: a seller who lands on a
/// word this build has never heard of gets a screen that can still name what
/// the server said, and support can read it back off a screenshot.
public enum ConnectSetupStatus: Codable, Sendable, Hashable {
    /// No Connect account yet.
    case notStarted
    /// An account exists and the form has not been submitted.
    case inProgress
    /// Submitted, and Stripe is reading something. Nothing to do.
    case underReview
    /// Submitted, and Stripe came back asking for more.
    case needsMore
    /// Terminal. Re-entering details does not reopen this.
    case rejected
    /// Submitted with nothing outstanding.
    case complete
    /// A word this build does not know, kept verbatim.
    case unknown(String)

    /// The word the server sent, which for a known state is the word it would
    /// send again.
    public var wireValue: String {
        switch self {
        case .notStarted: "not_started"
        case .inProgress: "in_progress"
        case .underReview: "under_review"
        case .needsMore: "needs_more"
        case .rejected: "rejected"
        case .complete: "complete"
        case .unknown(let raw): raw
        }
    }

    public init(wireValue: String) {
        switch wireValue {
        case "not_started": self = .notStarted
        case "in_progress": self = .inProgress
        case "under_review": self = .underReview
        case "needs_more": self = .needsMore
        case "rejected": self = .rejected
        case "complete": self = .complete
        default: self = .unknown(wireValue)
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(wireValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

/// Whether the status came from a live Stripe read or from the booleans a
/// previous sync or webhook left on the seller row.
///
/// This is not a detail a seller should ever be shown, but the client cannot
/// render honestly without it: a cached answer carries empty item lists by
/// design, because the row remembers that requirements were outstanding and
/// not what they were called.
public enum ConnectStatusBasis: String, Codable, Sendable {
    case live
    case cached
    case unknown

    public init(from decoder: Decoder) throws {
        self = try decodeWireStatus(from: decoder, fallback: .unknown)
    }
}

/// One thing Stripe is waiting on, already humanized server-side.
///
/// The `key` is the backend's slug for a requirement it has a rule for, and
/// the raw Stripe key otherwise — so support can match an unrecognized one
/// against the Stripe dashboard verbatim. The label is what the seller reads;
/// no client rewrites it.
public struct ConnectRequirementItem: Codable, Sendable, Hashable, Identifiable {
    public let key: String
    public let label: String

    public var id: String { key }

    public init(key: String, label: String) {
        self.key = key
        self.label = label
    }
}

// MARK: - Step 1 of seller setup, as one screen's worth of decisions

/// What the payouts step says and offers, derived from the server's word.
///
/// A value type rather than a pile of `if`s inside the view, so the mapping
/// can be tested without a running app — and so the two rules that actually
/// matter are checkable: a rejected seller is never handed a form, and
/// `disabledReason` never reaches a field a seller reads. Stripe writes that
/// field for machines — `"rejected.fraud"` is an accusation in a string, and
/// showing it to the person it names is not a status update.
public struct PayoutSetupStep: Equatable, Sendable {
    /// How loudly the step should present itself.
    public enum Tone: Sendable {
        /// Ordinary progress, and the reviewing state — which is calm on
        /// purpose: there is nothing for the seller to do about it.
        case calm
        /// Something is waiting on the seller, or has gone wrong.
        case attention
        /// Finished.
        case done
    }

    /// The single thing this step's button does.
    public enum Action: Equatable, Sendable {
        /// Collect the SSN, then open Stripe's form for the first time.
        case collectSSN(title: String)
        /// Open the embedded form on an account that already exists.
        case openForm(title: String)
        /// Read readiness again. There is nothing to fill in.
        case refresh(title: String)
        /// The dead end: support, with the first message already written.
        case contactSupport(title: String)
        /// Nothing to offer.
        case none
    }

    public let status: ConnectSetupStatus
    /// The state's own headline. Nil where the step's name already says it —
    /// a card headed "Payouts with Stripe" does not want that sentence twice.
    public let title: String?
    public let body: String
    public let tone: Tone
    /// The heading above `items`, when there are items to head.
    public let itemsTitle: String?
    public let items: [ConnectRequirementItem]
    /// Stands in for a checklist the server could not name — most often a
    /// cached read, which remembers that something was outstanding but not what
    /// it was called. An empty checklist would read as "nothing left", which is
    /// the opposite of what such a payload means.
    public let itemsWithheldNote: String?
    /// One quiet line about what Stripe may come back for later.
    public let upcomingNote: String?
    public let action: Action
    public let footnote: String?
    public let isComplete: Bool
}

/// The first message a rejected seller sends, written for them because the
/// dead end is ours to explain and not theirs to phrase.
public let payoutRejectedSupportMessage =
    "My payout account couldn't be approved and I'd like help understanding why."

extension ConnectStatus {
    /// The payouts step as this account currently stands.
    ///
    /// Every branch is reachable from the backend's own precedence ladder, and
    /// the two that matter most are the ones that withhold something:
    /// `rejected` offers no form and no retry, and a state with nothing left
    /// to name offers a sentence where a checklist would lie.
    public var payoutStep: PayoutSetupStep {
        let hasAccount = !(accountId ?? "").trimmingCharacters(in: .whitespaces).isEmpty

        switch status {
        case .notStarted:
            return notStartedStep

        case .inProgress:
            return PayoutSetupStep(
                status: status,
                title: "You're partway through",
                body: "Your name and address are saved. Open the form again and Stripe picks up where you left off.",
                tone: .calm,
                itemsTitle: missingItems.isEmpty ? nil : "Still to add:",
                items: missingItems,
                itemsWithheldNote: withheldNote,
                upcomingNote: upcomingNote,
                action: .openForm(title: "Continue setting up payouts"),
                footnote: nil,
                isComplete: false
            )

        case .underReview:
            return PayoutSetupStep(
                status: status,
                title: "Stripe is reviewing your details",
                body: "Nothing needed from you. We'll open your shop as soon as they're done.",
                tone: .calm,
                itemsTitle: reviewItems.isEmpty ? nil : "What they're looking at:",
                items: reviewItems,
                itemsWithheldNote: nil,
                upcomingNote: nil,
                action: .refresh(title: "Check again"),
                footnote: "Reviews usually finish within a day or two.",
                isComplete: false
            )

        case .needsMore:
            // A list is its own count, so "one more thing" is only ever
            // written above a list of one — Stripe commonly asks for two.
            // With the names withheld there is no list to introduce, so the
            // sentence loses its colon along with its number.
            let lead: String
            switch missingItems.count {
            case 0: lead = "Stripe needs a little more."
            case 1: lead = "Stripe needs one more thing:"
            default: lead = "Stripe needs a few more details:"
            }
            return PayoutSetupStep(
                status: status,
                title: "Stripe came back for more",
                body: "You've submitted your details. \(lead)",
                tone: .attention,
                itemsTitle: nil,
                items: missingItems,
                itemsWithheldNote: withheldNote,
                upcomingNote: nil,
                action: .openForm(title: "Finish with Stripe"),
                footnote: nil,
                isComplete: false
            )

        case .rejected:
            return PayoutSetupStep(
                status: status,
                title: "Payouts couldn't be approved",
                body: "Stripe wasn't able to approve payouts for this account. This usually can't be fixed by re-entering details.",
                tone: .attention,
                itemsTitle: nil,
                items: [],
                itemsWithheldNote: nil,
                upcomingNote: nil,
                action: .contactSupport(title: "Talk to us about this"),
                footnote: "Someone from our team may already be reaching out about it.",
                isComplete: false
            )

        case .complete:
            return PayoutSetupStep(
                status: status,
                title: nil,
                body: "Verified — your money goes straight to your bank account.",
                tone: .done,
                itemsTitle: nil,
                items: [],
                itemsWithheldNote: nil,
                upcomingNote: nil,
                action: .none,
                footnote: nil,
                isComplete: true
            )

        case .unknown:
            // A word from a newer server. Without an account there is nothing
            // this could mean but "not started", and the first screen is the
            // honest one. With an account, the form is the only place that can
            // say more than we can — so it stays reachable, and nothing here
            // claims to know where the seller stands.
            guard hasAccount else { return notStartedStep }
            return PayoutSetupStep(
                status: status,
                title: nil,
                body: "Open your payout setup with Stripe and they'll show you what's still needed.",
                tone: .calm,
                itemsTitle: missingItems.isEmpty ? nil : "Still to add:",
                items: missingItems,
                itemsWithheldNote: nil,
                upcomingNote: nil,
                action: .openForm(title: "Open payout setup"),
                footnote: nil,
                isComplete: false
            )
        }
    }

    private var notStartedStep: PayoutSetupStep {
        PayoutSetupStep(
            status: status,
            title: nil,
            body: "Verify your details once with Stripe. Calibre never sees your banking information.",
            tone: .calm,
            itemsTitle: nil,
            items: [],
            itemsWithheldNote: nil,
            upcomingNote: nil,
            action: .collectSSN(title: "Set up payouts"),
            footnote: nil,
            isComplete: false
        )
    }

    /// The sentence that replaces a checklist the server could not name.
    ///
    /// Keyed on the list being empty rather than on `statusBasis == .cached`,
    /// which is the strictly safer test: a live read that names nothing lands
    /// here too, and a basis word this build has never seen cannot defeat it.
    /// The basis is still decoded — it is the reason the list can be empty,
    /// not the condition for saying so.
    ///
    /// Only the states that would otherwise draw a checklist consult this.
    /// `under_review` with an empty list is a review with nothing outstanding,
    /// not a hidden chore, and `not_started` always arrives cached and empty
    /// because a seller with no account id can never produce a live read.
    private var withheldNote: String? {
        guard missingItems.isEmpty else { return nil }
        return "A few details are still needed — open the form to see them."
    }

    /// What Stripe may ask for after the current round, in one line. Their
    /// labels, joined; nothing here is shortened or counted.
    private var upcomingNote: String? {
        guard !upcomingItems.isEmpty else { return nil }
        return "Stripe may ask for this later: " + upcomingItems.map(\.label).joined(separator: ", ")
    }
}
