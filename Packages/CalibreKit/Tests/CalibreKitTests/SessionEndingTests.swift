import Foundation
import XCTest
@testable import CalibreKit

/// The two ways a session ends, and the one difference that matters.
///
/// `onSessionCleared` fires for both, because both must drop the cached
/// account state. `onSessionExpired` fires only for the ending the member did
/// not ask for, because only that one has to be announced: the app opens on
/// the market now, so a member whose token was rejected lands in the tab
/// shell as a guest with an empty Vault and no explanation — which reads as a
/// lost account rather than a signed-out one. Getting this backwards would
/// either say nothing when it must, or tell someone who just tapped Sign Out
/// that they were signed out.
final class SessionEndingTests: XCTestCase {
    @MainActor
    func testSigningOutClearsWithoutAnnouncingAnything() async {
        MockURLProtocol.setHandler { _ in
            (200, Data("{\"ok\": true, \"data\": {}}".utf8))
        }
        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "access-1", refreshToken: "refresh-1"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)
        let cleared = HitCounter()
        let expired = HitCounter()
        session.onSessionCleared = { cleared.increment() }
        session.onSessionExpired = { expired.increment() }

        await session.logout()

        XCTAssertEqual(cleared.value, 1, "cached account state is dropped either way")
        XCTAssertEqual(expired.value, 0, "the member asked for this — telling them is noise")
        XCTAssertFalse(session.isAuthenticated)
    }

    /// A refresh token the server rejects outright: the one ending nobody
    /// chose, and the one that has to say so.
    @MainActor
    func testRejectedRefreshTokenAnnouncesTheEnding() async {
        MockURLProtocol.setHandler { request in
            if request.url?.path == "/auth/refresh" {
                return (401, Data("{\"ok\": false, \"error\": \"Invalid refresh token\"}".utf8))
            }
            return (401, Data("{\"ok\": false, \"error\": \"expired\"}".utf8))
        }
        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "stale", refreshToken: "invalid"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)
        let cleared = HitCounter()
        let expired = HitCounter()
        session.onSessionCleared = { cleared.increment() }
        session.onSessionExpired = { expired.increment() }

        await session.bootstrap()

        XCTAssertEqual(cleared.value, 1)
        XCTAssertEqual(expired.value, 1, "an ending the member did not ask for has to be said out loud")
        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(store.load())
    }

    /// The failure mode this whole seam exists to avoid the *other* way: a
    /// network that is merely down must not end the session at all, so it
    /// must not announce one either.
    @MainActor
    func testATransientFailureEndsNothingAndSaysNothing() async {
        MockURLProtocol.setHandler { _ in
            (503, Data("{\"ok\": false, \"error\": \"upstream unavailable\"}".utf8))
        }
        let pair = TokenPair(accessToken: "access-1", refreshToken: "refresh-1")
        let store = MemoryTokenStore(tokens: pair)
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)
        let cleared = HitCounter()
        let expired = HitCounter()
        session.onSessionCleared = { cleared.increment() }
        session.onSessionExpired = { expired.increment() }

        await session.bootstrap()

        XCTAssertEqual(cleared.value, 0)
        XCTAssertEqual(expired.value, 0)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(store.load(), pair)
    }
}
