import Foundation

/// What Calibre decided about a seller's listing, in the seller's own copy of
/// the record.
///
/// This exists because the letters stopped carrying it. A review outcome used
/// to be explained in an email and nowhere else: this app, Android and the site
/// all printed the reason on a `rejected` listing and on nothing else. That left
/// the COMMON outcome — `needs-more-info`, the one a reviewer reaches a hundred
/// times a week, which lands the listing back in the seller's drafts —
/// explained only in an inbox. A seller who deleted the mail had a listing in
/// their drafts with no way to find out what it was waiting for. Take-downs
/// were the same. The letter now says "open the listing", so this is what it
/// opens onto, and it is the whole explanation rather than a copy of one.
public struct ListingReview: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case needsMoreInfo
        case rejected
        case takenDown
        /// Not a review at all: the card behind the listings lapsed and a
        /// monitor pulled them. Nobody decided anything about the watch, and
        /// nothing is waiting on a reviewer.
        case pausedForCard
    }

    public let outcome: Outcome
    public let title: String
    /// The reviewer's own words. Empty only for `pausedForCard`, which has no
    /// reviewer behind it.
    public let notes: String
    /// What to do about it, or nil when there is nothing the seller can do.
    public let next: String?
}

extension Listing {
    /// Our review of this listing, or nil when there is nothing to say.
    ///
    /// **Only the newest review event counts.** Matching the listing's status
    /// against any event that ever set that status reads a stale note back onto
    /// a listing that has moved on — sent back for photos, resubmitted,
    /// approved, and unlisted by the seller months later would show them the
    /// old photo note as though it were current. A review is superseded by
    /// whatever happened next, so an event that is not the latest is history.
    public var review: ListingReview? {
        if status == .pausedCard {
            return ListingReview(
                outcome: .pausedForCard,
                title: "We took this off the market",
                notes: "The credit card standing behind your listings has lapsed.",
                next: "Add a valid card and it goes back up automatically — no review, nothing to resubmit."
            )
        }
        guard let latest = reviewEvents?.first,
              let toStatus = latest.toStatus,
              toStatus == status.rawValue
        else { return nil }

        let notes = (latest.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return nil }

        switch status {
        case .draft:
            return ListingReview(
                outcome: .needsMoreInfo,
                title: "We need a little more before this goes live",
                notes: notes,
                next: "Change what it asks for and submit it again — it goes straight back into our review queue."
            )
        case .rejected:
            // Deliberately not "fix it and resubmit": a rejection is the
            // outcome for a watch Calibre will not carry, and the honest next
            // step is a person rather than another round of the queue.
            return ListingReview(
                outcome: .rejected,
                title: "We cannot put this listing live as it stands",
                notes: notes,
                next: "If you hold paperwork or provenance that speaks to this, contact support and we will go through it with you."
            )
        case .archived:
            return ListingReview(
                outcome: .takenDown,
                title: "This listing was taken down",
                notes: notes,
                next: "If you think this was a mistake, or you have fixed what it names, contact support and we will look again."
            )
        default:
            return nil
        }
    }
}
