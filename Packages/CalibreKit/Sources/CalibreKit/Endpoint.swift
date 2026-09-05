import Foundation

/// One API call, fully described. `Response` is what `{ok: true, data: ...}`
/// decodes into.
public struct Endpoint<Response: Decodable & Sendable>: Sendable {
    public enum Method: String, Sendable {
        case get = "GET", post = "POST", patch = "PATCH", put = "PUT", delete = "DELETE"
    }

    public enum Body: Sendable {
        case none
        case json(Data)
        case multipart(MultipartForm)
    }

    public let method: Method
    public let path: String
    public let query: [URLQueryItem]
    public let body: Body
    /// When true, a 401 triggers one silent refresh + retry before failing.
    public let requiresAuth: Bool

    public init(
        method: Method = .get,
        path: String,
        query: [URLQueryItem] = [],
        body: Body = .none,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
    }

    /// JSON-body convenience.
    public static func json(
        method: Method,
        path: String,
        payload: some Encodable,
        query: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) throws -> Endpoint {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return Endpoint(
            method: method,
            path: path,
            query: query,
            body: .json(try encoder.encode(payload)),
            requiresAuth: requiresAuth
        )
    }
}

/// Builds the `URLRequest` for one endpoint against a client's configuration
/// and auth provider. Shared by `APIClient` and `MessagingClient` — the two
/// clients differ in how a *response* decodes (see `MessagingClient`'s own
/// doc comment for why), not in how a request is built, so this half used to
/// be copied verbatim between them.
func buildAPIRequest(
    for endpoint: Endpoint<some Decodable>,
    configuration: APIConfiguration,
    auth: AuthProviding?
) async throws -> URLRequest {
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

/// Multipart/form-data builder for photo and file uploads.
public struct MultipartForm: Sendable {
    public struct Part: Sendable {
        let name: String
        let filename: String?
        let contentType: String?
        let data: Data
    }

    public private(set) var parts: [Part] = []
    public let boundary = "calibre-\(UUID().uuidString)"

    public init() {}

    public mutating func addField(_ name: String, value: String) {
        parts.append(Part(name: name, filename: nil, contentType: nil, data: Data(value.utf8)))
    }

    /// Content type must be explicit — iOS HEIC parts otherwise risk being
    /// sent as application/octet-stream, which the backend rejects.
    public mutating func addFile(_ name: String, filename: String, contentType: String, data: Data) {
        parts.append(Part(name: name, filename: filename, contentType: contentType, data: data))
    }

    public func encoded() -> Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append(Data("\(disposition)\r\n".utf8))
            if let contentType = part.contentType {
                body.append(Data("Content-Type: \(contentType)\r\n".utf8))
            }
            body.append(Data("\r\n".utf8))
            body.append(part.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}
