import Foundation
import Observation

/// The signed-in user as the backend reports it.
public struct CurrentUser: Codable, Sendable, Equatable {
    public let id: String
    public let email: String
    public let username: String
    public let roles: [String]

    public var isAdmin: Bool { roles.contains("admin") }
}

/// Something the user tried to do while signed out — replayed after sign-in.
public struct AuthIntent: Sendable {
    /// Context line for the sign-in sheet, e.g. "Sign in to save this watch".
    public let reason: String
    let action: @MainActor @Sendable () async -> Void

    public init(reason: String, action: @escaping @MainActor @Sendable () async -> Void) {
        self.reason = reason
        self.action = action
    }
}

/// Session lifecycle: tokens in Keychain, silent single-flight refresh on 401,
/// guest gating with intent replay. Tokens are opaque — never decoded locally.
@MainActor
@Observable
public final class AuthSession {
    public private(set) var user: CurrentUser?
    /// Set when a gated action needs sign-in; the app presents the auth sheet.
    public var pendingIntent: AuthIntent?

    /// A persisted token pair represents a signed-in session even while the
    /// launch-time `/auth/me` validation is temporarily offline. A definitive
    /// 401 + rejected refresh clears the tokens and flips this back to false.
    public private(set) var isAuthenticated = false

    @ObservationIgnored private let tokenStore: TokenStoring
    @ObservationIgnored private let configuration: APIConfiguration
    /// Bare transport for auth endpoints only (no auth provider — no recursion).
    @ObservationIgnored private lazy var bareClient = APIClient(configuration: configuration, auth: nil)
    @ObservationIgnored private var tokens: TokenPair?
    @ObservationIgnored private var refreshTask: Task<Bool, Never>?
    @ObservationIgnored private let urlSession: URLSession

    public init(configuration: APIConfiguration, tokenStore: TokenStoring = KeychainTokenStore()) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.tokens = tokenStore.load()
        self.isAuthenticated = self.tokens != nil
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        if let protocolClasses = configuration.protocolClasses {
            config.protocolClasses = protocolClasses
        }
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Bootstrap

    /// Restores the session on launch: if tokens exist, validate via /auth/me
    /// and refresh only after a real 401. Transient network/server failures keep
    /// the Keychain session so closing the app while the API is unavailable
    /// never signs the user out.
    public func bootstrap() async {
        guard tokens != nil else { return }
        do {
            user = try await sendAuthed(Endpoint<CurrentUser>(path: "/auth/me"))
        } catch APIError.sessionExpired {
            guard await refreshAfterUnauthorized() else { return }
            do {
                user = try await sendAuthed(Endpoint<CurrentUser>(path: "/auth/me"))
            } catch APIError.sessionExpired {
                // A freshly issued access token was rejected. This is a
                // definitive invalid session, not a connectivity problem.
                clearSession()
            } catch {
                // The refresh succeeded, so retain it through a transient
                // validation failure and let the next request retry normally.
            }
        } catch {
            // Offline, timeout, decoding, rate-limit, and 5xx failures are not
            // evidence that the persisted credentials are invalid.
        }
    }

    // MARK: - Sign in / out

    public func login(identifier: String, password: String) async throws {
        try await authenticate(path: "/auth/login", payload: ["identifier": identifier, "password": password])
    }

    public func register(_ payload: [String: String]) async throws {
        try await authenticate(path: "/auth/register", payload: payload)
    }

    /// Sign in with Apple / Google-exchange — any endpoint that answers with
    /// the login shape.
    public func authenticate(path: String, payload: [String: some Encodable & Sendable]) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw APIError.rateLimited(retryAfter: nil)
            }
            let raw = try? decoder.decode(AuthErrorEnvelope.self, from: data)
            throw APIError.server(
                message: raw?.error ?? "Sign-in failed. Please try again.",
                code: nil,
                status: http.statusCode,
                details: nil
            )
        }

        let envelope = try decoder.decode(AuthEnvelope.self, from: data)
        // The body carries the access token; the refresh token arrives only as
        // an HttpOnly cookie — harvest it from Set-Cookie ourselves.
        let refreshToken = envelope.data.tokens.refreshToken ?? harvestCookie(
            named: "calibre_refresh_token",
            from: http
        )
        applySession(
            user: envelope.data.user,
            tokens: TokenPair(accessToken: envelope.data.tokens.accessToken, refreshToken: refreshToken)
        )
    }

    public func logout() async {
        let refreshToken = tokens?.refreshToken
        clearSession()
        // Best-effort server-side revocation.
        if let refreshToken {
            let endpoint = try? Endpoint<EmptyResponse>.json(
                method: .post,
                path: "/auth/logout",
                payload: ["refresh_token": refreshToken],
                requiresAuth: false
            )
            if let endpoint {
                _ = try? await bareClient.send(endpoint)
            }
        }
    }

    // MARK: - Guest gating

    /// Runs `action` now when signed in; otherwise stores it as the pending
    /// intent (the app presents the auth sheet) and replays it after sign-in.
    public func require(_ reason: String, action: @escaping @MainActor @Sendable () async -> Void) {
        if isAuthenticated {
            Task { await action() }
        } else {
            pendingIntent = AuthIntent(reason: reason, action: action)
        }
    }

    /// Called by the auth sheet after a successful sign-in.
    public func replayPendingIntent() {
        guard let intent = pendingIntent else { return }
        pendingIntent = nil
        Task { await intent.action() }
    }

    private func applySession(user: CurrentUser, tokens: TokenPair) {
        self.user = user
        self.tokens = tokens
        isAuthenticated = true
        tokenStore.save(tokens)
        let hadPendingIntent = pendingIntent != nil
        if hadPendingIntent {
            replayPendingIntent()
        }
    }

    private func clearSession() {
        user = nil
        tokens = nil
        isAuthenticated = false
        tokenStore.clear()
    }

    private func harvestCookie(named name: String, from response: HTTPURLResponse) -> String? {
        guard let headers = response.allHeaderFields as? [String: String],
              let url = response.url else { return nil }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            .first(where: { $0.name == name })?.value
    }

    private func sendAuthed<T: Decodable & Sendable>(_ endpoint: Endpoint<T>) async throws -> T {
        var request = URLRequest(url: configuration.baseURL.appending(path: endpoint.path))
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let header = await authHeader() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 {
            throw APIError.sessionExpired
        }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        }
        guard (200..<300).contains(http.statusCode) else {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let raw = try? decoder.decode(AuthErrorEnvelope.self, from: data)
            throw APIError.server(
                message: raw?.error ?? "Something went wrong.",
                code: nil,
                status: http.statusCode,
                details: nil
            )
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DataWrap<T>.self, from: data).data
    }
}

/// `{data: ...}` unwrap for AuthSession's bare requests (types can't be
/// nested in generic functions).
private struct DataWrap<V: Decodable>: Decodable {
    let data: V
}

// MARK: - AuthProviding

extension AuthSession: AuthProviding {
    /// Native clients use the backend's documented Bearer-token path. Cookie
    /// storage remains disabled, avoiding stale browser-cookie behavior.
    public func authHeader() async -> (name: String, value: String)? {
        guard let tokens else { return nil }
        return ("Authorization", "Bearer \(tokens.accessToken)")
    }

    /// Single-flight: concurrent 401s await one refresh.
    public func refreshAfterUnauthorized() async -> Bool {
        if let task = refreshTask {
            return await task.value
        }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performRefresh()
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> Bool {
        guard let refreshToken = tokens?.refreshToken else {
            // A 401 with no refresh credential cannot recover.
            clearSession()
            return false
        }
        struct RefreshResponse: Decodable, Sendable {
            let accessToken: String
        }
        do {
            let endpoint = try Endpoint<RefreshResponse>.json(
                method: .post,
                path: "/auth/refresh",
                payload: ["refresh_token": refreshToken],
                requiresAuth: false
            )
            let response = try await bareClient.send(endpoint)
            let updated = TokenPair(accessToken: response.accessToken, refreshToken: refreshToken)
            tokens = updated
            tokenStore.save(updated)
            return true
        } catch let APIError.server(_, _, status, _) where status == 401 || status == 403 {
            // Only an explicit auth rejection proves the persisted refresh
            // token is no longer usable. Never erase it for a timeout or 5xx.
            clearSession()
            return false
        } catch {
            return false
        }
    }
}

private struct AuthEnvelope: Decodable {
    struct Payload: Decodable {
        let user: CurrentUser
        let tokens: Tokens
    }

    struct Tokens: Decodable {
        let accessToken: String
        let refreshToken: String?
    }

    let data: Payload
}

private struct AuthErrorEnvelope: Decodable {
    let error: String?
}
