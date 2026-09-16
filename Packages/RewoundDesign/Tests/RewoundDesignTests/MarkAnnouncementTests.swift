import XCTest

@testable import CalibreDesign

/// A mark announces a fact once per app session and then stands as it.
///
/// `trigger:` covers the re-render half of that — a sixty-second refetch must
/// not re-seal a parcel — and this covers the other half: a screen pushed
/// twice in one session is two mounts, and the second one is not news.
@MainActor
final class MarkAnnouncementTests: XCTestCase {

    private func key(_ suffix: String = #function) -> String {
        // Session state outlives a test, so each case works on its own key
        // rather than on a shared one it would have to reset.
        "test:\(suffix)"
    }

    func testAFactIsAnnouncedOnceAndThenStandsStill() {
        let fact = key()
        XCTAssertTrue(MarkAnnouncements.shared.claim(fact))
        XCTAssertFalse(MarkAnnouncements.shared.claim(fact))
        XCTAssertFalse(MarkAnnouncements.shared.claim(fact))
    }

    /// The key is the event. Two different events both get their moment, which
    /// is what makes an order reaching `to_buyer` announce itself even though
    /// the same screen already announced `to_auth`.
    func testDifferentFactsEachGetTheirMoment() {
        let first = key() + ":to_auth"
        let second = key() + ":to_buyer"
        XCTAssertTrue(MarkAnnouncements.shared.claim(first))
        XCTAssertTrue(MarkAnnouncements.shared.claim(second))
        XCTAssertFalse(MarkAnnouncements.shared.claim(first))
    }

    /// A nil key is a gate that is not met — nothing is announced, and nothing
    /// is written down that would suppress the announcement later.
    func testAnUnmetGateAnnouncesNothingAndRecordsNothing() {
        XCTAssertFalse(MarkAnnouncements.shared.claim(nil))
        XCTAssertFalse(MarkAnnouncements.shared.claim(nil))

        let fact = key()
        XCTAssertTrue(MarkAnnouncements.shared.claim(fact), "the real fact still gets its one moment")
    }
}
