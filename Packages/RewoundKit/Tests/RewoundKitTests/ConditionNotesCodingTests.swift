import Foundation
import XCTest
@testable import RewoundKit

/// `condition_notes` through the two coders the app actually uses.
///
/// The decoder converts snake keys to camel before matching them, the encoder
/// converts camel keys to snake after, and a hand-written snake `CodingKey`
/// cancels either one out silently (the beta programme was dark for a week
/// that way). So every assertion here runs through `APIClient.makeDecoder`
/// and `Endpoint.json`, never through a plain `JSONDecoder`, which would
/// match the snake key literally and pass whatever the model said.
final class ConditionNotesCodingTests: XCTestCase {

    private static let notes = [
        "case": "Light hairlines on the clasp side",
        "dial": "A speck at six, visible under a loupe",
    ]

    /// The recorded listing-detail capture with `condition_notes` set to
    /// `value`, or with the key removed when `value` is nil.
    private func detailPayload(conditionNotes value: Any?) throws -> Data {
        let raw = try fixtureData("listing-detail")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var data = try XCTUnwrap(envelope["data"] as? [String: Any])
        data["condition_notes"] = value
        envelope["data"] = data
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private func encodedBody(_ payload: ListingDraftPayload) throws -> [String: Any] {
        let endpoint: Endpoint<Listing> = try .json(method: .patch, path: "/account/listings/l1", payload: payload)
        guard case .json(let data) = endpoint.body else {
            XCTFail("A listing PATCH carries a JSON body")
            return [:]
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Wire to model

    func testTheDetailPayloadsNotesDecodeWithTheirPartKeysIntact() throws {
        let listing = try apiDecoder()
            .decode(Envelope<Listing>.self, from: detailPayload(conditionNotes: Self.notes))
            .data

        XCTAssertEqual(listing.conditionNotes, Self.notes)
        // And `condition` is untouched beside it: still the flat part -> grade
        // map every client reads.
        XCTAssertNotNil(listing.condition?.overall)
    }

    /// Absent and empty are two different answers. A card payload (and a
    /// server that predates the key) carries no key at all; a listing with no
    /// notes carries `{}`.
    func testAnAbsentKeyIsNilAndAnEmptyMapIsEmpty() throws {
        let absent = try apiDecoder()
            .decode(Envelope<Listing>.self, from: detailPayload(conditionNotes: nil))
            .data
        XCTAssertNil(absent.conditionNotes)

        let empty = try apiDecoder()
            .decode(Envelope<Listing>.self, from: detailPayload(conditionNotes: [String: String]()))
            .data
        XCTAssertEqual(empty.conditionNotes, [:])
    }

    // MARK: - Model to wire

    func testThePayloadSendsConditionNotesUnderTheSnakeKeyWithPartKeysUnchanged() throws {
        let body = try encodedBody(ListingDraftPayload(conditionNotes: Self.notes))

        XCTAssertNil(body["conditionNotes"], "the property name must not reach the wire")
        let sent = try XCTUnwrap(body["condition_notes"] as? [String: String])
        XCTAssertEqual(sent, Self.notes)
        XCTAssertEqual(Set(sent.keys), ["case", "dial"])
    }

    /// The server replaces its stored map with whatever arrives, so "no notes
    /// any more" has to be said out loud, and "I never showed the seller their
    /// notes" has to say nothing at all.
    func testAnEmptyMapIsSentAndNilIsLeftOff() throws {
        let cleared = try encodedBody(ListingDraftPayload(conditionNotes: [:]))
        XCTAssertEqual(cleared["condition_notes"] as? [String: String], [:])

        let untouched = try encodedBody(ListingDraftPayload(conditionOverall: "Good"))
        XCTAssertFalse(untouched.keys.contains("condition_notes"))
        XCTAssertEqual(untouched["condition_overall"] as? String, "Good")
    }

    // MARK: - Both directions

    /// What the wizard does on an edit: read the listing, send the notes it
    /// holds back. Every part name has to arrive where it started.
    func testNotesSurviveTheRoundTripForEveryPartName() throws {
        let everyPart = Dictionary(
            uniqueKeysWithValues: ["overall", "case", "dial", "bezel", "crystal", "bracelet", "clasp", "caseback"]
                .map { ($0, "Note on the \($0)") }
        )
        let read = try apiDecoder()
            .decode(Envelope<Listing>.self, from: detailPayload(conditionNotes: everyPart))
            .data
        let held = try XCTUnwrap(read.conditionNotes)

        let body = try encodedBody(ListingDraftPayload(conditionNotes: held))
        XCTAssertEqual(body["condition_notes"] as? [String: String], everyPart)
    }
}
