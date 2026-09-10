import Foundation
import XCTest
@testable import CalibreKit

/// Closing the "this one sold" banner.
///
/// A dismissal answers the notices that were on screen when the person closed
/// it. It has to be remembered per notice and outside the banner: the banner is
/// destroyed by an ordinary tab switch, and a notice whose acknowledgement
/// never reached the server is still pending on the store afterwards.
final class ListingNoticeDismissalTests: XCTestCase {
    /// Serves `/listing-notices` from whatever ids are handed in, and fails
    /// the acknowledgement — the case the dismissal has to survive, because a
    /// successful ack removes the row and settles the question by itself.
    @MainActor
    private func storeWithPendingNotices(_ ids: [String]) async throws -> CommerceStore {
        let notices = ids.map { id in
            """
            {"id": "\(id)", "listing_id": "l-\(id)", "reason": "sold",
             "source": "saved", "title": "A watch", "currency": "USD"}
            """
        }
        MockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/listing-notices":
                return (200, Data("""
                {"ok": true, "data": {"notices": [\(notices.joined(separator: ","))], "has_more": false}}
                """.utf8))
            default:
                return (500, Data("{\"ok\": false, \"error\": \"boom\"}".utf8))
            }
        }
        let store = CommerceStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        _ = try await store.loadListingNotices()
        return store
    }

    @MainActor
    func testDismissingHidesOnlyTheNoticesThatWereOnScreen() async throws {
        let store = try await storeWithPendingNotices(["n1"])
        XCTAssertEqual(store.showableListingNotices.map(\.id), ["n1"])

        store.dismissListingNotices(ids: ["n1"])
        XCTAssertTrue(
            store.showableListingNotices.isEmpty,
            "a notice the person closed must not be offered to the banner again"
        )
    }

    /// The defect this replaced: one close silenced every sold notice that
    /// arrived afterwards, for the life of the tab.
    @MainActor
    func testANoticeArrivingAfterADismissalIsStillShown() async throws {
        let store = try await storeWithPendingNotices(["n1"])
        store.dismissListingNotices(ids: ["n1"])

        // The store refetches when Saved appears, and a second watch has sold.
        MockURLProtocol.setHandler { _ in
            (200, Data("""
            {"ok": true, "data": {"notices": [
              {"id": "n1", "listing_id": "l-n1", "reason": "sold", "source": "saved", "currency": "USD"},
              {"id": "n2", "listing_id": "l-n2", "reason": "sold", "source": "saved", "currency": "USD"}
            ], "has_more": false}}
            """.utf8))
        }
        _ = try await store.loadListingNotices()

        XCTAssertEqual(
            store.showableListingNotices.map(\.id), ["n2"],
            "the closed notice stays closed and the new one is shown"
        )
    }

    /// The other half: the dismissal has to outlive the banner, which a tab
    /// switch tears down. Nothing here is view state, so it does.
    @MainActor
    func testDismissalSurvivesARefetchThatStillCarriesTheNotice() async throws {
        let store = try await storeWithPendingNotices(["n1"])
        store.dismissListingNotices(ids: ["n1"])

        // The acknowledgement failed, so the server still reports it pending.
        _ = try await store.loadListingNotices()
        XCTAssertEqual(store.listingNotices.map(\.id), ["n1"])
        XCTAssertTrue(
            store.showableListingNotices.isEmpty,
            "an un-acknowledged notice must not come back after it was closed"
        )
    }

    /// Dismissals belong to a session, like everything else the store caches.
    @MainActor
    func testResetForgetsDismissals() async throws {
        let store = try await storeWithPendingNotices(["n1"])
        store.dismissListingNotices(ids: ["n1"])

        store.reset()
        XCTAssertTrue(store.dismissedNoticeIDs.isEmpty)

        _ = try await store.loadListingNotices()
        XCTAssertEqual(
            store.showableListingNotices.map(\.id), ["n1"],
            "the next account starts with nothing dismissed"
        )
    }
}
