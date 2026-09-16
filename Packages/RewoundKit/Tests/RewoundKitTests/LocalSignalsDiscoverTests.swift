import Foundation
import XCTest
@testable import CalibreKit

final class LocalSignalsDiscoverTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "local-signals-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    @MainActor
    func testRemoveDiscoverPassDropsOnlyTheUndoneID() {
        let signals = LocalSignals(directory: directory)
        signals.recordDiscoverPass("a")
        signals.recordDiscoverPass("b")
        signals.recordDiscoverPass("c")

        signals.removeDiscoverPass("b")

        XCTAssertEqual(signals.discoverPassed, ["a", "c"])
        XCTAssertFalse(signals.hasPassed("b"))
        XCTAssertTrue(signals.hasPassed("a"))
    }

    @MainActor
    func testRemoveDiscoverPassPersistsAcrossReload() {
        let first = LocalSignals(directory: directory)
        first.recordDiscoverPass("a")
        first.recordDiscoverPass("b")
        first.removeDiscoverPass("a")

        let second = LocalSignals(directory: directory)
        XCTAssertEqual(second.discoverPassed, ["b"])
    }

    @MainActor
    func testRemoveDiscoverPassIgnoresUnknownID() {
        let signals = LocalSignals(directory: directory)
        signals.recordDiscoverPass("a")

        signals.removeDiscoverPass("never-passed")

        XCTAssertEqual(signals.discoverPassed, ["a"])
    }
}
