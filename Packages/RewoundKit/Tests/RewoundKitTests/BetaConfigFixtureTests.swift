import Foundation
import XCTest
@testable import RewoundKit

/// The recorded `/beta/config`, through the decoder the app actually uses.
///
/// This exists because the beta was dark in every build while the site showed
/// its bar. `APIClient.makeDecoder` converts snake_case keys before they are
/// matched, and the beta models also spelled their keys in snake_case
/// (`catalogue_version`), so they could never be found. The decode threw,
/// `BetaStore.load` reads any throw as "no beta" on purpose, and the only
/// tests decoded with a plain `JSONDecoder()` — which matched the keys
/// literally, and passed.
///
/// So this decodes a real server response, not a hand-written one, and it
/// checks the fields that fail *quietly* as well as the ones that throw. A
/// scale question with no labels or a checklist with no cap decodes without
/// complaint and just renders wrong.
final class BetaConfigFixtureTests: XCTestCase {

    private func config() throws -> BetaConfig {
        let envelope = try apiDecoder().decode(
            Envelope<BetaConfig>.self,
            from: fixtureData("beta-config")
        )
        XCTAssertTrue(envelope.ok)
        return envelope.data
    }

    func testTheRecordedConfigDecodesWithTheAppsDecoder() throws {
        let config = try config()
        XCTAssertTrue(
            config.enabled,
            "beta-config.json was recorded with the programme off. Re-record it against a backend running REWOUND_BETA_PROGRAM=true."
        )
        XCTAssertNotNil(config.welcome)
        XCTAssertNotNil(config.bar)
        XCTAssertNotNil(config.testCard, "test_card is the one top-level key spelled in snake_case")
    }

    func testTheFormDecodesEveryDoorItOffers() throws {
        let form = try XCTUnwrap(try config().form)
        XCTAssertFalse(form.catalogueVersion.isEmpty)
        XCTAssertFalse(form.kindQuestion.isEmpty)
        // Every door the tester is offered has a section list behind it, and
        // the section keys keep their underscores (`full_test`): the key
        // strategy converts coding keys, not the keys of a dictionary.
        XCTAssertFalse(form.kinds.isEmpty)
        for kind in form.kinds {
            let sections = try XCTUnwrap(form.sections[kind.value], "no sections for door \(kind.value)")
            XCTAssertFalse(sections.isEmpty, "door \(kind.value) has no sections")
        }
    }

    /// The keys that fail silently. Each one is optional, so a key that is
    /// never matched decodes as nil and the question renders without it.
    func testTheQuietlyOptionalKeysArrive() throws {
        let form = try XCTUnwrap(try config().form)
        let questions = form.sections.values.flatMap { $0.flatMap(\.questions) }
        XCTAssertFalse(questions.isEmpty)

        let scale = try XCTUnwrap(questions.first { $0.type == "scale" }, "the recorded form has no scale question")
        XCTAssertNotNil(scale.minLabel, "\(scale.id) lost min_label")
        XCTAssertNotNil(scale.maxLabel, "\(scale.id) lost max_label")

        XCTAssertTrue(
            questions.contains { $0.maxSelect != nil },
            "no question kept max_select; every checklist would be uncapped"
        )

        let conditional = try XCTUnwrap(questions.first { $0.showWhen != nil }, "no question kept show_when")
        let condition = try XCTUnwrap(conditional.showWhen)
        XCTAssertFalse(condition.question.isEmpty)
        XCTAssertFalse(condition.anyOf.isEmpty, "\(conditional.id) lost any_of, so it could never be shown")
    }
}
