import Foundation

/// Transport for `calibre-messaging` — a separate service from the main
/// Calibre Backend, so it earns its own client rather than overloading
/// `APIClient`.
///
/// The difference is the wire contract, not the domain. `APIClient` decodes
/// every response as Backend's `{ok, data}` envelope and every refusal as
/// `{"error": ...}`; calibre-messaging is a plain FastAPI service that
/// answers each endpoint's own `response_model` directly and refuses with
/// FastAPI's default `{"detail": ...}`. Reusing `APIClient.send` against that
/// shape would fail to decode *every* response, success or failure. This
/// mirrors `AuthSession`'s own raw request path in the same file family, kept
/// for exactly this reason: its auth endpoints don't fit the envelope either.
///
/// Auth still works exactly as it does for `APIClient` — the same
/// Backend-issued bearer token, via whatever `AuthProviding` is handed in. In
/// practice that is the app's one `AuthSession`, shared across both clients:
/// a 401 here still triggers the same silent refresh against Backend.
public final class MessagingClient: Sendable {
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
        let request = try await buildAPIRequest(for: endpoint, configuration: configuration, auth: auth)
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

        return try decodeBody(data, status: http.statusCode, path: endpoint.path)
    }

    private func decodeBody<Response: Decodable>(_ data: Data, status: Int, path: String) throws -> Response {
        guard (200..<300).contains(status) else {
            throw APIError.server(message: Self.detailMessage(from: data), code: nil, status: status, details: nil)
        }

        // Every 2xx this service answers with no body (`POST
        // /threads/{id}/read` is a bare 204) is a caller that asked for
        // nothing back — same shortcut `APIClient` takes, for the same
        // reason: a caller expecting a real payload must still fail rather
        // than being handed a silent default.
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        guard !data.isEmpty else {
            throw APIError.decoding(
                underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Empty body for \(path)")
                ),
                path: path
            )
        }
        do {
            return try APIClient.makeDecoder(origin: configuration.baseURL).decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(underlying: error, path: path)
        }
    }

    /// FastAPI's default refusal shapes: `{"detail": "message"}` for a raised
    /// `HTTPException`, or `{"detail": [{"msg": "...", ...}, ...]}` for a
    /// request-validation (422) failure. Either way, something a person can
    /// read — never the raw JSON, and never silently empty.
    private static func detailMessage(from data: Data) -> String {
        struct StringDetail: Decodable { let detail: String }
        struct ValidationItem: Decodable { let msg: String? }
        struct ValidationDetail: Decodable { let detail: [ValidationItem] }

        if let decoded = try? JSONDecoder().decode(StringDetail.self, from: data) {
            return decoded.detail
        }
        if let decoded = try? JSONDecoder().decode(ValidationDetail.self, from: data),
           let first = decoded.detail.first?.msg {
            return first
        }
        return "Something went wrong."
    }

    // MARK: - Server-Sent Events

    /// One `data:` frame off an SSE stream, already de-chunked and stripped
    /// of its `event:`/`:comment` lines — the keepalive comment and the
    /// opening `: connected` line never reach the caller. No auth header:
    /// the stream endpoint authorises by the one-time `ticket` query item
    /// (see `StreamTicket`), the same reason `EventSource` can't carry one.
    public func eventStream(path: String, query: [URLQueryItem]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var components = URLComponents(
                        url: configuration.baseURL.appending(path: path),
                        resolvingAgainstBaseURL: false
                    )!
                    components.queryItems = query
                    var request = URLRequest(url: components.url!)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continuation.finish(throwing: APIError.invalidResponse)
                        return
                    }

                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                continuation.yield(Data(dataLines.joined(separator: "\n").utf8))
                                dataLines = []
                            }
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }
                        var value = String(line.dropFirst("data:".count))
                        if value.hasPrefix(" ") { value.removeFirst() }
                        dataLines.append(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
