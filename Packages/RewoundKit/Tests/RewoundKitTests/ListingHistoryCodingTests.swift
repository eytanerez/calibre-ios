import Foundation
import XCTest
@testable import RewoundKit

/// `history` (contracts, 2026-09-30, Part A) through the coders the app
/// actually uses.
///
/// The API decoder converts snake keys to camel before matching, and a
/// hand-written snake `CodingKey` would cancel that out silently (the beta
/// programme was dark for a week that way). So the wire side runs through
/// `APIClient.makeDecoder` and `Endpoint.json`, never a plain `JSONDecoder`.
final class ListingHistoryCodingTests: XCTestCase {

    /// A recorded capture with `history` set to `value` on the listing (or on
    /// every result of a page), or with the key removed when `value` is nil.
    private func payload(_ fixture: String, history value: Any?) throws -> Data {
        let raw = try fixtureData(fixture)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var data = try XCTUnwrap(envelope["data"] as? [String: Any])
        if var results = data["results"] as? [[String: Any]] {
            XCTAssertFalse(results.isEmpty, "the capture has no cards to put history on")
            for index in results.indices { results[index]["history"] = value }
            data["results"] = results
        } else {
            data["history"] = value
        }
        envelope["data"] = data
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    nonisolated(unsafe) private static let full: [String: Any] = [
        "polish": "unpolished",
        "originality": "replaced",
        "replaced_parts_note": "Crown and crystal, fitted by the brand",
        "service_history": "serviced",
        "last_service_year": 2021,
    ]

    // MARK: - Wire to model

    func testTheDetailPayloadsHistoryDecodesEveryField() throws {
        let listing = try apiDecoder()
            .decode(Envelope<Listing>.self, from: payload("listing-detail", history: Self.full))
            .data
        let history = try XCTUnwrap(listing.history)

        XCTAssertEqual(history.polish, "unpolished")
        XCTAssertEqual(history.originality, "replaced")
        XCTAssertEqual(history.replacedPartsNote, "Crown and crystal, fitted by the brand")
        XCTAssertEqual(history.serviceHistory, "serviced")
        XCTAssertEqual(history.lastServiceYear, 2021)
        // Beside it, nothing else moved.
        XCTAssertNotNil(listing.condition?.overall)
    }

    /// The card view carries the same object, on every card.
    func testTheCardPagesHistoryDecodesOnEveryCard() throws {
        let page = try apiDecoder()
            .decode(Envelope<PageResponse<Listing>>.self, from: payload("listings-card", history: Self.full))
            .data
        XCTAssertFalse(page.results.isEmpty)
        for listing in page.results {
            XCTAssertEqual(listing.history?.polish, "unpolished", listing.id)
            XCTAssertEqual(listing.history?.lastServiceYear, 2021, listing.id)
        }
    }

    /// Old responses lack the key: the listing still decodes, with no history.
    func testAnAbsentOrNullHistoryIsNil() throws {
        let absent = try apiDecoder()
            .decode(Envelope<Listing>.self, from: payload("listing-detail", history: nil))
            .data
        XCTAssertNil(absent.history)

        let null = try apiDecoder()
            .decode(Envelope<Listing>.self, from: payload("listing-detail", history: NSNull()))
            .data
        XCTAssertNil(null.history)

        let cards = try apiDecoder()
            .decode(Envelope<PageResponse<Listing>>.self, from: payload("listings-card", history: nil))
            .data
        XCTAssertFalse(cards.results.isEmpty)
        XCTAssertTrue(cards.results.allSatisfy { $0.history == nil })
    }

    /// "Nobody asked" is null inside the object; each answer stands alone.
    func testNullAnswersAreNilAndTheRestStand() throws {
        let partial: [String: Any] = [
            "polish": NSNull(),
            "originality": "unknown",
            "replaced_parts_note": NSNull(),
            "service_history": "never",
            "last_service_year": NSNull(),
        ]
        let history = try XCTUnwrap(
            apiDecoder().decode(Envelope<Listing>.self, from: payload("listing-detail", history: partial)).data.history
        )
        XCTAssertEqual(history, ListingHistory(originality: "unknown", serviceHistory: "never"))
    }

    /// One odd value costs that one answer, never the listing: a word from a
    /// newer server reads as not asked, a year sent as text is still a year,
    /// and a blank note is no note.
    func testOddValuesCostOneAnswerNotTheListing() throws {
        let odd: [String: Any] = [
            "polish": "lightly_polished",
            "originality": "all_original",
            "replaced_parts_note": "   ",
            "service_history": "serviced",
            "last_service_year": "2019",
        ]
        let history = try XCTUnwrap(
            apiDecoder().decode(Envelope<Listing>.self, from: payload("listing-detail", history: odd)).data.history
        )
        XCTAssertNil(history.polish)
        XCTAssertEqual(history.originality, "all_original")
        XCTAssertNil(history.replacedPartsNote)
        XCTAssertEqual(history.serviceHistory, "serviced")
        XCTAssertEqual(history.lastServiceYear, 2019)
    }

    /// The home feed and metadata caches write models with a plain encoder
    /// and read them back with a plain decoder. The answers survive that.
    func testHistorySurvivesTheDiskCacheRoundTrip() throws {
        let listing = try apiDecoder()
            .decode(Envelope<Listing>.self, from: payload("listing-detail", history: Self.full))
            .data
        let data = try JSONEncoder().encode(listing)
        let back = try JSONDecoder().decode(Listing.self, from: data)
        XCTAssertEqual(back.history, listing.history)
        XCTAssertNotNil(back.history)
    }

    // MARK: - Model to wire

    private func encodedBody(_ payload: ListingDraftPayload) throws -> [String: Any] {
        let endpoint: Endpoint<Listing> = try .json(method: .patch, path: "/account/listings/l1", payload: payload)
        guard case .json(let data) = endpoint.body else {
            XCTFail("A listing PATCH carries a JSON body")
            return [:]
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheAnswersGoOutUnderTheContractsSnakeKeys() throws {
        let body = try encodedBody(ListingDraftPayload(
            polish: "polished",
            originality: "replaced",
            replacedPartsNote: .value("Crown"),
            serviceHistory: "serviced",
            lastServiceYear: .value(2022)
        ))
        XCTAssertEqual(body["polish"] as? String, "polished")
        XCTAssertEqual(body["originality"] as? String, "replaced")
        XCTAssertEqual(body["replaced_parts_note"] as? String, "Crown")
        XCTAssertEqual(body["service_history"] as? String, "serviced")
        XCTAssertEqual(body["last_service_year"] as? Int, 2022)
        for camel in ["replacedPartsNote", "serviceHistory", "lastServiceYear"] {
            XCTAssertNil(body[camel], "the property name \(camel) must not reach the wire")
        }
    }

    /// Nil leaves a key off (a PATCH that leaves the answer alone); `.null`
    /// says null out loud (a PATCH that clears it).
    func testNilIsLeftOffAndNullIsSent() throws {
        let untouched = try encodedBody(ListingDraftPayload(conditionOverall: "Good"))
        for key in ["polish", "originality", "replaced_parts_note", "service_history", "last_service_year"] {
            XCTAssertFalse(untouched.keys.contains(key), "\(key) went out on a payload that never set it")
        }

        let cleared = try encodedBody(ListingDraftPayload(
            originality: "replaced",
            replacedPartsNote: .null,
            serviceHistory: "serviced",
            lastServiceYear: .null
        ))
        XCTAssertTrue(cleared["replaced_parts_note"] is NSNull)
        XCTAssertTrue(cleared["last_service_year"] is NSNull)
        XCTAssertFalse(cleared.keys.contains("polish"))
    }
}
