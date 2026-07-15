import Foundation
import XCTest
@testable import CalibreKit

/// `CommerceStore.reset()` and the `sessionGeneration` guard it bumps —
/// cross-account/session isolation for cart/watchlist/addresses. A
/// signed-out (or newly signed-in) session must never be repopulated by a
/// request that was still in flight under the previous one.
final class CommerceStoreSessionTests: XCTestCase {
    private func mockConfiguration() -> APIConfiguration {
        APIConfiguration(
            baseURL: URL(string: "https://mock.calibre.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
    }

    @MainActor
    func testResetClearsEveryCachedCollection() async throws {
        MockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/cart":
                return (200, Data("""
                {"ok": true, "data": [{"id": "c1", "listing_id": "l1"}]}
                """.utf8))
            case "/watchlist":
                return (200, Data("""
                {"ok": true, "data": [{"id": "w1", "listing_id": "l1"}]}
                """.utf8))
            default:
                return (404, Data("{\"ok\": false, \"error\": \"not found\"}".utf8))
            }
        }
        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let commerce = CommerceStore(client: client)
        _ = try await commerce.loadCart()
        _ = try await commerce.loadWatchlist()
        XCTAssertFalse(commerce.cart.isEmpty)
        XCTAssertFalse(commerce.watchlist.isEmpty)
        XCTAssertFalse(commerce.watchedListingIDs.isEmpty)

        commerce.reset()

        XCTAssertTrue(commerce.cart.isEmpty)
        XCTAssertTrue(commerce.watchlist.isEmpty)
        XCTAssertTrue(commerce.watchedListingIDs.isEmpty)
        XCTAssertTrue(commerce.addresses.isEmpty)
    }

    /// The core race: account A's `loadCart()` is still in flight (a slow
    /// response) when the session ends. `reset()` runs, then A's response
    /// finally arrives — it must not repopulate `cart`.
    @MainActor
    func testDelayedResponseAfterResetDoesNotRepopulateCart() async throws {
        MockURLProtocol.setHandler { _ in
            // Deterministic stand-in for "still in flight when the session
            // changed" — same technique as APIClientTests'
            // testAuthSessionRefreshIsSingleFlight (blocks the loading
            // thread, not the test's).
            Thread.sleep(forTimeInterval: 0.15)
            return (200, Data("""
            {"ok": true, "data": [{"id": "stale-cart-item", "listing_id": "l1"}]}
            """.utf8))
        }
        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let commerce = CommerceStore(client: client)

        let staleLoad = Task { try await commerce.loadCart() }
        try await Task.sleep(for: .milliseconds(30)) // let the request actually start
        commerce.reset()

        _ = try await staleLoad.value
        XCTAssertTrue(commerce.cart.isEmpty, "a response landing after reset() must not repopulate cart")
    }

    /// Same race for `toggleWatch`'s revert path: the optimistic flip
    /// happens, the session ends before the network call resolves, and the
    /// call fails — the revert must not write into the new session either.
    @MainActor
    func testToggleWatchRevertAfterResetDoesNotWriteStaleState() async throws {
        MockURLProtocol.setHandler { _ in
            Thread.sleep(forTimeInterval: 0.15)
            return (500, Data("{\"ok\": false, \"error\": \"boom\"}".utf8))
        }
        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let commerce = CommerceStore(client: client)

        let staleToggle = Task { try? await commerce.toggleWatch(listingID: "l1") }
        try await Task.sleep(for: .milliseconds(30))
        commerce.reset()

        _ = await staleToggle.value
        XCTAssertTrue(commerce.watchlist.isEmpty)
        XCTAssertTrue(commerce.watchedListingIDs.isEmpty)
    }

    /// `AuthSession.onSessionCleared` — the real hook `AppServices` wires to
    /// `CommerceStore.reset()` — must fire on a manual sign-out.
    @MainActor
    func testAuthSessionFiresOnSessionClearedOnLogout() async throws {
        MockURLProtocol.setHandler { _ in
            (200, Data("{\"ok\": true, \"data\": {}}".utf8))
        }
        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "access-1", refreshToken: "refresh-1"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)
        let firedCount = HitCounter()
        session.onSessionCleared = { firedCount.increment() }

        await session.logout()

        XCTAssertEqual(firedCount.value, 1)
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(store.load())
    }
}
