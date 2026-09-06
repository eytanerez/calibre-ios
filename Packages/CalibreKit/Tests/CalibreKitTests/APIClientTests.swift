import Foundation
import XCTest
@testable import CalibreKit

// MARK: - URLProtocol mock

/// Routes every request through a swappable handler. Installed via
/// `APIConfiguration.protocolClasses`, so both APIClient's session and
/// AuthSession's internal sessions hit it.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)
    typealias AsyncHandler = @Sendable (URLRequest) async -> (status: Int, body: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: Handler?
    nonisolated(unsafe) private static var _asyncHandler: AsyncHandler?

    static func setHandler(_ handler: @escaping Handler) {
        lock.withLock {
            _handler = handler
            _asyncHandler = nil
        }
    }

    static func setAsyncHandler(_ handler: @escaping AsyncHandler) {
        lock.withLock {
            _handler = nil
            _asyncHandler = handler
        }
    }

    private static func currentHandlers() -> (Handler?, AsyncHandler?) {
        lock.withLock { (_handler, _asyncHandler) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (handler, asyncHandler) = Self.currentHandlers()
        if let asyncHandler {
            let responder = MockProtocolResponder(owner: self)
            Task { [request, responder] in
                guard let url = request.url else { return }
                let result = await asyncHandler(request)
                responder.deliver(status: result.status, body: result.body, url: url)
            }
            return
        }
        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        deliver(status: status, body: body, url: url)
    }

    fileprivate func deliver(status: Int, body: Data, url: URL) {
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

private final class MockProtocolResponder: @unchecked Sendable {
    private weak var owner: MockURLProtocol?

    init(owner: MockURLProtocol) {
        self.owner = owner
    }

    func deliver(status: Int, body: Data, url: URL) {
        owner?.deliver(status: status, body: body, url: url)
    }
}

// Shared by every test file in this target that needs an `APIClient` or
// `MessagingClient` pointed at `MockURLProtocol` — it used to be copied,
// byte-for-byte, into six other test files.
func mockConfiguration() -> APIConfiguration {
    APIConfiguration(
        baseURL: URL(string: "https://mock.calibre.test")!,
        protocolClasses: [MockURLProtocol.self]
    )
}

/// `httpBody` is nil by the time a request reaches a URLProtocol — URLSession
/// hands the body over as a stream instead — so a "seen request" recorder
/// needs to drain it while it still has it. Shared by every such recorder in
/// this target; it used to be a byte-identical private copy in each one.
func drainHTTPBodyStream(_ stream: InputStream) -> Data {
    stream.open()
    defer { stream.close() }
    var data = Data()
    let size = 4096
    var buffer = [UInt8](repeating: 0, count: size)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: size)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
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

    /// The exact 402 body `POST /checkout/create-intent` returns when a buyer
    /// asks to pay by wire with no credit card recorded as their default —
    /// copied from a live response, `"funding": null` and all.
    ///
    /// Two things have to survive it. The machine code has to arrive, because
    /// `WireCardRefusal` is built from it and the entire wire card-refusal UI
    /// (add a card, pay by card instead) is keyed off that type being
    /// non-nil. And the *other* key in the same map must not take the code
    /// down with it: decoding `details` straight into `[String: String]` threw
    /// on the null and turned the whole map into nil, which is how a refusal
    /// the buyer could have acted on arrived as "something went wrong, try
    /// again" — advice that could never work.
    func testServerErrorCarriesCodeFromDetailsAlongsideANullSibling() async throws {
        let body = Data("""
        {"ok": false,
         "error": "Paying by wire needs a credit card on file for the refundable $250 authorization.",
         "details": {"code": "wire_card_required", "funding": null}}
        """.utf8)
        MockURLProtocol.setHandler { _ in (402, body) }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: CurrentUser = try await client.send(Endpoint(path: "/checkout/create-intent", requiresAuth: false))
            XCTFail("Expected APIError.server")
        } catch let error as APIError {
            guard case .server(let message, let code, let status, let details) = error else {
                return XCTFail("Expected .server, got \(error)")
            }
            XCTAssertEqual(status, 402)
            XCTAssertEqual(code, "wire_card_required")
            XCTAssertEqual(error.serverCode, "wire_card_required")
            XCTAssertEqual(details?["code"], "wire_card_required")
            // The null is dropped rather than rendered as the word "null".
            XCTAssertNil(details?["funding"])
            XCTAssertTrue(message.hasPrefix("Paying by wire"))
        }
    }

    /// A validation failure states each field as a *list* of messages. Those
    /// are not detail strings and are dropped — but they must not stop the
    /// rest of the map from being read.
    func testServerErrorKeepsScalarDetailsWhenAFieldCarriesAList() async throws {
        let body = Data("""
        {"ok": false, "error": "Listing not found",
         "details": {"code": "listing_reserved", "listing_id": ["not found", "or reserved"], "retry_after": 30}}
        """.utf8)
        MockURLProtocol.setHandler { _ in (409, body) }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: CurrentUser = try await client.send(Endpoint(path: "/checkout/payment-intent", requiresAuth: false))
            XCTFail("Expected APIError.server")
        } catch let error as APIError {
            guard case .server(_, let code, _, let details) = error else {
                return XCTFail("Expected .server, got \(error)")
            }
            XCTAssertEqual(code, "listing_reserved")
            XCTAssertEqual(details?["retry_after"], "30")
            XCTAssertNil(details?["listing_id"])
        }
    }

    /// A top-level `code`, if an endpoint ever sends one, still wins over the
    /// one inside `details`.
    func testTopLevelCodeWinsOverDetailsCode() async throws {
        let body = Data("""
        {"ok": false, "error": "no", "code": "top_level", "details": {"code": "nested"}}
        """.utf8)
        MockURLProtocol.setHandler { _ in (400, body) }

        let client = APIClient(configuration: mockConfiguration(), auth: nil)
        do {
            let _: CurrentUser = try await client.send(Endpoint(path: "/anything", requiresAuth: false))
            XCTFail("Expected APIError.server")
        } catch let error as APIError {
            XCTAssertEqual(error.serverCode, "top_level")
        }
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

    /// A refresh response belongs to the credentials that started it. If the
    /// member signs in while that request is in flight, the old success must
    /// not replace the new account's tokens.
    @MainActor
    func testOldRefreshSuccessCannotOverwriteNewLogin() async throws {
        let refreshGate = AsyncRefreshGate()
        MockURLProtocol.setAsyncHandler { request in
            switch request.url?.path {
            case "/auth/refresh":
                await refreshGate.holdRefresh()
                return (200, Data("{\"ok\": true, \"data\": {\"access_token\": \"old-refreshed\"}}".utf8))
            case "/auth/login":
                return (200, Self.loginResponse(access: "new-access", refresh: "new-refresh"))
            default:
                return (404, Data("{\"ok\": false, \"error\": \"not found\"}".utf8))
            }
        }

        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "old-access", refreshToken: "old-refresh"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)
        let oldRefresh = Task { @MainActor in await session.refreshAfterUnauthorized() }
        await refreshGate.waitUntilRefreshStarts()

        try await session.login(identifier: "new@example.com", password: "password")
        await refreshGate.releaseRefresh()

        let oldRefreshResult = await oldRefresh.value
        XCTAssertFalse(oldRefreshResult)
        XCTAssertEqual(session.user?.id, "new-user")
        XCTAssertEqual(store.load(), TokenPair(accessToken: "new-access", refreshToken: "new-refresh"))
    }

    /// The rejection path follows the same ownership rule: an old refresh
    /// token's 401 cannot clear a replacement session or announce its expiry.
    @MainActor
    func testOldRefreshRejectionCannotClearNewLogin() async throws {
        let refreshGate = AsyncRefreshGate()
        MockURLProtocol.setAsyncHandler { request in
            switch request.url?.path {
            case "/auth/refresh":
                await refreshGate.holdRefresh()
                return (401, Data("{\"ok\": false, \"error\": \"Invalid refresh token\"}".utf8))
            case "/auth/login":
                return (200, Self.loginResponse(access: "new-access", refresh: "new-refresh"))
            default:
                return (404, Data("{\"ok\": false, \"error\": \"not found\"}".utf8))
            }
        }

        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "old-access", refreshToken: "old-refresh"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)
        var clearCount = 0
        var expiryCount = 0
        session.onSessionCleared = { clearCount += 1 }
        session.onSessionExpired = { expiryCount += 1 }
        let oldRefresh = Task { @MainActor in await session.refreshAfterUnauthorized() }
        await refreshGate.waitUntilRefreshStarts()

        try await session.login(identifier: "new@example.com", password: "password")
        await refreshGate.releaseRefresh()

        let oldRefreshResult = await oldRefresh.value
        XCTAssertFalse(oldRefreshResult)
        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.user?.id, "new-user")
        XCTAssertEqual(store.load(), TokenPair(accessToken: "new-access", refreshToken: "new-refresh"))
        XCTAssertEqual(clearCount, 0)
        XCTAssertEqual(expiryCount, 0)
    }

    /// Launch-time API outages must not be interpreted as a logout. The app
    /// can continue with its persisted credentials and retry on the next call.
    @MainActor
    func testAuthBootstrapKeepsSessionOnServerFailure() async {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/auth/me")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-1")
            return (503, Data("{\"ok\": false, \"error\": \"temporarily unavailable\"}".utf8))
        }

        let pair = TokenPair(accessToken: "access-1", refreshToken: "refresh-1")
        let store = MemoryTokenStore(tokens: pair)
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)

        await session.bootstrap()

        XCTAssertTrue(session.isAuthenticated)
        XCTAssertNil(session.user)
        XCTAssertEqual(store.load(), pair)
    }

    /// A 401 is recoverable when the persisted refresh token is still valid.
    /// The retried `/auth/me` must use the newly issued Bearer token.
    @MainActor
    func testAuthBootstrapRefreshesExpiredAccessToken() async {
        let refreshHits = HitCounter()
        MockURLProtocol.setHandler { request in
            switch request.url?.path {
            case "/auth/refresh":
                refreshHits.increment()
                return (200, Data("{\"ok\": true, \"data\": {\"access_token\": \"fresh\"}}".utf8))
            case "/auth/me":
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh" {
                    return (200, Data("{\"data\": {\"id\": \"u1\", \"email\": \"a@b.c\", \"username\": \"tester\", \"roles\": [\"member\"]}}".utf8))
                }
                return (401, Data("{\"ok\": false, \"error\": \"expired\"}".utf8))
            default:
                return (404, Data("{\"ok\": false, \"error\": \"not found\"}".utf8))
            }
        }

        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "stale", refreshToken: "refresh-1"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)

        await session.bootstrap()

        XCTAssertTrue(session.isAuthenticated)
        XCTAssertEqual(session.user?.username, "tester")
        XCTAssertEqual(refreshHits.value, 1)
        XCTAssertEqual(store.load()?.accessToken, "fresh")
    }

    /// Only a definitive refresh-token rejection erases the Keychain session.
    @MainActor
    func testAuthBootstrapClearsSessionWhenRefreshIsRejected() async {
        MockURLProtocol.setHandler { request in
            if request.url?.path == "/auth/refresh" {
                return (401, Data("{\"ok\": false, \"error\": \"Invalid refresh token\"}".utf8))
            }
            return (401, Data("{\"ok\": false, \"error\": \"expired\"}".utf8))
        }

        let store = MemoryTokenStore(tokens: TokenPair(accessToken: "stale", refreshToken: "invalid"))
        let session = AuthSession(configuration: mockConfiguration(), tokenStore: store)

        await session.bootstrap()

        XCTAssertFalse(session.isAuthenticated)
        XCTAssertNil(store.load())
    }

    private static func loginResponse(access: String, refresh: String) -> Data {
        Data("""
        {"ok": true, "data": {
          "user": {"id": "new-user", "email": "new@example.com", "username": "new", "roles": ["member"]},
          "tokens": {"access_token": "\(access)", "refresh_token": "\(refresh)"}
        }}
        """.utf8)
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

/// Pauses a mock refresh at a deterministic interleaving point while allowing
/// the replacement login request through the same URLSession.
actor AsyncRefreshGate {
    private var refreshStarted = false
    private var refreshReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func holdRefresh() async {
        refreshStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        guard !refreshReleased else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilRefreshStarts() async {
        guard !refreshStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseRefresh() {
        refreshReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
