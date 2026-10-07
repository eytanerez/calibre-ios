import Foundation
import Observation

/// The beta program's state for one run of the app.
///
/// Loaded once at launch and held. The program does not switch on or off
/// during a session, and a config that could not be fetched means "no beta" —
/// never a retry loop, and never a blocked launch. An app pointed at a backend
/// that predates these routes gets a 404 here and behaves exactly as it did
/// before the beta existed.
@MainActor
@Observable
public final class BetaStore {
    @ObservationIgnored private let client: APIClient

    public private(set) var config: BetaConfig = .off
    public private(set) var hasLoaded = false

    /// This install's upload token. Not a session and not an identity — it
    /// scopes an anonymous upload to whoever made it for the few minutes
    /// between choosing a screenshot and pressing send, and the server compares
    /// it against nothing but another copy of itself.
    @ObservationIgnored public let uploadToken: String

    private static let uploadTokenKey = "beta.uploadToken"

    public init(client: APIClient) {
        self.client = client
        if let stored = UserDefaults.standard.string(forKey: Self.uploadTokenKey) {
            uploadToken = stored
        } else {
            let minted = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            UserDefaults.standard.set(minted, forKey: Self.uploadTokenKey)
            uploadToken = minted
        }
    }

    public var isEnabled: Bool { config.enabled }

    /// Fetched once. Any failure is "no beta", deliberately — a tester on a
    /// flaky connection gets the app, not an error screen about a survey.
    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            config = try await client.send(
                Endpoint<BetaConfig>(path: "/beta/config", requiresAuth: false)
            )
        } catch {
            config = .off
        }
    }

    /// One invented-but-plausible person, different on every call, for the
    /// "fill this in for me" buttons. Different every call is the requirement:
    /// two testers pressing it in the same minute must not collide on a
    /// username, because the unique-constraint error the second one gets is
    /// exactly the dead end the button exists to remove.
    public func demoFill() async throws -> BetaDemoFill {
        try await client.send(
            Endpoint<BetaDemoFill>(path: "/beta/demo-fill", requiresAuth: false)
        )
    }

    public func upload(filename: String, contentType: String, data: Data) async throws -> BetaAttachment {
        var form = MultipartForm()
        form.addField("upload_token", value: uploadToken)
        form.addFile("file", filename: filename, contentType: contentType, data: data)
        return try await client.send(
            Endpoint<BetaAttachment>(
                method: .post,
                path: "/beta/attachments",
                body: .multipart(form),
                requiresAuth: false
            )
        )
    }

    public func submit(
        kind: String,
        answers: [String: BetaAnswer],
        appVersion: String?
    ) async throws -> BetaSubmissionReceipt {
        struct Payload: Encodable {
            let kind: String
            let answers: [String: BetaAnswer]
            let surface: String
            let uploadToken: String
            let appVersion: String?

            private enum CodingKeys: String, CodingKey {
                case kind, answers, surface
                case uploadToken = "upload_token"
                case appVersion = "app_version"
            }
        }
        // Built by hand rather than through `Endpoint.json`: that helper applies
        // `.convertToSnakeCase`, which would rewrite every question id in
        // `answers` — `bug_what_happened` survives it, but a future id in camel
        // case would not, and the server would refuse an answer the app believed
        // it had sent.
        let data = try JSONEncoder().encode(
            Payload(
                kind: kind,
                answers: answers,
                surface: "ios",
                uploadToken: uploadToken,
                appVersion: appVersion
            )
        )
        return try await client.send(
            Endpoint<BetaSubmissionReceipt>(
                method: .post,
                path: "/beta/feedback",
                body: .json(data),
                requiresAuth: false
            )
        )
    }

    // MARK: - The branching, applied on device
    //
    // `nonisolated` because all three are pure: they read their arguments and
    // nothing else. Inheriting the class's @MainActor would force every caller
    // — a filter inside a SwiftUI body, a test — onto the main actor for a
    // dictionary lookup, which is a constraint none of them earn.

    /// Whether a question's condition currently holds.
    ///
    /// Mirrors `show_when_holds` in `beta_program.py`, and it has to: a question
    /// the app shows and the server then refuses is an answer somebody typed
    /// and lost. The server re-checks every one of these and is the authority;
    /// this is what keeps the two from disagreeing in the direction that costs
    /// a tester their words.
    nonisolated public static func conditionHolds(
        _ question: BetaQuestion,
        answers: [String: BetaAnswer]
    ) -> Bool {
        guard let condition = question.showWhen else { return true }
        guard let parent = answers[condition.question] else { return false }
        return parent.matches(anyOf: condition.anyOf)
    }

    nonisolated public static func visibleQuestions(
        in section: BetaSection,
        answers: [String: BetaAnswer]
    ) -> [BetaQuestion] {
        section.questions.filter { conditionHolds($0, answers: answers) }
    }

    /// Answers that are not, by themselves, anybody saying anything.
    ///
    /// `contact_ok` and `email` are an address, not feedback. `bug_device` and
    /// `bug_browser` are worse: the app fills those in from the device the
    /// moment a tester picks a door, so counting them made the send button go
    /// live before a single question had been answered — and the server, which
    /// drops them along with the rest of the bug section when no bug was
    /// reported, then refused the submission the button had just offered.
    ///
    /// Mirrored by `NON_CONTENT_ANSWERS` in `beta_program.py` and in
    /// `frontend/src/lib/beta.ts`. All three have to agree.
    nonisolated public static let nonContentAnswers: Set<String> = [
        "contact_ok", "email", "bug_device", "bug_browser",
    ]

    /// Whether the send button should be live.
    nonisolated public static func hasAnyAnswer(_ answers: [String: BetaAnswer]) -> Bool {
        answers.contains { id, answer in
            !nonContentAnswers.contains(id) && !answer.isEmpty
        }
    }
}
