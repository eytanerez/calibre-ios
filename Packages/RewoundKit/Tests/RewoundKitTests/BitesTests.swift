import Foundation
import XCTest
@testable import CalibreKit

/// `GET /content/bites/today`, `/content/bites` and `/content/bites/{slug}`,
/// recorded from the running API.
///
/// The answer that matters most here is the one the format was designed
/// around: an archive-slot Bite carries its own original date rather than
/// today's, and a correction is added beside that date rather than replacing
/// it.
final class BitesTests: XCTestCase {

    /// The `{slot, bite}` answer `GET /content/bites/today` gives.
    ///
    /// This app reads today's Bite off the Home feed's own `todays_bite`
    /// module, which carries the same two keys, so the standalone endpoint's
    /// envelope is asserted here rather than modelled in the client.
    private struct TodaysSlot: Decodable {
        let slot: String
        let bite: Bite?
    }

    func testTodaysSlotDecodesWithTheSourcesItWasPublishedAgainst() throws {
        let today = try apiDecoder().decode(
            Envelope<TodaysSlot>.self,
            from: fixtureData("bites-today")
        ).data

        XCTAssertEqual(today.slot, "fresh")
        let bite = try XCTUnwrap(today.bite)
        XCTAssertFalse(bite.title.isEmpty)
        XCTAssertFalse(bite.body.isEmpty)
        XCTAssertFalse(bite.isArchive)
        XCTAssertFalse(bite.archived)
        XCTAssertFalse(bite.sources.isEmpty, "A Bite with no sources is not a sourced claim.")
        for source in bite.sources {
            XCTAssertFalse(source.label.isEmpty)
            XCTAssertNotNil(URL(string: source.href))
        }
        XCTAssertNotNil(bite.datePublishedISO)
        XCTAssertNil(bite.correctedOn)
    }

    func testTheArchiveListPagesBackwardsOnTheEditorialDate() throws {
        let page = try apiDecoder().decode(
            Envelope<BiteArchivePage>.self,
            from: fixtureData("bites-archive")
        ).data

        XCTAssertFalse(page.results.isEmpty, "An empty recording would make the ordering check vacuous.")
        let dates = page.results.compactMap(\.datePublishedISO)
        XCTAssertEqual(dates.count, page.results.count)
        XCTAssertEqual(dates, dates.sorted(by: >), "The archive is newest first.")
        if let next = page.nextBefore {
            XCTAssertEqual(next, dates.last)
        }
    }

    func testAnArchiveSlotBiteKeepsItsOwnOriginalDate() throws {
        // Fixed dates, not `Date.now`: the point of the assertion is that
        // nothing rewrites a publication date to simulate freshness, and a
        // test that computed today's date could not tell the two apart.
        let json = """
        {"slot": "archive",
         "bite": {"id": "papers-prove-less-than-you-think",
           "title": "A warranty card proves a sale happened.",
           "topic": "provenance", "body": "Box and papers reliably raise what a watch sells for.",
           "author": "Calibre Desk", "date": "June 18, 2026", "datePublishedISO": "2026-06-18",
           "isArchive": true, "archived": false, "image": null, "imageAlt": null,
           "sources": [{"href": "https://buycalibre.com/journal", "label": "The Calibre Journal"}],
           "article": null, "next": null, "correctedOn": null, "correctionNote": null}}
        """
        let today = try apiDecoder().decode(TodaysSlot.self, from: Data(json.utf8))
        let bite = try XCTUnwrap(today.bite)

        XCTAssertEqual(today.slot, "archive")
        XCTAssertTrue(bite.isArchive)
        XCTAssertEqual(bite.datePublishedISO, "2026-06-18")
        XCTAssertEqual(bite.date, "June 18, 2026")
    }

    func testACorrectionSitsBesideTheOriginalDateRatherThanReplacingIt() throws {
        let json = """
        {"id": "s", "title": "T", "topic": "market", "body": "B", "author": "A",
         "date": "June 18, 2026", "datePublishedISO": "2026-06-18", "isArchive": false,
         "archived": false, "image": null, "imageAlt": null,
         "sources": [{"href": "https://buycalibre.com/market", "label": "Calibre completed sales"}],
         "article": {"id": "a", "title": "The long version"},
         "next": {"label": "See the market data", "href": "/market"},
         "correctedOn": "2026-06-20", "correctionNote": "The figure was for August, not July."}
        """
        let bite = try apiDecoder().decode(Bite.self, from: Data(json.utf8))

        XCTAssertEqual(bite.datePublishedISO, "2026-06-18")
        XCTAssertEqual(bite.correctedOn, "2026-06-20")
        XCTAssertEqual(bite.correctionNote, "The figure was for August, not July.")
        XCTAssertEqual(bite.article?.id, "a")
        XCTAssertEqual(bite.next?.href, "/market")
    }
}
