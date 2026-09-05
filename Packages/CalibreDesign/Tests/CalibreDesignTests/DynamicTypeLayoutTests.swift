import SwiftUI
import XCTest

@testable import CalibreDesign

/// The two rules that decide how much width a listing card gets, and which
/// were the whole of the accessibility-size damage on the browse surfaces:
/// a grid that stayed two-up and a lane card frozen at 168pt.
///
/// At AX5 a 168pt-wide card leaves the eyebrow row roughly 140pt. The year is
/// pinned against compression and takes its width first, so the brand — which
/// gets what is left and may shrink to 0.65 — came out as a single letter:
/// "R  2002" where "ROLEX 2002" belongs. The same 140pt truncated the
/// reference to "Ref. RO30…", broke "$16,591.04" across two lines, and let
/// the condition pill, which does grow with the type, spill out over the
/// photograph.
@MainActor
final class DynamicTypeLayoutTests: XCTestCase {

    // MARK: - Grids collapse to one column

    func testGridStaysTwoUpBelowTheAccessibilityThreshold() {
        for size in [DynamicTypeSize.xSmall, .medium, .large, .xxxLarge] {
            XCTAssertEqual(
                calibreGridColumns(size).count, 2,
                "\(size) is not an accessibility size and must not move the shipped two-up grid."
            )
        }
    }

    func testGridCollapsesToOneColumnAtEveryAccessibilitySize() {
        let accessibilitySizes: [DynamicTypeSize] = [
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
        ]
        // Guard the collection first: an empty loop asserts nothing.
        XCTAssertEqual(accessibilitySizes.count, 5)
        for size in accessibilitySizes {
            XCTAssertTrue(size.isAccessibilitySize, "\(size) should be an accessibility size")
            XCTAssertEqual(
                calibreGridColumns(size).count, 1,
                "\(size) must give each card the full measure rather than a sliver of it."
            )
        }
    }

    func testGridSpacingSurvivesTheCollapse() {
        // The caller passes Space.l; a collapsed grid that dropped it would
        // change the margins of every card on the screen.
        XCTAssertEqual(calibreGridColumns(.accessibility5, spacing: Space.l).count, 1)
        XCTAssertEqual(calibreGridColumns(.large, spacing: Space.l).count, 2)
    }

    // MARK: - Lane cards scale, but not past the phone

    func testLaneCardKeepsItsShippedWidthAtTheDefaultSize() {
        // `@ScaledMetric` hands back exactly what it was given at .large, so
        // the default reader sees the 168pt card that shipped.
        XCTAssertEqual(calibreLaneCardWidth(168), 168)
    }

    func testLaneCardGrowsWithTheReadersTextSize() {
        XCTAssertEqual(calibreLaneCardWidth(210), 210)
        XCTAssertEqual(calibreLaneCardWidth(300), 300)
    }

    func testLaneCardIsCappedSoItNeverOutgrowsThePhone() {
        // 168 scaled by AX5 is roughly 520pt — wider than any iPhone. The cap
        // has to bite, and has to leave the next card peeking on a 375pt
        // screen with Space.margin either side (375 - 40 = 335 usable).
        let capped = calibreLaneCardWidth(520)
        XCTAssertEqual(capped, 320)
        XCTAssertLessThan(capped, 375 - 2 * Space.margin + Space.l)
    }

    func testLaneCardWidthIsNeverZeroOrNegative() {
        // A frame(width:) of 0 collapses the card to nothing; a negative one
        // is undefined. Neither is reachable through `@ScaledMetric`, but the
        // helper is public and the floor costs nothing.
        XCTAssertEqual(calibreLaneCardWidth(0), 1)
        XCTAssertEqual(calibreLaneCardWidth(-40), 1)
    }
}
