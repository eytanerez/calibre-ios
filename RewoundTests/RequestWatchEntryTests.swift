import RewoundKit
import SwiftUI
import XCTest
@testable import Rewound

/// "Request a watch" from outside the Requests screen: the band on Home, the
/// capsule on the results grid, and what the form starts with when it opens
/// from a grid that already knows something about the watch.
final class RequestWatchEntryTests: XCTestCase {

    // MARK: - Home placement

    func testTheBandSitsDirectlyAboveTheEndOfTheFeed() {
        let slots = HomePageSlot.arrange([.freshArrivals, .bite, .brands, .popular, .endOfFeed])

        XCTAssertEqual(
            slots,
            [
                .section(.freshArrivals), .section(.bite), .section(.brands), .section(.popular),
                .requestWatch, .section(.endOfFeed),
            ]
        )
    }

    func testTheBandStillShowsWhenTheServerSentNoEndOfFeed() {
        let slots = HomePageSlot.arrange([.watchesForYou, .brands, .popular])

        XCTAssertEqual(slots.last, .requestWatch, "no terminator from the server took the band with it")
    }

    func testTheBandWaitsWhileTheFeedIsLoading() {
        XCTAssertEqual(HomePageSlot.arrange([.feedLoading]), [.section(.feedLoading)])
    }

    func testAFailedFeedWithNothingElseIsTheRetryAlone() {
        XCTAssertEqual(HomePageSlot.arrange([.feedUnavailable]), [.section(.feedUnavailable)])
    }

    /// A failed feed is not an empty page when the shelves that run their own
    /// queries still drew; the band closes that page as it closes any other.
    func testAFailedFeedWithShelvesStillGetsTheBand() {
        let slots = HomePageSlot.arrange([.feedUnavailable, .brands, .popular])

        XCTAssertEqual(slots.last, .requestWatch)
        XCTAssertEqual(slots.filter { $0 == .requestWatch }.count, 1)
    }

    // MARK: - The capsule's scroll zones

    private let far: CGFloat = 5_000

    func testTheCapsuleAppearsPastAboutAScreenAndHidesNearTheTop() {
        let viewport: CGFloat = 700

        XCTAssertEqual(RequestPromptZone.zone(offset: 0, viewport: viewport, distanceToEnd: far), .top)
        XCTAssertEqual(RequestPromptZone.zone(offset: 400, viewport: viewport, distanceToEnd: far), .between)
        XCTAssertEqual(RequestPromptZone.zone(offset: 700, viewport: viewport, distanceToEnd: far), .deep)

        XCTAssertTrue(RequestPromptZone.deep.shows(whenCurrently: false))
        XCTAssertFalse(RequestPromptZone.top.shows(whenCurrently: true))
    }

    /// A brand with six watches never scrolls a whole screen; its end is
    /// where the capsule comes in instead.
    func testTheEndOfAShortGridShowsTheCapsule() {
        XCTAssertEqual(RequestPromptZone.zone(offset: 350, viewport: 700, distanceToEnd: 0), .deep)
    }

    /// A grid that fits on the screen has nothing to scroll past: its end is
    /// already in view.
    func testAGridThatFitsShowsTheCapsuleAtOnce() {
        XCTAssertEqual(RequestPromptZone.zone(offset: 0, viewport: 700, distanceToEnd: -200), .deep)
    }

    /// Between the two lines the capsule keeps what it was doing, so scrolling
    /// around a single threshold cannot make it flicker.
    func testBetweenTheLinesTheCapsuleKeepsItsState() {
        XCTAssertTrue(RequestPromptZone.between.shows(whenCurrently: true))
        XCTAssertFalse(RequestPromptZone.between.shows(whenCurrently: false))
    }

    /// The numbers a six-watch brand page actually reported on an iPhone 17
    /// Pro: `containerSize` is only the part between the navigation bar and
    /// the brand rail over the tab bar, and `contentOffset` rests at minus the
    /// top inset. Measured against the whole frame, the end sat 251pt below
    /// where the page can scroll, and the capsule never came.
    func testTheBrandPageGeometryReachesItsEnd() {
        func geometry(offset: CGFloat) -> ScrollGeometry {
            ScrollGeometry(
                contentOffset: CGPoint(x: 0, y: offset),
                contentSize: CGSize(width: 402, height: 1_098),
                contentInsets: EdgeInsets(top: 116, leading: 0, bottom: 135, trailing: 0),
                containerSize: CGSize(width: 402, height: 623)
            )
        }

        XCTAssertEqual(RequestPromptZone.zone(geometry(offset: -116)), .top, "at rest at the top")
        XCTAssertEqual(RequestPromptZone.zone(geometry(offset: 359)), .deep, "at rest at the end")
    }

    func testAnUnmeasuredViewportIsTheTop() {
        XCTAssertEqual(RequestPromptZone.zone(offset: 500, viewport: 0, distanceToEnd: 0), .top)
    }

    // MARK: - Prefill

    private let brands = ["Rolex", "Omega", "Grand Seiko", "Seiko", "A. Lange & Söhne", "Patek Philippe"]

    func testABrandPageFillsTheBrand() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(brand: "Omega"),
            lockedBrand: "Omega",
            knownBrands: brands
        )

        XCTAssertEqual(prefill, WatchRequestPrefill(brand: "Omega"))
    }

    func testTheBrandAndModelFiltersCarryOver() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(brand: "Rolex", model: "Submariner"),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertEqual(prefill, WatchRequestPrefill(brand: "Rolex", model: "Submariner"))
    }

    func testASearchIsSplitIntoBrandAndModel() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "  rolex   daytona "),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertEqual(prefill, WatchRequestPrefill(brand: "Rolex", model: "daytona"))
    }

    func testTheLongestBrandWins() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "Grand Seiko Snowflake"),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertEqual(prefill.brand, "Grand Seiko")
        XCTAssertEqual(prefill.model, "Snowflake")
    }

    func testABrandMatchesWholeWordsOnly() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "Omegamatic"),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertNil(prefill.brand)
        XCTAssertEqual(prefill.model, "Omegamatic")
    }

    func testAccentsDoNotStopABrandMatching() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "a. lange & sohne datograph"),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertEqual(prefill.brand, "A. Lange & Söhne")
        XCTAssertEqual(prefill.model, "datograph")
    }

    func testAReferenceSearchFillsTheReference() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "Rolex 116610ln"),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertEqual(prefill, WatchRequestPrefill(brand: "Rolex", reference: "116610LN"))
    }

    func testASizeIsNotAReference() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "40mm"),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertNil(prefill.reference)
        XCTAssertEqual(prefill.model, "40mm")
    }

    /// On a brand page the search is inside that brand, so a search that
    /// repeats the brand's name does not put it in the model as well.
    func testASearchRepeatingTheLockedBrandIsNotDoubled() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "Rolex GMT-Master II", brand: "Rolex"),
            lockedBrand: "Rolex",
            knownBrands: brands
        )

        XCTAssertEqual(prefill, WatchRequestPrefill(brand: "Rolex", model: "GMT-Master II"))
    }

    func testWithoutTheCatalogASearchStaysWhole() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(search: "Rolex Daytona"),
            lockedBrand: nil,
            knownBrands: []
        )

        XCTAssertEqual(prefill, WatchRequestPrefill(model: "Rolex Daytona"))
    }

    func testAnUnfilteredGridStartsEmpty() {
        let prefill = WatchRequestPrefill.browsing(
            filters: BrowseFilters(sort: .createdDesc),
            lockedBrand: nil,
            knownBrands: brands
        )

        XCTAssertTrue(prefill.isEmpty)
    }
}
