import Foundation

/// The sections Home can be made of, named once so the running order below
/// and the screen that draws it agree on what exists.
///
/// Some shelves the web page carries have no case here because this app does
/// not hold what they are made of. "Price drops on watches you've seen" needs
/// the price a listing carried when the reader last opened it, and "New since
/// your last visit" needs the moment they last left; the on-device signals
/// file keeps listing ids and nothing else. Drawing either from what is on
/// hand would mean inventing the comparison, so they are skipped rather than
/// approximated. The hero, the brand marquee, the budget bands, the market
/// pulse, "Why Rewound" and "How it works" are the site's furniture and have
/// no counterpart on the phone.
public enum HomeSection: Hashable, Sendable {
    /// The lane skeleton, drawn while the first load settles. Takes the
    /// ranked shelf's slot; the shelves that run their own queries still draw
    /// below it.
    case feedLoading
    /// The feed request failed. Takes the ranked shelf's slot; the shelves
    /// that run their own queries still draw below it.
    case feedUnavailable
    case nextStep
    /// `worth_a_look`, under Home's greeting.
    case watchesForYou
    /// On-device history, resolved to listings.
    case recentlyViewed
    case brands
    case popular
    /// Newest first. The guest page opens with this shelf and heads it "New
    /// this week" — the same query, in the slot the member's ranked shelf
    /// takes.
    case freshArrivals
    case savedSearches
    case bite
    case poll
    case collection
    case endOfFeed
}

/// Who the page is drawn for. Decided by the session, as the site decides it.
/// The feed's own `audience` says what the server composed, which is a
/// different question from which page to draw.
public enum HomeAudience: Sendable {
    case member
    case guest
}

/// Where the feed request stands.
public enum HomeFeedLoadState: Sendable {
    case loading
    case loaded
    case failed
}

/// Home's running order, top to bottom — the same skeleton the web page runs
/// for both audiences, so the two read as one page rather than as two.
///
/// The member's page is the guest's with more in it. The guest opens with a
/// shelf of the newest watches; the member opens with the ranked shelf under
/// their greeting. The day's Bite sits directly under that first row of
/// watches on both pages — above Recently viewed for a member, above the
/// brands for a guest — so the day's reading is met before the page settles
/// into shelves. Both go on to brands and what is popular, and the member's
/// personal modules follow before the feed terminator closes the page. A
/// section with nothing to show is absent, never an empty frame,
/// and a member-only section is not drawn for a guest even when the server
/// happened to send it: the guest feed carries a poll and a terminator, and
/// the guest page shows the Bite and browse-all-watches terminator while
/// keeping the poll private.
public enum HomeRunningOrder {
    /// `present` is the set of sections that have something to show. The two
    /// state-derived entries, the skeleton and the retry, are decided by `feed`
    /// and ignored in `present`.
    public static func sections(
        audience: HomeAudience,
        feed: HomeFeedLoadState,
        present: Set<HomeSection>
    ) -> [HomeSection] {
        // The skeleton and the retry take the first shelf's slot — the ranked
        // shelf's for a member, the newest shelf's for a guest — and the page
        // goes on below either, as it does on the site: the shelves that run
        // their own queries draw around a shelf that is still loading rather
        // than waiting behind it. A failed request is not an empty feed, and
        // for a guest it is not a quiet day either: the guest's Bite rides on
        // the same request, and a guest with no network would otherwise be
        // handed a page with nothing on it and no way to ask again. Both
        // audiences get the retry.
        //
        // The Bite keeps its slot relative to that first shelf: directly under
        // it, whichever shelf it is and whether the shelf is drawn, loading or
        // failed.
        let skeleton: [HomeSection] = switch audience {
        case .member:
            [
                .nextStep,
                .feedLoading,
                .feedUnavailable,
                .watchesForYou,
                .bite,
                .recentlyViewed,
                .brands,
                .popular,
                .freshArrivals,
                .savedSearches,
                .poll,
                .collection,
                .endOfFeed,
            ]
        case .guest:
            [
                .feedLoading,
                .feedUnavailable,
                .freshArrivals,
                .bite,
                .brands,
                .popular,
                .endOfFeed,
            ]
        }

        return skeleton.filter { section in
            switch section {
            case .feedLoading: feed == .loading
            case .feedUnavailable: feed == .failed
            default: present.contains(section)
            }
        }
    }
}
