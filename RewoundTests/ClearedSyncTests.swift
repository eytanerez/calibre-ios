import Foundation
import XCTest
@testable import Rewound

/// The silent push that says a notification was cleared somewhere else.
///
/// Eytan, 2026-09-09: *"notifications need to sync across devices if i clear
/// one then clear it across everything and remove the notification on their
/// phone."*
///
/// One payload serves both platforms, so **every value is a string** — FCM's
/// data map is string-to-string, and a client that expected a number here
/// would read nothing on Android and nothing on the day the two clients were
/// asked to agree.
@MainActor
final class ClearedSyncTests: XCTestCase {
    private func payload(_ extra: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var body: [AnyHashable: Any] = ["type": "notifications_cleared"]
        for (key, value) in extra { body[key] = value }
        return body
    }

    func testItReadsOneClearedNotification() throws {
        let sync = try XCTUnwrap(PushCoordinator.ClearedSync(userInfo: payload([
            "notification_ids": "a1",
            "cleared_all": "false",
            "remaining_count": "3",
        ])))

        XCTAssertEqual(sync.ids, ["a1"])
        XCTAssertFalse(sync.clearedAll)
        XCTAssertEqual(sync.remaining, 3)
    }

    /// Several rows travel comma-separated in one string, because that is the
    /// only shape both platforms' data maps carry.
    func testItSplitsSeveralIds() throws {
        let sync = try XCTUnwrap(PushCoordinator.ClearedSync(userInfo: payload([
            "notification_ids": "a1,b2,c3",
            "cleared_all": "false",
            "remaining_count": "0",
        ])))

        XCTAssertEqual(sync.ids, ["a1", "b2", "c3"])
    }

    /// Clear-all is the flag WITH an empty list, never a list of everything: a
    /// background APNs payload is capped at 4KB and an inbox of a few hundred
    /// UUIDs does not fit, so a listed clear-all would be cut short or dropped
    /// and leave cards on a phone with nothing coming to remove them.
    func testClearAllIsAFlagAndNotAList() throws {
        let sync = try XCTUnwrap(PushCoordinator.ClearedSync(userInfo: payload([
            "notification_ids": "",
            "cleared_all": "true",
            "remaining_count": "0",
        ])))

        XCTAssertTrue(sync.clearedAll)
        XCTAssertTrue(sync.ids.isEmpty)
        XCTAssertEqual(sync.remaining, 0)
    }

    /// `remaining_count` is a string beside an `aps.badge` that is an Int —
    /// Apple's own field, Apple's own type. They say the same thing, and
    /// either has to be readable, because a build that only understood one of
    /// them would leave the badge wrong on the platform that sent the other.
    func testTheBadgeAnswersWhenTheStringIsMissing() throws {
        let sync = try XCTUnwrap(PushCoordinator.ClearedSync(userInfo: payload([
            "notification_ids": "a1",
            "cleared_all": "false",
            "aps": ["content-available": 1, "badge": 5],
        ])))

        XCTAssertEqual(sync.remaining, 5)
    }

    /// Neither field. `remaining` is nil, and nil is the payload saying
    /// nothing — not saying zero.
    ///
    /// Zero here is the shape that wipes a badge and empties a bell on a phone
    /// holding a full inbox because two rows were cleared on another one. The
    /// backend sends both fields today, so this is a payload nothing produces
    /// yet: it is pinned because the day the payload loses one of them, the
    /// branch nothing took becomes the only branch, and it does it silently.
    func testAClearThatNamesNoCountSaysNothingAboutTheBadge() throws {
        let sync = try XCTUnwrap(PushCoordinator.ClearedSync(userInfo: payload([
            "notification_ids": "a1",
            "cleared_all": "false",
            "aps": ["content-available": 1],
        ])))

        XCTAssertEqual(sync.ids, ["a1"])
        XCTAssertNil(sync.remaining)
    }

    /// Everything else on the wire is a notification to show. Switching on
    /// `type` first is what keeps a clear from being drawn as one.
    func testAnOrdinaryPushIsNotAClear() {
        let alert: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Your offer was accepted", "body": "…"]],
            "category": "offers",
            "notification_id": "a1",
        ]

        XCTAssertNil(PushCoordinator.ClearedSync(userInfo: alert))
    }
}
