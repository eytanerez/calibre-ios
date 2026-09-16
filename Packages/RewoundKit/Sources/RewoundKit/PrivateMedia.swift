import Foundation

/// Reads the bytes of an object Rewound serves behind the member's own
/// credential.
///
/// Kept as a protocol so a view can be driven from a stub, and so the one
/// implementation that attaches a bearer token is a single, auditable place.
public protocol PrivateMediaFetching: Sendable {
    func data(for url: URL) async throws -> Data
}

/// The owner's own photographs are not public objects. They are served from
/// `/secure-media/<kind>/<scope>/<name>` on the API host, and that route
/// checks the caller: anonymous gets 401 and a signed-in stranger gets 404.
/// So an image view cannot simply be handed the address — the bytes have to
/// be fetched by something that holds the session, which is what this is.
///
/// Three properties are load bearing:
///
/// - **The credential never leaves the API's own origin.** `data(for:)`
///   refuses an address that is not the configured host, scheme and port, so
///   the bearer token cannot be walked off Rewound by a URL that arrived in a
///   payload. `VaultCoverSource` makes the same distinction when it decides
///   what a cover *is*; this refuses it again at the moment a request would
///   actually be built, because that is the only place it can be enforced.
/// - **Nothing is written to disk.** The proxy answers
///   `Cache-Control: private, no-store`, so the session is ephemeral, its URL
///   cache is off, and every request ignores whatever a shared cache might
///   hold. What is kept is a bounded map in this process, dropped whole when
///   the session ends.
/// - **A 401 is a refresh, once.** The same contract `APIClient` honors: an
///   expired access token renews and the fetch is retried a single time, so a
///   gallery does not empty itself the first morning after a token ages out.
public actor PrivateMediaLoader: PrivateMediaFetching {
    private let origin: URL
    private let auth: AuthProviding?
    private let session: URLSession
    /// The ceiling on what is held in memory. Eight photographs of one watch
    /// re-encoded by the server sit far inside it; a member scrolling a large
    /// collection evicts in arrival order rather than growing without bound.
    private let byteBudget: Int

    private var cached: [URL: Data] = [:]
    private var arrival: [URL] = []
    private var heldBytes = 0
    private var inFlight: [URL: Task<Data, Error>] = [:]

    public init(configuration: APIConfiguration, auth: AuthProviding?, byteBudget: Int = 48 * 1_024 * 1_024) {
        self.origin = configuration.baseURL
        self.auth = auth
        self.byteBudget = byteBudget
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        if let protocolClasses = configuration.protocolClasses {
            config.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: config)
    }

    public func data(for url: URL) async throws -> Data {
        guard Self.isSameOrigin(url, as: origin) else { throw APIError.invalidResponse }
        if let hit = cached[url] { return hit }
        // Two frames asking for the same photograph in the same instant — the
        // card behind the sheet and the tile inside it — is one fetch, not
        // two, and neither of them is the one that has to wait.
        if let running = inFlight[url] { return try await running.value }

        let session = self.session
        let auth = self.auth
        let task = Task<Data, Error>.detached {
            try await Self.fetch(url, session: session, auth: auth, isRetry: false)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let bytes = try await task.value
        remember(bytes, for: url)
        return bytes
    }

    /// Drops everything held for the account that just ended. A photograph of
    /// somebody's own watch must not still be in memory to be drawn under the
    /// next person to sign in on this device.
    public func clear() {
        cached.removeAll()
        arrival.removeAll()
        heldBytes = 0
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }

    private func remember(_ bytes: Data, for url: URL) {
        cached[url] = bytes
        arrival.append(url)
        heldBytes += bytes.count
        while heldBytes > byteBudget, let oldest = arrival.first {
            arrival.removeFirst()
            heldBytes -= cached.removeValue(forKey: oldest)?.count ?? 0
        }
    }

    private static func fetch(
        _ url: URL,
        session: URLSession,
        auth: AuthProviding?,
        isRetry: Bool
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if let header = await auth?.authHeader() {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(underlying: error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401, !isRetry, let auth {
            if await auth.refreshAfterUnauthorized() {
                return try await fetch(url, session: session, auth: auth, isRetry: true)
            }
            throw APIError.sessionExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            // The proxy answers a bare status here, not Rewound's JSON
            // envelope, so there is no server sentence to carry up. The
            // status is what a caller can tell apart: 404 means this
            // photograph is not the caller's, and every retry of it is a
            // second wrong answer.
            throw APIError.server(
                message: "That photograph couldn\u{2019}t be loaded.",
                code: nil,
                status: http.statusCode,
                details: nil
            )
        }
        guard !data.isEmpty else { throw APIError.invalidResponse }
        return data
    }

    static func isSameOrigin(_ url: URL, as origin: URL) -> Bool {
        func port(_ candidate: URL) -> Int? {
            candidate.port ?? (candidate.scheme?.lowercased() == "https" ? 443 : 80)
        }
        return url.scheme?.lowercased() == origin.scheme?.lowercased()
            && url.host()?.lowercased() == origin.host()?.lowercased()
            && port(url) == port(origin)
    }
}
