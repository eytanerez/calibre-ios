import XCTest
@testable import Calibre

@MainActor
final class PushRouteTests: XCTestCase {
    func testBackendMessageAndAccountRoutesResolve() {
        XCTAssertEqual(PushCoordinator.route(from: "thread/thread-1"), .messageThread("thread-1"))
        XCTAssertEqual(PushCoordinator.route(from: "messages"), .messages)
        XCTAssertEqual(PushCoordinator.route(from: "account/settings"), .accountSettings)
    }

    func testUnknownRoutesStayUnresolved() {
        XCTAssertNil(PushCoordinator.route(from: "future/place"))
    }
}
