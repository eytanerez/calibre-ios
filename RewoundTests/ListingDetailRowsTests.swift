import XCTest

@testable import Rewound
@testable import RewoundKit

/// "The details" on a listing: which rows carry a (?), and that each (?) finds
/// its sentence.
///
/// `ListingSpecs.rows` hands the table labels, not keys, so the key behind
/// each (?) is put back from the label. A label renamed in RewoundKit and not
/// in `ListingDetailRows.specKeyByLabel` would print the row without its (?)
/// and nothing would look broken; these tests are what notice.
final class ListingDetailRowsTests: XCTestCase {

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// All sixteen spec fields filled, so `rows` prints every label it has.
    private func fullSpecs() throws -> ListingSpecs {
        let json = """
        {
          "material": "Oystersteel", "bezel": "Unidirectional ceramic", "glass": "Sapphire",
          "back": "Solid", "shape": "Round", "diameter_mm": 41, "finish": "Brushed and polished",
          "dial": "Black", "indexes": "Dots and batons", "hands": "Mercedes",
          "movement": "Automatic", "calibre": "3235", "bracelet": "Oyster",
          "thickness_mm": 12.5, "lug_width_mm": 21, "water_resistance_m": 300
        }
        """
        return try decoder().decode(ListingSpecs.self, from: Data(json.utf8))
    }

    func testEverySpecRowFindsItsSentence() throws {
        let rows = ListingDetailRows.specRows(try fullSpecs())
        // A loop over nothing passes everything: the sixteen are there first.
        XCTAssertEqual(rows.count, 16)
        for row in rows {
            let key = try XCTUnwrap(row.helpKey, "\(row.label) has no spec key, so no (?)")
            XCTAssertNotNil(SpecHelp.sentences[key], "\(row.label) → \(key) has no sentence")
        }
        // And every sentence in the shared wording is reachable from a row:
        // the sixteen specs here, the rest from the listing's own columns
        // (`testEveryRowButBrandAndModelIsExplained` below).
        let reached = Set(rows.compactMap(\.helpKey))
            .union(["reference", "year", "box", "papers", "booklets", "box_papers"])
        XCTAssertEqual(reached, Set(SpecHelp.sentences.keys))
    }

    func testEveryExplainedRowHasAQuestionForVoiceOver() {
        XCTAssertFalse(SpecHelp.sentences.isEmpty)
        for key in SpecHelp.sentences.keys {
            XCTAssertNotNil(ListingDetailRows.questions[key], "\(key) has no VoiceOver question")
        }
    }

    /// Brand and Model get no (?) (Eytan, 2026-09-29); every other row does,
    /// the box, papers and booklets answers included.
    func testEveryRowButBrandAndModelIsExplained() throws {
        let json = """
        {
          "id": "detail-rows-1", "listing_number": 9101, "seller_id": "seller-1",
          "title": "Submariner Date", "brand": "Rolex", "model": "Submariner Date",
          "reference_number": "126610LN", "price": "14200.00", "currency": "USD",
          "production_year": 2023, "status": "active", "images": [],
          "box_included": true, "papers_included": true, "booklets_included": false,
          "specs": { "material": "Oystersteel", "diameter_mm": 41 }
        }
        """
        let listing = try decoder().decode(Listing.self, from: Data(json.utf8))
        let rows = ListingDetailRows.rows(for: listing)
        let byLabel = Dictionary(uniqueKeysWithValues: rows.map { ($0.label, $0) })

        XCTAssertEqual(rows.map(\.label), [
            "Brand", "Model", "Reference", "Year", "Box", "Papers", "Booklets", "Case material", "Diameter",
        ])
        XCTAssertNil(byLabel["Brand"]?.helpKey)
        XCTAssertNil(byLabel["Model"]?.helpKey)
        XCTAssertEqual(byLabel["Reference"]?.helpKey, "reference")
        XCTAssertEqual(byLabel["Year"]?.helpKey, "year")
        XCTAssertEqual(byLabel["Case material"]?.helpKey, "material")
        XCTAssertEqual(byLabel["Diameter"]?.value, "41mm")
        XCTAssertEqual(byLabel["Diameter"]?.helpKey, "diameter_mm")
        XCTAssertEqual(byLabel["Box"]?.helpKey, "box")
        XCTAssertEqual(byLabel["Papers"]?.helpKey, "papers")
        XCTAssertEqual(byLabel["Booklets"]?.helpKey, "booklets")
        for row in rows where row.label != "Brand" && row.label != "Model" {
            let key = try XCTUnwrap(row.helpKey, "\(row.label) has no (?)")
            XCTAssertNotNil(SpecHelp.sentences[key], "\(row.label) → \(key) has no sentence")
        }
    }

    /// A listing from before the box question was split carries one bit, and
    /// its one row is explained too.
    func testTheOldBoxAndPapersRowIsExplained() throws {
        let json = """
        {
          "id": "detail-rows-2", "listing_number": 9102, "seller_id": "seller-1",
          "title": "Explorer", "brand": "Rolex", "model": "Explorer",
          "price": "8125.00", "currency": "USD", "status": "active", "images": [],
          "box_papers": true
        }
        """
        let listing = try decoder().decode(Listing.self, from: Data(json.utf8))
        let rows = ListingDetailRows.rows(for: listing)
        XCTAssertEqual(rows.map(\.label), ["Brand", "Model", "Box & papers"])
        XCTAssertEqual(rows.last?.helpKey, "box_papers")
    }
}
