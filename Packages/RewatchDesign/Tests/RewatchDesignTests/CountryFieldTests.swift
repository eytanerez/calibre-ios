import XCTest

@testable import RewatchDesign

/// The `.country` field asks AutoFill for a country NAME (iOS has no content
/// type for a code), and every form behind it accepts only a two-letter code.
/// The field converts a filled-in name to its code on the way in.
final class CountryFieldTests: XCTestCase {
    func testAFilledInNameBecomesItsCode() {
        XCTAssertEqual(RewatchFieldKind.countryCode(forName: "United States"), "US")
        XCTAssertEqual(RewatchFieldKind.countryCode(forName: "  canada "), "CA")
        XCTAssertEqual(RewatchFieldKind.countryCode(forName: "UNITED KINGDOM"), "GB")
    }

    func testTheUsualWaysOfWritingTheUS() {
        XCTAssertEqual(RewatchFieldKind.countryCode(forName: "USA"), "US")
        XCTAssertEqual(RewatchFieldKind.countryCode(forName: "U.S.A."), "US")
        XCTAssertEqual(RewatchFieldKind.countryCode(forName: "United States of America"), "US")
    }

    /// A code is already what the forms want, and anything that is not a
    /// country's name is left for the form's own validation to answer.
    func testCodesAndNonsenseAreLeftAlone() {
        XCTAssertNil(RewatchFieldKind.countryCode(forName: "US"))
        XCTAssertNil(RewatchFieldKind.countryCode(forName: "ca"))
        XCTAssertNil(RewatchFieldKind.countryCode(forName: "Narnia"))
        XCTAssertNil(RewatchFieldKind.countryCode(forName: ""))
    }
}
