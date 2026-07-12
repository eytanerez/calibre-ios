import Foundation
import XCTest
@testable import CalibreKit

// MARK: - URLProtocol mock

/// Routes every request through a swappable handler. Installed via
/// `APIConfiguration.protocolClasses`, so both APIClient's session and
/// AuthSession's internal sessions hit it.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?

    static func setHandler(_ handler: @escaping Handler) {
        lock.withLock { _handler = handler }
    }

    private static func currentHandler() -> Handler? {
        lock.withLock { _handler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.currentHandler(), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func mockConfiguration() -> APIConfiguration {
    APIConfiguration(
        baseURL: URL(string: "https://mock.calibre.test")!,
        protocolClasses: [MockURLProtocol.self]
    )
}

// MARK: - Auth stub

/// AuthProviding stub honoring the protocol's single-flight contract, with an
/// observable count of *actual* refresh executions.
final class SingleFlightAuthStub: AuthProviding {
    actor State {
        var token = "stale"
        var refreshCount = 0
        private var inFlight: Task<Bool, Never>?

        func currentToken() -> String { token }

        func refresh() async -> Bool {
            // A straggler whose 401 lands after the refresh finished must not
            // start a second one.
            if token == "fresh" { return true }
            if let inFlight {
                return await inFlight.value
            }
            let task = Task<Bool, Never> {
                // Long enough that all 20 callers pile up behind one refresh.
                try? await Task.sleep(for: .milliseconds(150))
                // Flip the token *inside* the task so awaiting callers only
                // resume once the fresh token is visible.
                self.token = "fresh"
                return true
            }
            inFlight = task
            refreshCount += 1
            let result = await task.value
            inFlight = nil
            return result
        }
    }

    let state = State()

    func authHeader() async -> (name: String, value: String)? {
        ("Authorization", "Bearer \(await state.currentToken())")
    }

    func refreshAfterUnauthorized() async -> Bool {
        await state.refresh()
    }
}

// MARK: - Tests

final class APIClientTests: XCTestCase {

    /// A real `{ok:false}` error body (as /auth/me returns unauthenticated)
    /// must surface as APIError.server with the backend's message. Inlined —
    /// the auth-me fixture is now recorded signed-in, so it's a success body.
    func testEnvelopeErrorDecodesFromRecordedFixture() async throws {
        let errorBody = Data("""
        {"ok": false, "error": "Authentication credentials were not provided"}
        """.utf8)
        MockURLProtocol.setHandler { _ in (401, errorBody) }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: CurrentUser = try await client.send(Endpoint(path: "/auth/me", requiresAuth: false))
            XCTFail("Expected APIError.server")
        } catch let APIError.server(message, code, status, _) {
            XCTAssertEqual(message, "Authentication credentials were not provided")
            XCTAssertNil(code)
            XCTAssertEqual(status, 401)
        }
    }

    func testEnvelopeSuccessDecodesPayload() async throws {
        let body = Data("""
        {"ok": true, "data": {"id": "u1", "email": "a@b.c", "username": "tester", "roles": ["member"]}}
        """.utf8)
        MockURLProtocol.setHandler { _ in (200, body) }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        let user: CurrentUser = try await client.send(Endpoint(path: "/auth/me", requiresAuth: false))
        XCTAssertEqual(user.username, "tester")
        XCTAssertFalse(user.isAdmin)
    }

    func testRateLimitMapsTo429Error() async throws {
        MockURLProtocol.setHandler { _ in (429, Data("{\"ok\": false, \"error\": \"slow down\"}".utf8)) }
        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: CurrentUser = try await client.send(Endpoint(path: "/auth/me", requiresAuth: false))
            XCTFail("Expected rate limit error")
        } catch APIError.rateLimited {
            // expected
        }
    }

    /// 20 concurrent requests all hit a 401; exactly ONE refresh executes,
    /// then every request retries with the fresh token and succeeds.
    func testConcurrent401sTriggerExactlyOneRefresh() async throws {
        let auth = SingleFlightAuthStub()
        MockURLProtocol.setHandler { request in
            let header = request.value(forHTTPHeaderField: "Authorization")
            if header == "Bearer fresh" {
                return (200, Data("{\"ok\": true, \"data\": {\"id\": \"1\", \"listing_number\": 1, \"seller_id\": \"s\", \"title\": \"t\", \"price\": \"1.00\", \"currency\": \"USD\", \"status\": \"active\", \"images\": []}}".utf8))
            }
            return (401, Data("{\"ok\": false, \"error\": \"Authentication credentials were not provided\"}".utf8))
        }

        let client = APIClient(configuration: mockConfiguration(), auth: auth)
        try await withThrowingTaskGroup(of: Listing.self) { group in
            for index in 0..<20 {
                group.addTask {
                    try await client.send(Endpoint<Listing>(path: "/listings/\(index)"))
                }
            }
            var completed = 0
            for try await listing in group {
                XCTAssertEqual(listing.id, "1")
                completed += 1
            }
            XCTAssertEqual(completed, 20)
        }

        let refreshCount = await auth.state.refreshCount
        XCTAssertEqual(refreshCount, 1, "single-flight: 20 concurrent 401s must coalesce into one refresh")
    }

    /// Same property, against the real AuthSession implementation: 20
    /// concurrent refreshAfterUnauthorized() calls produce exactly one
    /// network refresh.
    @MainActor
    func testAuthSessionRefreshIsSingleFlight() async throws {
        let hitCounter = HitCounter()
        MockURLProtocol.setHandler { request in
            if request.url?.path == "/auth/refresh" {
                hitCounter.increment()
                Thread.sleep(forTimeInterval: 0.1) // hold callers in flight
                return (200, Data("{\"ok\": true, \"data\": {\"access_token\": \"fresh-token\"}}".utf8))
            }
            return (404, Data("{\"ok\": false, \"error\": \"not found\"}".utf8))
        }

        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "stale", refreshToken: "refresh-1"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)

        var refreshTasks: [Task<Bool, Never>] = []
        for _ in 0..<20 {
            refreshTasks.append(Task { @MainActor in
                await session.refreshAfterUnauthorized()
            })
        }
        var results: [Bool] = []
        for task in refreshTasks {
            results.append(await task.value)
        }

        XCTAssertEqual(results.count, 20)
        XCTAssertTrue(results.allSatisfy { $0 }, "every caller sees the shared refresh succeed")
        XCTAssertEqual(hitCounter.value, 1, "exactly one /auth/refresh network call")
        XCTAssertEqual(store.load()?.accessToken, "fresh-token")
        XCTAssertEqual(store.load()?.refreshToken, "refresh-1", "refresh token is not rotated")
    }
}

/// Thread-safe test counter (the URLProtocol handler runs off-main).
final class HitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
}
