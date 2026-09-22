import RewoundKit
import XCTest
@testable import Rewound

/// The beta program, on the app's side.
///
/// Two things carry the weight here.
///
/// The branching has to agree with the server's, exactly. A question the app
/// shows and the server then refuses is an answer somebody typed and lost, and
/// nothing goes red when it happens — the tester simply gets a 400 after
/// fifteen minutes of work.
///
/// And the survey has to survive being older than the catalog. This app ships
/// through TestFlight, which means a build from three weeks ago is still in
/// somebody's hands while the questions move underneath it.
final class BetaProgramTests: XCTestCase {

    // MARK: - Decoding

    /// The app's own decoder, never a fresh `JSONDecoder()`.
    ///
    /// This helper used a plain decoder, and that is how the beta was dark in
    /// every build. `APIClient.makeDecoder` converts snake_case keys before
    /// they are matched, so a model that also spelled its keys in snake_case
    /// (`catalogue_version`) could never find them: the decode threw,
    /// `BetaStore.load` read the throw as "no beta", and the app showed
    /// nothing while the site showed the bar. A plain decoder matched those
    /// keys literally, so every test here passed against a decode the app
    /// never performs.
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.makeDecoder(origin: nil).decode(type, from: Data(json.utf8))
    }

    func testAnOffConfigCarriesNothingAtAll() throws {
        let config = try decode(BetaConfig.self, #"{"enabled": false}"#)
        XCTAssertFalse(config.enabled)
        // Not merely `enabled: false` beside the copy. A client reading the
        // wrong key would otherwise show the welcome to somebody who was never
        // a tester.
        XCTAssertNil(config.welcome)
        XCTAssertNil(config.testCard)
        XCTAssertNil(config.form)
    }

    func testTheSnakeCasedKeysOnTheWireAreRead() throws {
        let config = try decode(BetaConfig.self, """
        {
          "enabled": true,
          "welcome": {"title": "Thanks", "body": ["One."], "signoff": "Moshe & Eytan"},
          "bar": {"text": "Beta", "action": "Give feedback"},
          "test_card": {
            "number": "4242 4242 4242 4242", "expiry": "10/29", "cvc": "207",
            "caption": "Your demo credit card", "note": "Not a real card."
          },
          "form": {
            "catalogue_version": "1",
            "kind_question": "What are you here to submit?",
            "kinds": [{"value": "bug", "label": "I found a bug"}],
            "sections": {"bug": []}
          }
        }
        """)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.testCard?.number, "4242 4242 4242 4242")
        XCTAssertEqual(config.form?.catalogueVersion, "1")
        XCTAssertEqual(config.form?.kindQuestion, "What are you here to submit?")
        XCTAssertEqual(config.welcome?.signoff, "Moshe & Eytan")
    }

    func testAQuestionTypeThisBuildHasNeverHeardOfDoesNotBreakDecoding() throws {
        // The whole reason `BetaQuestion.type` is a String rather than an enum.
        // A question type added to the catalog after this build shipped must
        // leave the other thirty-nine questions renderable — a throwing decode
        // here would empty the entire survey for every tester on an older
        // TestFlight build, silently.
        let question = try decode(BetaQuestion.self, """
        {"id": "future", "type": "ranking", "prompt": "Rank these"}
        """)
        XCTAssertEqual(question.id, "future")
        if case .unsupported = BetaAnswerKind(question.type) {
            // Correct: named, so the row can say so rather than draw nothing.
        } else {
            XCTFail("an unknown type must resolve to .unsupported, not to a shape it is not")
        }
    }

    func testEveryKnownTypeMapsToItsShape() {
        XCTAssertEqual(describe(BetaAnswerKind("single")), "single")
        XCTAssertEqual(describe(BetaAnswerKind("multi")), "multi")
        XCTAssertEqual(describe(BetaAnswerKind("scale")), "scale")
        XCTAssertEqual(describe(BetaAnswerKind("matrix")), "matrix")
        XCTAssertEqual(describe(BetaAnswerKind("files")), "files")
        XCTAssertEqual(describe(BetaAnswerKind("longtext")), "longtext")
        XCTAssertEqual(describe(BetaAnswerKind("text")), "text")
        XCTAssertEqual(describe(BetaAnswerKind("email")), "email")
    }

    private func describe(_ kind: BetaAnswerKind) -> String {
        switch kind {
        case .single: "single"
        case .multi: "multi"
        case .scale: "scale"
        case .text: "text"
        case .longtext: "longtext"
        case .email: "email"
        case .matrix: "matrix"
        case .files: "files"
        case .unsupported: "unsupported"
        }
    }

    // MARK: - Encoding

    func testAnAnswerEncodesAsItsOwnShapeAndNotAsAWrapper() throws {
        // The server validates by type: a string where it expects a list is a
        // refused submission. A wrapper object around each value would be
        // refused for every answer at once.
        let encoded = try JSONEncoder().encode([
            "first_impression": BetaAnswer.text("A watch marketplace"),
            "overall_rating": .number(9),
            "brand_words": .choices(["premium", "modern"]),
            "feature_value": .matrix(["saving_watches": "important"]),
        ])
        let decoded = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(decoded?["first_impression"] as? String, "A watch marketplace")
        XCTAssertEqual(decoded?["overall_rating"] as? Int, 9)
        XCTAssertEqual(decoded?["brand_words"] as? [String], ["premium", "modern"])
        XCTAssertEqual(
            decoded?["feature_value"] as? [String: String],
            ["saving_watches": "important"]
        )
    }

    func testAQuestionIdIsSentExactlyAsTheCatalogueSpelledIt() throws {
        // `Endpoint.json` applies `.convertToSnakeCase`, which rewrites keys —
        // and the keys here are question ids, not field names. `BetaStore`
        // encodes the payload by hand for this reason; if that ever reverts,
        // a camel-cased id would arrive as something the server does not know
        // and the answer would be dropped without a word.
        let encoded = try JSONEncoder().encode(["bugWhatHappened": BetaAnswer.text("x")])
        let decoded = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertNotNil(decoded?["bugWhatHappened"], "the question id was rewritten in transit")
    }

    // MARK: - The branching

    private func question(
        id: String,
        type: String = "text",
        showWhen: (question: String, anyOf: [String])? = nil
    ) throws -> BetaQuestion {
        var json = #"{"id": "\#(id)", "type": "\#(type)", "prompt": "?"#
        json += #"""#
        if let showWhen {
            let values = showWhen.anyOf.map { "\"\($0)\"" }.joined(separator: ",")
            json += #", "show_when": {"question": "\#(showWhen.question)", "any_of": [\#(values)]}"#
        }
        json += "}"
        return try decode(BetaQuestion.self, json)
    }

    func testAConditionHoldsOnlyWhenItsParentSaysSo() throws {
        let child = try question(id: "bug_where_other", showWhen: (question: "bug_where", anyOf: ["other"]))

        XCTAssertFalse(BetaStore.conditionHolds(child, answers: [:]))
        XCTAssertFalse(BetaStore.conditionHolds(child, answers: ["bug_where": .text("checkout")]))
        XCTAssertTrue(BetaStore.conditionHolds(child, answers: ["bug_where": .text("other")]))
    }

    func testAMultiAnswerSatisfiesAConditionByContainingTheValue() throws {
        let child = try question(id: "where_other", showWhen: (question: "bought_sold_where", anyOf: ["other"]))
        XCTAssertFalse(BetaStore.conditionHolds(child, answers: ["bought_sold_where": .choices(["chrono24"])]))
        XCTAssertTrue(BetaStore.conditionHolds(child, answers: ["bought_sold_where": .choices(["chrono24", "other"])]))
    }

    func testAnUnconditionalQuestionIsAlwaysShown() throws {
        let plain = try question(id: "first_impression", type: "longtext")
        XCTAssertTrue(BetaStore.conditionHolds(plain, answers: [:]))
    }

    func testASectionIsFilteredDownToWhatIsCurrentlyVisible() throws {
        let section = try decode(BetaSection.self, """
        {
          "id": "bug", "title": "Anything broken",
          "questions": [
            {"id": "bug_where", "type": "single", "prompt": "Where?",
             "options": [{"value": "checkout", "label": "Checkout"}, {"value": "other", "label": "Other"}]},
            {"id": "bug_where_other", "type": "text", "prompt": "Which?",
             "show_when": {"question": "bug_where", "any_of": ["other"]}}
          ]
        }
        """)

        let hidden = BetaStore.visibleQuestions(in: section, answers: ["bug_where": .text("checkout")])
        XCTAssertEqual(hidden.map(\.id), ["bug_where"])

        let shown = BetaStore.visibleQuestions(in: section, answers: ["bug_where": .text("other")])
        XCTAssertEqual(shown.map(\.id), ["bug_where", "bug_where_other"])
    }

    // MARK: - What counts as an answer

    func testAnEmailAndAYesIsAnAddressNotFeedback() {
        // The server refuses this submission. Offering the button would hand a
        // tester an error for something they did right.
        XCTAssertFalse(BetaStore.hasAnyAnswer([
            "contact_ok": .text("yes"),
            "email": .text("tester@example.com"),
        ]))
    }

    func testTheDeviceWeDetectedIsNotSomethingTheTesterSaid() {
        // Found by opening the form in a browser. The app prefills these from
        // the device the moment a door is chosen, so while they counted, the
        // send button went live before a single question had been answered —
        // and the server, which drops them with the rest of the bug section
        // when no bug was reported, refused the submission the button had just
        // offered. The tester's first action produced an error.
        XCTAssertFalse(BetaStore.hasAnyAnswer([
            "bug_device": .text("iphone"),
            "bug_browser": .text("rewound_ios_app"),
        ]))
        // Beside one real sentence the whole thing counts, as it should.
        XCTAssertTrue(BetaStore.hasAnyAnswer([
            "bug_device": .text("iphone"),
            "bug_what_happened": .text("Checkout spun"),
        ]))
    }

    func testTheThreeClientsAgreeOnWhatIsNotContent() {
        // The same four ids as `NON_CONTENT_ANSWERS` in beta_program.py and in
        // frontend/src/lib/beta.ts. A list that drifts means one surface offers
        // a send another refuses.
        XCTAssertEqual(
            BetaStore.nonContentAnswers,
            ["contact_ok", "email", "bug_device", "bug_browser"]
        )
    }

    func testAZeroIsAnAnswer() {
        // "Not at all likely" is the bottom of a 0–10 scale and the single most
        // important answer in the survey. Treating it as empty would drop it.
        XCTAssertTrue(BetaStore.hasAnyAnswer(["purchase_likelihood": .number(0)]))
    }

    func testAnEmptyOrWhitespaceAnswerDoesNotCount() {
        XCTAssertFalse(BetaStore.hasAnyAnswer([:]))
        XCTAssertFalse(BetaStore.hasAnyAnswer(["first_impression": .text("   ")]))
        XCTAssertFalse(BetaStore.hasAnyAnswer(["brand_words": .choices([])]))
        XCTAssertFalse(BetaStore.hasAnyAnswer(["feature_value": .matrix([:])]))
    }

    func testAnythingElseCounts() {
        XCTAssertTrue(BetaStore.hasAnyAnswer(["first_impression": .text("A watch marketplace")]))
        XCTAssertTrue(BetaStore.hasAnyAnswer(["brand_words": .choices(["premium"])]))
        XCTAssertTrue(BetaStore.hasAnyAnswer(["feature_value": .matrix(["saving_watches": "important"])]))
    }
}
