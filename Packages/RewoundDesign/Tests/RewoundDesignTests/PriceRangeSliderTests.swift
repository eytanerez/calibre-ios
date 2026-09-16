import SwiftUI
import XCTest

@testable import CalibreDesign

/// The dual-thumb price filter could be dragged into a state it could not be
/// dragged out of.
///
/// Both thumbs are drawn at 28pt and grabbed at 44pt (`a11yExpandTarget`), so
/// their hit regions overlap while their circles still look separate, and the
/// later sibling — the maximum — won every touch in the overlap. Drag the
/// minimum up until `lowerDrag`'s `min(_, upperValue)` clamp parks it against
/// the maximum, and the minimum sits under a thumb that cannot help it:
/// dragging left is clamped at `lowerValue`, dragging right only widens while
/// the maximum is still below the bound.
///
/// Measured on the shipped build against the live $0–$128,100 filter: dragging
/// the minimum to the right edge left "$128,000 – $128,100+", and one drag to
/// the left moved the *maximum* down to $128,000 rather than the minimum. From
/// "$128,000 – $128,000" no drag separated them again; "Clear all" was the
/// only way out. The sheet's own tutorial promises "a low end and a high end
/// move independently".
///
/// Note what that repro rules out. At that price step the two values differ by
/// $100 while their centres differ by about a third of a point, so a rule
/// keyed on `lower >= upper` never fires on the state that actually traps
/// people. The test has to be about pixels.
///
/// `lowerThumbTakesTouch` is the rule that now sets the z-order, and SwiftUI
/// hit-tests in reverse z-order, so it decides which thumb a finger lands on.
final class PriceRangeSliderTests: XCTestCase {
    private let bounds = 0.0...128_100.0
    private let grab: CGFloat = Space.touchTarget / 2  // 22pt

    /// Where a value's thumb centre lands on a 360pt track, matching the
    /// view's own `x(for:width:)`.
    private func x(_ value: Double, width: CGFloat = 360, thumb: CGFloat = 28) -> CGFloat {
        let usable = width - thumb
        let t = (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
        return thumb / 2 + usable * CGFloat(t)
    }

    private func lowerWins(_ lower: Double, _ upper: Double) -> Bool {
        PriceRangeSlider.lowerThumbTakesTouch(
            lowerX: x(lower),
            upperX: x(upper),
            grabRadius: grab,
            lower: lower,
            upper: upper,
            in: bounds
        )
    }

    // MARK: - The measured repro

    func testTheMinimumTakesTheTouchInTheStateMeasuredOnDevice() {
        // "$128,000 – $128,100+" — one price step apart in value, a third of a
        // point apart on screen. This is the state the shipped build could not
        // escape, and the one a value-equality rule would miss.
        XCTAssertLessThan(x(128_100) - x(128_000), grab, "The two thumbs must actually overlap here.")
        XCTAssertNotEqual(128_000.0, 128_100.0, "…while their values are not equal.")
        XCTAssertTrue(lowerWins(128_000, 128_100))
    }

    func testTheMinimumTakesTheTouchOnceBothAreParkedAtTheSameFigure() {
        XCTAssertTrue(lowerWins(128_000, 128_000))
        XCTAssertTrue(lowerWins(128_100, 128_100))
    }

    // MARK: - Separated thumbs keep the shipped order

    func testMaximumKeepsTheTouchForAnOrdinarySeparatedRange() {
        XCTAssertGreaterThan(x(38_000) - x(5_200), grab, "These thumbs are nowhere near each other.")
        XCTAssertFalse(lowerWins(5_200, 38_000))
    }

    func testMaximumKeepsTheTouchForTheEverydayOpenEndedRange() {
        // "$5,200 and up": the maximum is at the bound but the minimum is far
        // from it and perfectly reachable.
        XCTAssertFalse(lowerWins(5_200, 128_100))
    }

    func testMaximumKeepsTheTouchForTheUntouchedFullRange() {
        XCTAssertFalse(lowerWins(0, 128_100))
    }

    func testSeparationAloneDecidesIt_evenHighInTheRange() {
        // Both thumbs high up, where the minimum has far more room — but they
        // are apart on screen, so nothing is covered and nothing is swapped.
        XCTAssertGreaterThan(x(128_100) - x(100_000), grab)
        XCTAssertFalse(lowerWins(100_000, 128_100))
    }

    // MARK: - Overlapping: the thumb with room wins, wherever it is

    func testMaximumTakesTheTouchWhenThePairIsParkedOnTheFloor() {
        // Mirror image: the maximum dragged down onto the minimum at $0. The
        // maximum is the one with room, so it keeps the touch.
        XCTAssertFalse(lowerWins(0, 0))
        XCTAssertFalse(lowerWins(0, 320))
    }

    func testTheThumbWithMoreRoomWinsAcrossTheWholeRange() {
        let midpoint = (bounds.lowerBound + bounds.upperBound) / 2
        let samples = stride(from: 0.0, through: 128_100.0, by: 6_405.0).map { $0 }
        // Guard the collection: a strict assertion over an empty sweep is
        // vacuously green.
        XCTAssertEqual(samples.count, 21)

        for value in samples {
            XCTAssertEqual(
                lowerWins(value, value), value > midpoint,
                "At \(value) the coincident pair should hand the touch to whichever thumb has room."
            )
        }
    }

    // MARK: - Degenerate input

    func testAZeroWidthRangeDoesNotSwap() {
        // Nothing can move either way; the shipped order is as good as any.
        XCTAssertFalse(
            PriceRangeSlider.lowerThumbTakesTouch(
                lowerX: 14, upperX: 14, grabRadius: grab,
                lower: 100, upper: 100, in: 100...100
            )
        )
    }

    func testTheRuleReadsPositionsNotValues() {
        // Identical values, but told they are far apart on screen: no swap.
        // This is the assertion that fails if anyone re-writes the guard back
        // into value space.
        XCTAssertFalse(
            PriceRangeSlider.lowerThumbTakesTouch(
                lowerX: 10, upperX: 300, grabRadius: grab,
                lower: 128_000, upper: 128_000, in: bounds
            )
        )
    }
}
