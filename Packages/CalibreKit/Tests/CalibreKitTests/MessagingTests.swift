import Foundation
import XCTest
@testable import CalibreKit

/// The client half of the messaging pass: reporting a push tap, and the guest
/// support thread surviving sign-in.
final class MessagingTests: XCTestCase {
    private func mockConfiguration() -> APIConfiguration {
        APIConfiguration(
            baseURL: URL(string: "https://mock.calibre.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
    }

    /// Isolated defaults so a test's guest token never touches the real app's.
    private func scratchDefaults() -> UserDefaults {
        let suite = "calibre.tests.\(UUID().uuidString)"
        // Only the suite name crosses into the teardown block: `UserDefaults`
        // is not Sendable, and the domain can be dropped by name.
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    // MARK: - Tap reporting

    /// `POST /account/notifications/{id}/opened` answers 204 with an empty
    /// body — the first endpoint in the API that does. The envelope decoder
    /// used to be the only path out, so this would have thrown a decoding
    /// error on every tap.
    @MainActor
    func testMarkOpenedPostsToTheOpenedEndpointAndAcceptsAnEmpty204() async throws {
        let seen = SeenRequest()
        MockURLProtocol.setHandler { request in
            seen.record(method: request.httpMethod, path: request.url?.path)
            return (204, Data())
        }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let store = ServerAlertsStore(client: client)
        try await store.markOpened(id: "n-1")

        XCTAssertEqual(seen.method, "POST")
        XCTAssertEqual(seen.path, "/account/notifications/n-1/opened")
    }

    /// The empty-body shortcut is for callers who asked for nothing. A caller
    /// expecting a payload and handed none must still fail, or a silent
    /// default would stand in for data the server never sent.
    func testEmptyBodyStillFailsWhenTheCallerExpectedAPayload() async throws {
        MockURLProtocol.setHandler { _ in (204, Data()) }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: CurrentUser = try await client.send(Endpoint(path: "/auth/me", requiresAuth: false))
            XCTFail("Expected a decoding failure")
        } catch APIError.decoding {
            // Expected.
        }
    }

    // MARK: - Guest support thread

    /// Signing in must not delete the guest thread pointer. The server merges
    /// a guest conversation into the account on signup (contracts §12.9), and
    /// a client that threw its token away first left the thread stranded
    /// whenever that merge did not run.
    @MainActor
    func testAuthenticatedLoadKeepsTheGuestToken() async throws {
        MockURLProtocol.setHandler { _ in (200, Data("{\"ok\": true, \"data\": null}".utf8)) }

        let defaults = scratchDefaults()
        defaults.set("guest-token-1", forKey: "calibre.support.guestToken")
        let store = SupportStore(client: APIClient(configuration: mockConfiguration(), auth: nil), defaults: defaults)

        _ = try await store.loadThread(authenticated: true)

        XCTAssertEqual(store.guestToken, "guest-token-1")
    }

    /// A cleared session drops the thread in memory but not the guest token:
    /// sessions clear for reasons that are not a person leaving — a rejected
    /// refresh token, a stray 401 — and a guest would lose the only pointer
    /// to their own conversation. Sign-out is what clears it.
    @MainActor
    func testResetDropsTheLoadedThreadButKeepsTheGuestToken() async throws {
        MockURLProtocol.setHandler { _ in (200, Data("{\"ok\": true, \"data\": null}".utf8)) }

        let defaults = scratchDefaults()
        defaults.set("guest-token-1", forKey: "calibre.support.guestToken")
        let store = SupportStore(client: APIClient(configuration: mockConfiguration(), auth: nil), defaults: defaults)
        _ = try await store.loadThread(authenticated: false)

        store.reset()

        XCTAssertNil(store.conversation)
        XCTAssertEqual(store.guestToken, "guest-token-1")
        store.forgetGuestToken()
        XCTAssertNil(store.guestToken)
    }
}

/// The one request the mock saw, readable from the test's actor. The handler
/// runs on URLSession's thread, so the fields are lock-guarded rather than
/// merely `nonisolated(unsafe)`.
private final class SeenRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var _method: String?
    private var _path: String?

    var method: String? { lock.withLock { _method } }
    var path: String? { lock.withLock { _path } }

    func record(method: String?, path: String?) {
        lock.withLock {
            _method = method
            _path = path
        }
    }
}
