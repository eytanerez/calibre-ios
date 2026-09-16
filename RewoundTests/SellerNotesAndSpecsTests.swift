import XCTest

@testable import Rewound
@testable import RewoundKit

/// The description became prose, and the spec sheet became a payload.
///
/// Both halves of one change: the sell form stopped writing a copy of every
/// answer into the description, and the server started sending `specs`. What
/// these tests hold is the two things that go wrong if either half is read the
/// old way — a seller's sentence eaten by a colon, and a spec row printed
/// without its unit.
final class SellerNotesAndSpecsTests: XCTestCase {

    // MARK: - The seller's own words

    /// Exactly what `listingDescription()` used to write.
    private let generated = """
    Brand: Rolex
    Model: Submariner
    Reference Number: 126610LN
    Condition: Like New
    Case Condition: Like New
    Dial Condition: New
    Year of Manufacture: 2023
    Box: Included
    Papers: Included
    Booklets: Not included
    Seller Notes: Worn a handful of times.
    Marketplace Status: Pending admin approval
    """

    func testTheGeneratedBlockLeavesOnlyTheSellersNotes() {
        XCTAssertEqual(SellerNotes(generated).text, "Worn a handful of times.")
    }

    func testAColonInsideTheNotesSurvives() {
        // THE bug this replaced. The old parser split every line on its first
        // colon and treated anything with a plausible label as a spec, so
        // "Serviced 2025: full service" became a spec row called
        // "Serviced 2025" and vanished from the seller's own notes. Harmless
        // while descriptions were generated; a deleted sentence the moment they
        // became prose.
        let source = "Seller Notes: Serviced 2025: full service, new gaskets."
        XCTAssertEqual(SellerNotes(source).text, "Serviced 2025: full service, new gaskets.")
    }

    func testAProseSentenceContainingAColonIsKeptWhole() {
        let source = "One owner from new: bought at an AD in 2023 and worn on weekends."
        XCTAssertEqual(SellerNotes(source).text, source)
    }

    func testADealersOwnSpecLinesAreNotDeleted() {
        // A CSV import's description is whatever the dealer wrote. Only the
        // keys OUR form generated are dropped.
        let source = "Movement: Automatic\nCase: 41mm steel\nA lovely honest watch."
        XCTAssertEqual(SellerNotes(source).text, source)
    }

    func testASellerWhoWroteNothingIsLeftWithNothing() {
        let withoutNotes = generated
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("Seller Notes:") }
            .joined(separator: "\n")
        XCTAssertEqual(SellerNotes(withoutNotes).text, "")
    }

    func testNothingInNothingOut() {
        XCTAssertEqual(SellerNotes(nil).text, "")
        XCTAssertEqual(SellerNotes("").text, "")
        XCTAssertEqual(SellerNotes("   \n\n ").text, "")
    }

    func testLeadingBlanksDoNotPushTheNotesDownThePage() {
        XCTAssertEqual(SellerNotes("Brand: Rolex\n\n\nSeller Notes: Tidy.").text, "Tidy.")
    }

    func testParagraphBreaksInsideKeptProseSurvive() {
        XCTAssertEqual(SellerNotes("First.\n\nSecond.").text, "First.\n\nSecond.")
    }

    // MARK: - The spec sheet

    private func specs(
        material: String? = nil,
        dial: String? = nil,
        diameterMm: Int? = nil,
        thicknessMm: Double? = nil,
        lugWidthMm: Int? = nil,
        waterResistanceM: Int? = nil,
        movement: String? = nil
    ) throws -> ListingSpecs {
        // Decoded rather than constructed, so the snake_case keys the server
        // actually sends are what is under test.
        let payload: [String: Any?] = [
            "material": material, "dial": dial, "diameter_mm": diameterMm,
            "thickness_mm": thicknessMm, "lug_width_mm": lugWidthMm,
            "water_resistance_m": waterResistanceM, "movement": movement,
        ]
        let json = try JSONSerialization.data(
            withJSONObject: payload.compactMapValues { $0 }, options: []
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ListingSpecs.self, from: json)
    }

    func testAnUnfilledFieldIsNotARow() throws {
        // Eytan's rule: blank hides. A spec sheet of em-dashes reads as a
        // broken page rather than as a catalog still being written.
        let rows = try specs(material: "Oystersteel").rows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.label, "Case material")
    }

    func testAMeasurementCarriesItsUnit() throws {
        let rows = try specs(diameterMm: 41, lugWidthMm: 21).rows
        XCTAssertEqual(rows.first(where: { $0.label == "Diameter" })?.value, "41mm")
        XCTAssertEqual(rows.first(where: { $0.label == "Lug width" })?.value, "21mm")
    }

    func testAThicknessKeepsItsDecimalAndDropsAPointlessOne() throws {
        XCTAssertEqual(
            try specs(thicknessMm: 12.5).rows.first?.value, "12.5mm"
        )
        // 13.0mm is a number somebody typed as 13.
        XCTAssertEqual(
            try specs(thicknessMm: 13).rows.first?.value, "13mm"
        )
    }

    func testAWatchThatHoldsNoPressureSaysSoRatherThanReadingZero() throws {
        // Zero is a real answer and "0m" reads as a missing value.
        XCTAssertEqual(
            try specs(waterResistanceM: 0).rows.first?.value, "Not water resistant"
        )
        XCTAssertEqual(
            try specs(waterResistanceM: 300).rows.first?.value, "300m"
        )
    }

    func testTheRowsComeBackInSpecSheetOrder() throws {
        let rows = try specs(
            material: "Oystersteel", dial: "Black", diameterMm: 41, movement: "Automatic"
        ).rows
        XCTAssertEqual(rows.map(\.label), ["Case material", "Diameter", "Dial", "Movement"])
    }

    func testAListingWithNoSpecsAtAllHasNoRows() throws {
        XCTAssertTrue(try specs().rows.isEmpty)
    }
}
