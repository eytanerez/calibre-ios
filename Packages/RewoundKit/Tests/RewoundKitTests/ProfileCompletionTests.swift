import Foundation
import XCTest
@testable import RewoundKit

/// The completion gate rests on two things: that `CurrentUser` decodes from
/// both the new payload and the old one, and that the patch sends only what
/// the member changed.
///
/// The old-payload half is the one worth having. Every release build talks to
/// the staging box, but a member can be on a build newer than the server it
/// reaches — and a client that refused the session over a missing
/// `profile_complete` would sign that member out, while one that read a
/// missing key as `false` would hold them behind a form the server has no
/// endpoint to satisfy. Absent has to mean complete.
final class ProfileCompletionTests: XCTestCase {

    private func user(_ json: String) throws -> CurrentUser {
        try apiDecoder().decode(CurrentUser.self, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodesTheFullPayload() throws {
        let decoded = try user("""
        {
          "id": "u1", "email": "eytan@example.com", "username": "eytan",
          "roles": ["member"],
          "first_name": "Eytan", "last_name": "Erez",
          "phone": "(415) 555-0134", "profile_complete": true
        }
        """)

        XCTAssertEqual(decoded.firstName, "Eytan")
        XCTAssertEqual(decoded.lastName, "Erez")
        XCTAssertEqual(decoded.phone, "(415) 555-0134")
        XCTAssertEqual(decoded.profileComplete, true)
    }

    func testAnIncompleteAccountSaysSo() throws {
        let decoded = try user("""
        {
          "id": "u1", "email": "eytan@example.com", "username": "eytan",
          "roles": [], "first_name": "Eytan", "last_name": "Erez",
          "phone": null, "profile_complete": false
        }
        """)

        XCTAssertNil(decoded.phone)
        XCTAssertEqual(decoded.profileComplete, false)
    }

    /// A server that predates this work sends id/email/username/roles and
    /// nothing else.
    func testDecodesAPayloadFromAServerThatPredatesTheFlag() throws {
        let decoded = try user("""
        {"id": "u1", "email": "eytan@example.com", "username": "eytan", "roles": []}
        """)

        XCTAssertNil(decoded.firstName)
        XCTAssertNil(decoded.lastName)
        XCTAssertNil(decoded.phone)
        XCTAssertNil(decoded.profileComplete)
    }

    /// The whole reason the flag is `Bool?` and not `Bool`.
    @MainActor
    func testAMissingFlagDoesNotGate() async throws {
        let session = AuthSession(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test")!),
            tokenStore: MemoryTokenStore(tokens: TokenPair(accessToken: "a", refreshToken: "r"))
        )
        session.replaceUser(with: try user("""
        {"id": "u1", "email": "eytan@example.com", "username": "eytan", "roles": []}
        """))

        XCTAssertFalse(session.needsProfileCompletion)
    }

    @MainActor
    func testAnExplicitFalseGates() async throws {
        let session = AuthSession(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test")!),
            tokenStore: MemoryTokenStore(tokens: TokenPair(accessToken: "a", refreshToken: "r"))
        )
        session.replaceUser(with: try user("""
        {"id": "u1", "email": "e@example.com", "username": "eytan", "roles": [],
         "profile_complete": false}
        """))
        XCTAssertTrue(session.needsProfileCompletion)

        session.replaceUser(with: try user("""
        {"id": "u1", "email": "e@example.com", "username": "eytan", "roles": [],
         "first_name": "Eytan", "last_name": "Erez", "phone": "4155550134",
         "profile_complete": true}
        """))
        XCTAssertFalse(session.needsProfileCompletion)
    }

    /// Nobody signed in has nothing to complete.
    @MainActor
    func testASignedOutSessionIsNotGated() {
        let session = AuthSession(
            configuration: APIConfiguration(baseURL: URL(string: "https://api.test")!),
            tokenStore: MemoryTokenStore()
        )
        XCTAssertFalse(session.needsProfileCompletion)
    }

    // MARK: - Request encoding

    /// Only what changed goes on the wire: a nil field is *absent*, not null.
    /// The backend refuses a non-string value for any field it accepts, so a
    /// null would be a 400 rather than a "leave this alone".
    func testOnlyThePresentFieldsAreEncoded() throws {
        let endpoint = try Endpoint<ProfileCompletionResponse>.json(
            method: .patch,
            path: "/account/profile-completion",
            payload: ProfileCompletionFields(phone: "(415) 555-0134")
        )
        guard case .json(let data) = endpoint.body else {
            return XCTFail("Expected a JSON body")
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body.keys.sorted(), ["phone"])
        XCTAssertEqual(body["phone"] as? String, "(415) 555-0134")
    }

    func testKeysGoOutSnakeCased() throws {
        let endpoint = try Endpoint<ProfileCompletionResponse>.json(
            method: .patch,
            path: "/account/profile-completion",
            payload: ProfileCompletionFields(
                firstName: "Eytan",
                lastName: "Erez",
                phone: "4155550134",
                username: "eytan"
            )
        )
        guard case .json(let data) = endpoint.body else {
            return XCTFail("Expected a JSON body")
        }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(body.keys.sorted(), ["first_name", "last_name", "phone", "username"])
        XCTAssertEqual(body["first_name"] as? String, "Eytan")
        XCTAssertEqual(body["username"] as? String, "eytan")
    }

    func testAnEmptyPatchKnowsItIsEmpty() {
        XCTAssertTrue(ProfileCompletionFields().isEmpty)
        XCTAssertFalse(ProfileCompletionFields(username: "eytan").isEmpty)
    }

    // MARK: - Round trip

    /// The endpoint answers with the login envelope, and what comes back is
    /// dropped straight into the session.
    @MainActor
    func testTheResponseReplacesTheSessionUser() async throws {
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
        let session = AuthSession(
            configuration: configuration,
            tokenStore: MemoryTokenStore(tokens: TokenPair(accessToken: "a", refreshToken: "r"))
        )
        session.replaceUser(with: try user("""
        {"id": "u1", "email": "e@example.com", "username": "eytan", "roles": [],
         "first_name": "Eytan", "last_name": "Erez", "profile_complete": false}
        """))
        XCTAssertTrue(session.needsProfileCompletion)

        let recorded = RecordedRequest()
        MockURLProtocol.setHandler { request in
            recorded.capture(request)
            let body = """
            {"ok": true, "data": {"user": {
              "id": "u1", "email": "e@example.com", "username": "eytan", "roles": [],
              "first_name": "Eytan", "last_name": "Erez", "phone": "(415) 555-0134",
              "profile_complete": true
            }}}
            """
            return (200, Data(body.utf8))
        }

        let store = AccountStore(client: APIClient(configuration: configuration, auth: session), auth: session)
        let updated = try await store.completeProfile(ProfileCompletionFields(phone: "(415) 555-0134"))
        session.replaceUser(with: updated)

        XCTAssertEqual(recorded.method, "PATCH")
        XCTAssertEqual(recorded.path, "/account/profile-completion")
        XCTAssertEqual(session.user?.phone, "(415) 555-0134")
        XCTAssertFalse(session.needsProfileCompletion)
    }

    /// A taken username comes back as a 409, and the screen keys its inline
    /// message off exactly that status.
    @MainActor
    func testATakenUsernameSurfacesAsA409() async throws {
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
        let session = AuthSession(
            configuration: configuration,
            tokenStore: MemoryTokenStore(tokens: TokenPair(accessToken: "a", refreshToken: "r"))
        )
        MockURLProtocol.setHandler { _ in
            (409, Data(#"{"ok": false, "error": "Username already in use"}"#.utf8))
        }

        let store = AccountStore(client: APIClient(configuration: configuration, auth: session), auth: session)
        do {
            _ = try await store.completeProfile(ProfileCompletionFields(username: "taken"))
            XCTFail("Expected the conflict to throw")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatus, ProfileCompletionStatus.usernameTaken)
        }
    }

    /// A refused field comes back as a 400 whose message is the server's own
    /// sentence — the screen shows it verbatim rather than inventing copy.
    @MainActor
    func testABadFieldSurfacesTheServersMessage() async throws {
        let configuration = APIConfiguration(
            baseURL: URL(string: "https://api.test")!,
            protocolClasses: [MockURLProtocol.self]
        )
        let session = AuthSession(
            configuration: configuration,
            tokenStore: MemoryTokenStore(tokens: TokenPair(accessToken: "a", refreshToken: "r"))
        )
        MockURLProtocol.setHandler { _ in
            (400, Data(#"{"ok": false, "error": "phone needs at least 7 digits"}"#.utf8))
        }

        let store = AccountStore(client: APIClient(configuration: configuration, auth: session), auth: session)
        do {
            _ = try await store.completeProfile(ProfileCompletionFields(phone: "1"))
            XCTFail("Expected the refusal to throw")
        } catch let error as APIError {
            XCTAssertEqual(error.httpStatus, ProfileCompletionStatus.badField)
            XCTAssertEqual(error.errorDescription, "phone needs at least 7 digits")
        }
    }
}

/// Captures the one request a test made, from the protocol's thread.
private final class RecordedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var request: URLRequest?

    func capture(_ request: URLRequest) {
        lock.withLock { self.request = request }
    }

    var method: String? { lock.withLock { request?.httpMethod } }
    var path: String? { lock.withLock { request?.url?.path } }
}
