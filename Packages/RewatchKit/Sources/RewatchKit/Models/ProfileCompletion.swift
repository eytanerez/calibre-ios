import Foundation

/// The body of `PATCH account/profile-completion`.
///
/// Every field is optional on the wire and only what is present is written, so
/// a client sends the answers the member actually changed and nothing else. A
/// nil property is *omitted* rather than sent as null — Swift's synthesized
/// encoding uses `encodeIfPresent` for optionals, and the backend treats a
/// present-but-non-string field as a 400, so a null would be refused rather
/// than ignored.
///
/// Keys go out snake_cased by `Endpoint.json`'s encoder strategy, the same way
/// every other patch payload in this package does.
public struct ProfileCompletionFields: Encodable, Sendable, Equatable {
    public var firstName: String?
    public var lastName: String?
    public var phone: String?
    public var username: String?

    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        phone: String? = nil,
        username: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.username = username
    }

    /// True when there is nothing to send. The caller uses it to keep a submit
    /// that changed nothing off the network entirely.
    public var isEmpty: Bool {
        firstName == nil && lastName == nil && phone == nil && username == nil
    }
}

/// `{"ok": true, "data": {"user": …}}` — the login envelope, which is what the
/// endpoint answers with so the client can drop the user straight into the
/// session it already holds.
public struct ProfileCompletionResponse: Decodable, Sendable {
    public let user: CurrentUser
}

/// The HTTP statuses this screen has to tell apart. The backend states its
/// refusals in plain English and the client shows those words; only the
/// conflict earns its own copy, because it belongs beside the username field
/// rather than at the top of the form.
public enum ProfileCompletionStatus {
    /// A field the server would not accept — its `message` is the thing to show.
    public static let badField = 400
    /// Somebody else already holds that username.
    public static let usernameTaken = 409
}
