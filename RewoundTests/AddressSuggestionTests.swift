import XCTest
@testable import Rewound

/// What an Apple Maps pick turns into on an address form. The network half
/// (the completer and the search) is Apple's; this is the half that decides
/// what lands in which box.
final class AddressSuggestionTests: XCTestCase {

    func testAPickFillsTheFourFields() throws {
        let address = try XCTUnwrap(SuggestedAddress(
            houseNumber: "1",
            street: "Infinite Loop",
            city: "Cupertino",
            region: "CA",
            postalCode: "95014",
            countryCode: "US",
            fallbackLine1: "1 Infinite Loop"
        ))

        XCTAssertEqual(address, SuggestedAddress(line1: "1 Infinite Loop", city: "Cupertino", state: "CA", postalCode: "95014"))
    }

    func testASpelledOutStateBecomesItsCode() throws {
        let address = try XCTUnwrap(SuggestedAddress(
            houseNumber: "350",
            street: "5th Ave",
            city: "New York",
            region: "New York",
            postalCode: "10118",
            countryCode: "us",
            fallbackLine1: "350 5th Ave"
        ))

        XCTAssertEqual(address.state, "NY")
    }

    func testWithoutAStreetTheSuggestionsOwnLineIsUsed() throws {
        let address = try XCTUnwrap(SuggestedAddress(
            houseNumber: nil,
            street: nil,
            city: "Austin",
            region: "TX",
            postalCode: "78701",
            countryCode: "US",
            fallbackLine1: "  600 Congress Ave "
        ))

        XCTAssertEqual(address.line1, "600 Congress Ave")
    }

    func testAPlaceOutsideTheUnitedStatesIsRefused() {
        XCTAssertNil(SuggestedAddress(
            houseNumber: "100",
            street: "Queen St W",
            city: "Toronto",
            region: "ON",
            postalCode: "M5H 2N2",
            countryCode: "CA",
            fallbackLine1: "100 Queen St W"
        ))
    }

    /// A territory is its own country to Maps and its own state to USPS.
    func testATerritoryIsItsOwnState() throws {
        let address = try XCTUnwrap(SuggestedAddress(
            houseNumber: "1",
            street: "Calle Fortaleza",
            city: "San Juan",
            region: nil,
            postalCode: "00901",
            countryCode: "PR",
            fallbackLine1: "1 Calle Fortaleza"
        ))

        XCTAssertEqual(address.state, "PR")
    }

    /// Half an address is worse than the one being typed: without a city or a
    /// state the pick fills nothing.
    func testAnAddressMissingItsStateFillsNothing() {
        XCTAssertNil(SuggestedAddress(
            houseNumber: "1",
            street: "Main St",
            city: "Springfield",
            region: "Somewhere",
            postalCode: nil,
            countryCode: "US",
            fallbackLine1: "1 Main St"
        ))
    }

    func testStateCodes() {
        XCTAssertEqual(USStateCode.code(for: "ca"), "CA")
        XCTAssertEqual(USStateCode.code(for: "District of Columbia"), "DC")
        XCTAssertEqual(USStateCode.code(for: "Washington D.C."), "DC")
        XCTAssertEqual(USStateCode.code(for: "West Virginia"), "WV")
        XCTAssertNil(USStateCode.code(for: "ON"))
        XCTAssertNil(USStateCode.code(for: ""))
        XCTAssertNil(USStateCode.code(for: nil))
    }

    func testForeignSuggestionsAreDropped() {
        let canada = Locale.current.localizedString(forRegionCode: "CA") ?? "Canada"
        let unitedStates = Locale.current.localizedString(forRegionCode: "US") ?? "United States"

        XCTAssertTrue(AddressSuggester.namesForeignCountry("Toronto, ON, \(canada)"))
        XCTAssertFalse(AddressSuggester.namesForeignCountry("Cupertino, CA, \(unitedStates)"))
        XCTAssertFalse(AddressSuggester.namesForeignCountry("Cupertino, CA"))
        XCTAssertFalse(AddressSuggester.namesForeignCountry(""))
    }
}
