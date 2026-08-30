import XCTest
@testable import CalibreKit

/// CALIBRE_FINAL_PUSH_CONTRACTS.md §6 — money and US phone numbers format as
/// the user types. These test the two properties that are easy to get wrong
/// and impossible to see in a screenshot: that every intermediate keystroke is
/// still typable, and that every backspace still deletes something.
final class MoneyInputFormatterTests: XCTestCase {

    func testGroupsThousandsAsTheyAreTyped() {
        XCTAssertEqual(MoneyInputFormatter.format("1"), "1")
        XCTAssertEqual(MoneyInputFormatter.format("12"), "12")
        XCTAssertEqual(MoneyInputFormatter.format("124"), "124")
        XCTAssertEqual(MoneyInputFormatter.format("1240"), "1,240")
        XCTAssertEqual(MoneyInputFormatter.format("12400"), "12,400")
        XCTAssertEqual(MoneyInputFormatter.format("1240000"), "1,240,000")
    }

    /// The trailing separator has to survive, or the cents can never be
    /// reached: "12400." re-formatted to "12,400" would delete the point the
    /// instant it was typed.
    func testKeepsATrailingDecimalPointSoCentsCanBeTyped() {
        XCTAssertEqual(MoneyInputFormatter.format("12400."), "12,400.")
        XCTAssertEqual(MoneyInputFormatter.format("12400.5"), "12,400.5")
        XCTAssertEqual(MoneyInputFormatter.format("12400.50"), "12,400.50")
    }

    func testDropsWhatIsNotPartOfANumber() {
        XCTAssertEqual(MoneyInputFormatter.format("$12,400"), "12,400")
        XCTAssertEqual(MoneyInputFormatter.format("12abc400"), "12,400")
        // A second point is a typo, not a number.
        XCTAssertEqual(MoneyInputFormatter.format("12.4.5"), "12.45")
    }

    func testHoldsTheFractionToTwoDigits() {
        XCTAssertEqual(MoneyInputFormatter.format("1.999"), "1.99")
    }

    func testLeadingZeroesCollapseButZeroPointStaysTypable() {
        XCTAssertEqual(MoneyInputFormatter.format("007"), "7")
        XCTAssertEqual(MoneyInputFormatter.format("0"), "0")
        XCTAssertEqual(MoneyInputFormatter.format("0.5"), "0.5")
        XCTAssertEqual(MoneyInputFormatter.format(".5"), "0.5")
    }

    /// Every backspace must remove a digit. A formatter that re-inserts the
    /// character just deleted freezes the field.
    func testEveryBackspaceRemovesADigit() {
        var text = MoneyInputFormatter.format("1240000")
        var seen: [String] = [text]
        while !text.isEmpty {
            text = MoneyInputFormatter.format(String(text.dropLast()))
            XCTAssertFalse(seen.contains(text), "stuck at \(text)")
            seen.append(text)
        }
        XCTAssertEqual(seen.last, "")
    }

    /// The value the field submits still parses — `positiveMoney` strips the
    /// separators this formatter adds.
    func testTheFormattedValueStillParses() {
        XCTAssertEqual(InputValidation.positiveMoney(MoneyInputFormatter.format("12400")), Decimal(12_400))
        XCTAssertEqual(InputValidation.positiveMoney(MoneyInputFormatter.format("12400.50")), Decimal(string: "12400.50"))
    }
}

final class PhoneFormatterTests: XCTestCase {

    func testFormatsAUSNumberAsItIsTyped() {
        XCTAssertEqual(PhoneFormatter.format("4"), "4")
        XCTAssertEqual(PhoneFormatter.format("415"), "415")
        XCTAssertEqual(PhoneFormatter.format("4155"), "(415) 5")
        XCTAssertEqual(PhoneFormatter.format("415555"), "(415) 555")
        XCTAssertEqual(PhoneFormatter.format("4155550"), "(415) 555-0")
        XCTAssertEqual(PhoneFormatter.format("4155550134"), "(415) 555-0134")
    }

    /// Punctuation is added one digit late precisely so this holds. Closing
    /// the bracket at three digits makes "(415)" re-form from "(415", and the
    /// field stops accepting deletions.
    func testEveryBackspaceRemovesADigit() {
        var text = PhoneFormatter.format("4155550134")
        var seen: [String] = [text]
        while !text.isEmpty {
            text = PhoneFormatter.format(String(text.dropLast()))
            XCTAssertFalse(seen.contains(text), "stuck at \(text)")
            seen.append(text)
        }
        XCTAssertEqual(seen.last, "")
    }

    func testDropsTheCountryCodeOnlyWhenAFullNumberIsBehindIt() {
        XCTAssertEqual(PhoneFormatter.format("14155550134"), "(415) 555-0134")
        XCTAssertEqual(PhoneFormatter.format("+1 415 555 0134"), "(415) 555-0134")
        // "1" alone is somebody starting to type an area code.
        XCTAssertEqual(PhoneFormatter.format("1"), "1")
    }

    /// A number that cannot be American is returned untouched rather than
    /// forced into a shape — the field never silently deletes what was typed.
    func testLeavesANonUSNumberAlone() {
        XCTAssertEqual(PhoneFormatter.format("+44 20 7946 0958"), "+44 20 7946 0958")
        XCTAssertNil(PhoneFormatter.nationalDigits("+44 20 7946 0958"))
    }

    func testNationalDigitsAreWhatGetsSubmitted() {
        XCTAssertEqual(PhoneFormatter.nationalDigits("(415) 555-0134"), "4155550134")
        XCTAssertEqual(PhoneFormatter.nationalDigits("+1 (415) 555-0134"), "4155550134")
    }

    /// The formatted string is still what `isValidPhone` accepts — it counts
    /// digits and allows `+-().` and spaces, and 10 digits is inside 7...15.
    func testTheFormattedValuePassesValidation() {
        XCTAssertTrue(InputValidation.isValidPhone(PhoneFormatter.format("4155550134")))
    }

    func testDisplayLeavesAStoredForeignNumberAsItIs() {
        XCTAssertEqual(PhoneFormatter.display("4155550134"), "(415) 555-0134")
        XCTAssertEqual(PhoneFormatter.display("+44 20 7946 0958"), "+44 20 7946 0958")
        XCTAssertNil(PhoneFormatter.display(nil))
        XCTAssertNil(PhoneFormatter.display("  "))
    }
}

/// Item 1.22 — the app says how long, not that there is a window.
final class ReturnTermsCopyTests: XCTestCase {

    func testTheWindowIsTheSummary() {
        XCTAssertEqual(ListingReturnTerms(accepted: true, windowHours: 72).summary, "72-hour returns")
        XCTAssertEqual(ListingReturnTerms(accepted: true, windowHours: 24).summary, "24-hour returns")
    }

    func testNoReturnsHasNoSummary() {
        XCTAssertNil(ListingReturnTerms(accepted: false, windowHours: nil).summary)
    }

    /// Rows recorded before the all-or-nothing CHECK constraint can accept
    /// returns with no window. Say the true thing rather than invent a number.
    func testAnAcceptingListingWithNoWindowSaysSoWithoutInventingOne() {
        XCTAssertEqual(ListingReturnTerms(accepted: true, windowHours: nil).summary, "Returns accepted")
    }

    /// Item 1.21 — `any` is the absence of the filter; `all` is the server's
    /// "accepts returns, whatever the window".
    func testTheFilterSendsWhatTheServerAccepts() {
        XCTAssertNil(ReturnWindowFilter.any.wireValue)
        XCTAssertEqual(ReturnWindowFilter.all.wireValue, "all")
        XCTAssertEqual(ReturnWindowFilter.hours24.wireValue, "24")
        XCTAssertEqual(ReturnWindowFilter.hours48.wireValue, "48")
        XCTAssertEqual(ReturnWindowFilter.hours72.wireValue, "72")
    }

    func testTheQueryCarriesTheReturnWindow() {
        var query = ListingQuery(returnWindow: .hours72)
        XCTAssertTrue(query.queryItems.contains(URLQueryItem(name: "return_window_hours", value: "72")))
        query.returnWindow = .any
        XCTAssertFalse(query.queryItems.contains { $0.name == "return_window_hours" })
    }
}

/// Item 1.20 — "rolex datejust" has to find the Datejust.
final class MultiTokenSearchTests: XCTestCase {

    func testTokensAreTheDistinctWordsInOrder() {
        XCTAssertEqual(CatalogStore.searchTokens("Rolex Datejust"), ["rolex", "datejust"])
        XCTAssertEqual(CatalogStore.searchTokens("  rolex   rolex datejust "), ["rolex", "datejust"])
        XCTAssertEqual(CatalogStore.searchTokens(""), [])
    }
}

/// The saved-search payload the Saved screen re-runs (item 1.10).
final class SavedSearchFiltersTests: XCTestCase {

    /// `APIClient` decodes with `.convertFromSnakeCase`, and that strategy
    /// renames **dictionary keys** too — so the server's `price_min` arrives
    /// as `priceMin` and has to be put back, or a saved search with a price
    /// range silently re-runs without one.
    func testSnakeCaseFilterKeysSurviveTheDecoder() throws {
        let json = """
        {
          "id": "s1",
          "name": "Tudor under $4,500",
          "filters": {"brand": "Tudor", "price_max": "4500", "year": 2021, "box_papers": true},
          "last_matched_at": null,
          "created_at": "2026-08-30T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let search = try decoder.decode(SavedSearchSummary.self, from: json)

        XCTAssertEqual(search.filters["brand"], "Tudor")
        XCTAssertEqual(search.filters["price_max"], "4500")
        // Numbers and bools arrive typed and are normalised to strings.
        XCTAssertEqual(search.filters["year"], "2021")
        XCTAssertEqual(search.filters["box_papers"], "true")
    }

    func testAPayloadWithNoFiltersDecodesToAnEmptyQuery() throws {
        let json = """
        {"id": "s2", "name": "Anything", "last_matched_at": null, "created_at": null}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let search = try decoder.decode(SavedSearchSummary.self, from: json)
        XCTAssertTrue(search.filters.isEmpty)
    }
}
