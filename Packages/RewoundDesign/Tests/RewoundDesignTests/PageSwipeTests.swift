import CoreGraphics
import XCTest
@testable import RewoundDesign

final class PageSwipeTests: XCTestCase {
    func testDiagonalHorizontalIntentLocksWhileVerticalMotionDoesNot() {
        XCTAssertTrue(PageSwipeDecision.isHorizontal(CGPoint(x: -80, y: 24)))
        XCTAssertFalse(PageSwipeDecision.isHorizontal(CGPoint(x: 24, y: 80)))
        XCTAssertFalse(PageSwipeDecision.isHorizontal(CGPoint(x: 30, y: 30)))
    }

    func testShortDragsDoNotAccidentallySwitchPages() {
        XCTAssertNil(PageSwipeDecision.destination(index: 1, count: 3, translation: 12, velocity: 800))
        XCTAssertNil(PageSwipeDecision.destination(index: 1, count: 3, translation: -35, velocity: -150))
    }

    func testLongSwipesAndShortFastFlicksMoveOnlyOnePage() {
        XCTAssertEqual(PageSwipeDecision.destination(index: 1, count: 5, translation: -250, velocity: -900), 2)
        XCTAssertEqual(PageSwipeDecision.destination(index: 1, count: 5, translation: 25, velocity: 600), 0)
    }

    func testEndPagesDoNotWrapOrProduceAHapticChange() {
        XCTAssertNil(PageSwipeDecision.destination(index: 0, count: 3, translation: 80, velocity: 500))
        XCTAssertNil(PageSwipeDecision.destination(index: 2, count: 3, translation: -80, velocity: -500))
    }
}
