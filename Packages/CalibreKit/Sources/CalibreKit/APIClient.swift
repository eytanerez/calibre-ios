import Foundation

/// Supplies auth headers and refresh behavior. Implemented by `AuthSession`;
/// kept as a protocol so the client is testable in isolation.
public protocol AuthProviding: Sendable {
    /// Header to attach to authenticated requests, or nil when signed out.
    func authHeader() async -> (name: String, value: String)?
    /// Called once after a 401. Returns true if a retry should be attempted.
    /// Implementations must single-flight concurrent callers.
    func refreshAfterUnauthorized() async -> Bool
}

public struct APIConfiguration: Sendable {
    public let baseURL: URL
    /// Test seam: URLProtocol classes injected into every URLSession built from
    /// this configuration (APIClient and AuthSession). Nil in production.
    public let protocolClasses: [AnyClass]?

    public init(baseURL: URL, protocolClasses: [AnyClass]? = nil) {
        self.baseURL = baseURL
        self.protocolClasses = protocolClasses
    }

    /// Resolves the app's configured backend from Info.plist (CalibreAPIBaseURL).
    public static func fromInfoPlist() -> APIConfiguration {
        #if DEBUG
        // UI tests and physical-device development can point at a fixture
        // server or current tunnel without editing a tracked xcconfig. XCUITest
        // forwards `launchEnvironment` into ProcessInfo for this purpose.
        if let override = ProcessInfo.processInfo.environment["CALIBRE_API_BASE_URL"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let raw = override.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else {
                preconditionFailure("CALIBRE_API_BASE_URL must be an absolute HTTP(S) URL")
            }
            return APIConfiguration(baseURL: url)
        }
        #endif

        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CalibreAPIBaseURL") as? String,
              let url = URL(string: raw) else {
            preconditionFailure("CalibreAPIBaseURL missing from Info.plist")
        }
        return APIConfiguration(baseURL: url)
    }
}

extension CodingUserInfoKey {
    /// Origin used to absolutize relative /media/... URLs at decode time.
    static let apiOrigin = CodingUserInfoKey(rawValue: "calibre.apiOrigin")!
}

/// The one HTTP transport. Cookie handling is disabled on purpose — auth is
/// an explicit header, so a stale cookie jar can never shadow the session.
public final class APIClient: Sendable {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let auth: AuthProviding?

    public init(configuration: APIConfiguration, auth: AuthProviding?) {
        self.configuration = configuration
        self.auth = auth
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        if let protocolClasses = configuration.protocolClasses {
            config.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: config)
    }

    public var baseURL: URL { configuration.baseURL }

    public func send<Response>(_ endpoint: Endpoint<Response>) async throws -> Response {
        try await send(endpoint, isRetry: false)
    }

    private func send<Response>(_ endpoint: Endpoint<Response>, isRetry: Bool) async throws -> Response {
        let request = try await buildRequest(endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401, endpoint.requiresAuth, !isRetry, let auth {
            if await auth.refreshAfterUnauthorized() {
                return try await send(endpoint, isRetry: true)
            }
            throw APIError.sessionExpired
        }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        }

        return try decodeEnvelope(data, status: http.statusCode, path: endpoint.path)
    }

    private func buildRequest(_ endpoint: Endpoint<some Decodable>) async throws -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: endpoint.path),
            resolvingAgainstBaseURL: false
        )!
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch endpoint.body {
        case .none:
            break
        case .json(let data):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case .multipart(let form):
            request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = form.encoded()
        }

        if endpoint.requiresAuth, let header = await auth?.authHeader() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }

    /// The decoder every API payload goes through — exposed so tests decode
    /// recorded fixtures with byte-identical behavior (snake_case conversion,
    /// ISO8601 dates, media-URL absolutization against `origin`).
    public static func makeDecoder(origin: URL?) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom(Self.decodeDate)
        if let origin {
            decoder.userInfo[.apiOrigin] = origin
        }
        return decoder
    }

    private func decodeEnvelope<Response: Decodable>(_ data: Data, status: Int, path: String) throws -> Response {
        let decoder = Self.makeDecoder(origin: configuration.baseURL)

        let envelope: RawEnvelope
        do {
            envelope = try decoder.decode(RawEnvelope.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error, path: path)
        }

        guard envelope.ok, (200..<300).contains(status) else {
            throw APIError.server(
                message: envelope.error ?? "Something went wrong.",
                code: envelope.code,
                status: status,
                details: envelope.details
            )
        }

        // Endpoints with no meaningful payload decode as EmptyResponse.
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(DataEnvelope<Response>.self, from: data).data
        } catch {
            throw APIError.decoding(underlying: error, path: path)
        }
    }

    /// ISO8601 with or without fractional seconds — the backend emits both.
    static func decodeDate(_ decoder: Decoder) throws -> Date {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if let date = Self.isoFractional.date(from: raw) ?? Self.iso.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "Unrecognized date: \(raw)"
        ))
    }

    // ISO8601DateFormatter is documented thread-safe; the annotation just
    // tells Swift 6 that sharing these immutable formatters is intentional.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()
}

/// `{ok, error?, details?}` — decoded first to route success vs failure.
private struct RawEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let code: String?
    let details: [String: String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        // details may be a flat map or arbitrary JSON — keep flat strings, drop the rest.
        details = try? container.decodeIfPresent([String: String].self, forKey: .details)
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, code, details
    }
}

private struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

/// For endpoints whose payload we don't need.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
