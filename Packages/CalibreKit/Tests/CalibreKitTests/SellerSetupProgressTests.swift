import XCTest
@testable import CalibreKit

/// The crown beside seller setup winds when a step finishes, and never
/// backwards.
final class SellerSetupProgressTests: XCTestCase {

    func testNothingFinishedDrawsNothing() {
        var progress = SellerSetupProgress()
        XCTAssertNil(progress.markKey)
        progress.record(stepsDone: 0)
        XCTAssertNil(progress.markKey)
    }

    func testTheKeyIsTheCountAStepFinishedAt() {
        var progress = SellerSetupProgress()
        progress.record(stepsDone: 1)
        XCTAssertEqual(progress.markKey, "seller-setup:1")
        progress.record(stepsDone: 2)
        XCTAssertEqual(progress.markKey, "seller-setup:2")
    }

    /// A refetch that reports fewer finished steps — a cached read, a card
    /// that lapsed — leaves the crown where it stood rather than unwinding it
    /// or taking it off the screen.
    func testThePeakNeverWindsBack() {
        var progress = SellerSetupProgress()
        progress.record(stepsDone: 2)
        progress.record(stepsDone: 1)
        XCTAssertEqual(progress.peakStepsDone, 2)
        XCTAssertEqual(progress.markKey, "seller-setup:2")
        progress.record(stepsDone: 0)
        XCTAssertEqual(progress.markKey, "seller-setup:2")
    }
}
