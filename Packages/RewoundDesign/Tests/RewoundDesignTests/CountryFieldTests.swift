import XCTest

@testable import RewoundDesign

/// The `.country` field asks AutoFill for a country NAME (iOS has no content
/// type for a code), and every form behind it accepts only a two-letter code.
/// The field converts a filled-in name to its code on the way in.
final class CountryFieldTests: XCTestCase {
    func testAFilledInNameBecomesItsCode() {
        XCTAssertEqual(RewoundFieldKind.countryCode(forName: "United States"), "US")
        XCTAssertEqual(RewoundFieldKind.countryCode(forName: "  canada "), "CA")
        XCTAssertEqual(RewoundFieldKind.countryCode(forName: "UNITED KINGDOM"), "GB")
    }

    func testTheUsualWaysOfWritingTheUS() {
        XCTAssertEqual(RewoundFieldKind.countryCode(forName: "USA"), "US")
        XCTAssertEqual(RewoundFieldKind.countryCode(forName: "U.S.A."), "US")
        XCTAssertEqual(RewoundFieldKind.countryCode(forName: "United States of America"), "US")
    }

    /// A code is already what the forms want, and anything that is not a
    /// country's name is left for the form's own validation to answer.
    func testCodesAndNonsenseAreLeftAlone() {
        XCTAssertNil(RewoundFieldKind.countryCode(forName: "US"))
        XCTAssertNil(RewoundFieldKind.countryCode(forName: "ca"))
        XCTAssertNil(RewoundFieldKind.countryCode(forName: "Narnia"))
        XCTAssertNil(RewoundFieldKind.countryCode(forName: ""))
    }
}
