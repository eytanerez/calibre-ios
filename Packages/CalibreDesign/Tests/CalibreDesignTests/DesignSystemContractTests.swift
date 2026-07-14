import XCTest

@testable import CalibreDesign

final class DesignSystemContractTests: XCTestCase {
    func testSpacingAndRadiusScalesStayOrdered() {
        XCTAssertLessThan(Space.xs, Space.s)
        XCTAssertLessThan(Space.s, Space.m)
        XCTAssertLessThan(Space.m, Space.l)
        XCTAssertLessThan(Space.l, Space.xl)
        XCTAssertLessThan(Space.xl, Space.xxl)

        XCTAssertLessThan(Radius.control, Radius.card)
        XCTAssertLessThan(Radius.card, Radius.overlay)
        XCTAssertGreaterThanOrEqual(Space.touchTarget, 44)
    }

    func testMotionCascadeCapsItsTail() {
        XCTAssertEqual(Motion.cascadeDelay(index: 0), 0)
        XCTAssertEqual(Motion.cascadeDelay(index: 7), 0.21, accuracy: 0.000_001)
        XCTAssertEqual(Motion.cascadeDelay(index: 20), 0.21, accuracy: 0.000_001)
    }
}
