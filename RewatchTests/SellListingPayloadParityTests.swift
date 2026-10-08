import Foundation
import XCTest

@testable import Rewatch
@testable import RewatchKit

/// The app's builder sends the website's builder's body, key for key and value
/// for value.
///
/// `Fixtures/sell-listing-payload.json` was written by the SITE's own code
/// (`Scripts/sell-payload-fixture.ts` runs `builderListingPayload` from
/// listingBuilderModel.ts over the answers in the file), so the expected bodies
/// are not a Swift reading of the TypeScript: they are what the site sends.
/// Each case maps the same answers through `BuilderRules.body` and encodes it
/// exactly as `Endpoint.json` does.
final class SellListingPayloadParityTests: XCTestCase {
    private struct Case: Decodable {
        struct Answers: Decodable {
            struct Box: Decodable { let box: Bool; let papers: Bool; let booklets: Bool }
            struct History: Decodable { let polish: String?; let originality: String?; let serviceHistory: String? }
            struct Customs: Decodable { let country: String; let hts: String }
            let brand: String
            let model: String
            let reference: String
            let year: String
            let sku: String
            let grade: String?
            let partsMatch: Bool?
            let parts: [String: String]
            let conditionNotes: [String: String]
            let box: Box
            let notes: String
            let history: History
            let replaced: String
            let serviceYear: String
            let priceText: String
            let returns: String?
            let customs: Customs
            let vaultWatchId: String?
        }
        let name: String
        let needsCustomsFields: Bool
        let answers: Answers
    }

    private func fixture() throws -> (cases: [Case], expected: [[String: Any]]) {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "sell-listing-payload", withExtension: "json"),
            "The fixture is missing from the test bundle"
        )
        let data = try Data(contentsOf: url)
        let cases = try JSONDecoder().decode([Case].self, from: data)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let expected = try raw.map { try XCTUnwrap($0["expected"] as? [String: Any]) }
        return (cases, expected)
    }

    private func answers(_ given: Case.Answers) -> BuilderAnswers {
        var answers = BuilderAnswers()
        answers.brand = given.brand
        answers.model = given.model
        answers.reference = given.reference
        answers.year = given.year
        answers.sku = given.sku
        answers.grade = given.grade
        answers.partsMatch = given.partsMatch
        answers.parts = given.parts
        answers.conditionNotes = given.conditionNotes
        answers.box = given.box.box
        answers.papers = given.box.papers
        answers.booklets = given.box.booklets
        answers.notes = given.notes
        answers.polish = given.history.polish
        answers.originality = given.history.originality
        answers.serviceHistory = given.history.serviceHistory
        answers.replaced = given.replaced
        answers.serviceYear = given.serviceYear
        answers.priceText = given.priceText
        answers.returns = given.returns.flatMap(ReturnsChoice.init(rawValue:))
        answers.customsCountry = given.customs.country
        answers.customsHTS = given.customs.hts
        answers.vaultWatchID = given.vaultWatchId
        return answers
    }

    /// The bytes `Endpoint.json` puts on the wire for this body.
    private func wire(_ body: SellListingBody) throws -> [String: Any] {
        let endpoint: Endpoint<Listing> = try Endpoint.json(method: .post, path: "/account/listings", payload: body)
        guard case .json(let data) = endpoint.body else {
            XCTFail("The create call carries no JSON body")
            return [:]
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheFixtureHasEveryCase() throws {
        let (cases, expected) = try fixture()
        // Guard the loop below: a strict comparison over nothing is green.
        XCTAssertEqual(cases.count, 3)
        XCTAssertEqual(expected.count, cases.count)
    }

    func testEachBodyIsTheSitesBodyForTheSameAnswers() throws {
        let (cases, expected) = try fixture()
        XCTAssertFalse(cases.isEmpty)
        for (index, testCase) in cases.enumerated() {
            let body = BuilderRules.body(answers(testCase.answers), needsCustomsFields: testCase.needsCustomsFields)
            let sent = try wire(body)
            let want = expected[index]
            XCTAssertEqual(
                Set(sent.keys), Set(want.keys),
                "\(testCase.name): keys differ. Only the app: \(Set(sent.keys).subtracting(want.keys).sorted()); only the site: \(Set(want.keys).subtracting(sent.keys).sorted())"
            )
            for key in want.keys.sorted() {
                XCTAssertEqual(
                    sent[key].map { NSDictionary(dictionary: ["v": $0]) },
                    want[key].map { NSDictionary(dictionary: ["v": $0]) },
                    "\(testCase.name): \(key) is \(String(describing: sent[key])) here and \(String(describing: want[key])) on the site"
                )
            }
            XCTAssertEqual(NSDictionary(dictionary: sent), NSDictionary(dictionary: want), testCase.name)
        }
    }

    /// The three box answers travel beside the derived `box_papers`, and the
    /// follow-ups go as explicit nulls rather than missing keys: the server
    /// reads a missing key as "leave it" and a null as "clear it".
    func testTheNullsAndTheThreeBoxAnswersAreOnTheWire() throws {
        var answers = BuilderAnswers()
        answers.brand = "Tudor"
        answers.model = "Black Bay"
        answers.reference = "79230N"
        answers.year = "2020"
        answers.grade = "Good"
        answers.partsMatch = true
        answers.box = true
        answers.originality = "all_original"
        answers.serviceHistory = "never"
        answers.priceText = "2,000"
        answers.returns = ReturnsChoice.none
        let sent = try wire(BuilderRules.body(answers, needsCustomsFields: false))
        XCTAssertEqual(sent["box_papers"] as? Bool, false)
        XCTAssertEqual(sent["box_included"] as? Bool, true)
        XCTAssertEqual(sent["papers_included"] as? Bool, false)
        XCTAssertEqual(sent["booklets_included"] as? Bool, false)
        XCTAssertTrue(sent["replaced_parts_note"] is NSNull)
        XCTAssertTrue(sent["last_service_year"] is NSNull)
        XCTAssertNil(sent["polish"], "An unanswered question is left off")
        XCTAssertNil(sent["return_window_hours"])
        XCTAssertEqual((sent["condition_notes"] as? [String: Any])?.count, 0)
        XCTAssertEqual(sent["price"] as? Double, 2000)
    }
}
