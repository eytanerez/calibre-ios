import XCTest

@testable import Rewound

/// The connection monitor's three facts, and when each changes.
///
/// The bar and every failed load read these, so a transition counted twice
/// would retry every visible failure twice, and one missed would leave a page
/// that failed offline sitting there after the connection came back.
@MainActor
final class ConnectivityTests: XCTestCase {
    func testLosingAndRegainingTheConnectionCountsOneReconnect() {
        let connectivity = Connectivity()
        XCTAssertTrue(connectivity.isOnline, "starts online, so the bar never flashes at launch")

        connectivity.update(online: false)
        XCTAssertFalse(connectivity.isOnline)
        XCTAssertEqual(connectivity.reconnects, 0)
        XCTAssertFalse(connectivity.justReconnected)

        connectivity.update(online: true)
        XCTAssertTrue(connectivity.isOnline)
        XCTAssertEqual(connectivity.reconnects, 1)
        XCTAssertTrue(connectivity.justReconnected)
    }

    func testARepeatedReportOfTheSameStateChangesNothing() {
        let connectivity = Connectivity()
        connectivity.update(online: true)
        connectivity.update(online: true)
        XCTAssertEqual(connectivity.reconnects, 0, "online to online is not a reconnect")

        connectivity.update(online: false)
        connectivity.update(online: false)
        connectivity.update(online: true)
        XCTAssertEqual(connectivity.reconnects, 1)
    }

    func testGoingOfflineAgainClearsTheBackOnlineNote() {
        let connectivity = Connectivity()
        connectivity.update(online: false)
        connectivity.update(online: true)
        XCTAssertTrue(connectivity.justReconnected)
        connectivity.update(online: false)
        XCTAssertFalse(connectivity.justReconnected, "offline wins over a stale 'back online'")
    }
}
