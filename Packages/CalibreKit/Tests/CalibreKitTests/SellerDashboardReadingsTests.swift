import Foundation
import XCTest
@testable import CalibreKit

/// The seller dashboard's figures have states a bare number gets wrong: a
/// conversion rate nobody could measure, a rate too small for the two places
/// the server rounds to, and a money gap that is not the commission it looks
/// like. The contract under test is `SellerDashboardView.get` in
/// `app/api/views/payouts.py` and `compute_order_base_payout_amount` in
/// `app/services/payouts.py`.
final class SellerDashboardReadingsTests: XCTestCase {

    /// The metrics block, stated as JSON so the test exercises the same
    /// decoding path the app does — a reading derived from a field that
    /// stopped decoding would otherwise still pass.
    private func metrics(
        ordersTotal: Int = 0,
        conversion: String = "null",
        views: Int = 0,
        gross: String = "0.00",
        net: String = "0.00"
    ) throws -> SellerDashboardMetrics {
        let json = """
        {
          "active_listings": 0,
          "pending_review_listings": 0,
          "draft_listings": 0,
          "rejected_listings": 0,
          "archived_listings": 0,
          "sold_listings": 0,
          "total_views": \(views),
          "total_watchers": 0,
          "orders_total": \(ordersTotal),
          "conversion_rate_percent": \(conversion),
          "gross_sales": "\(gross)",
          "net_sales": "\(net)",
          "pending_payout_total": "0.00",
          "pending_actions_total": 0,
          "offers_waiting": 0,
          "sold_awaiting_label": 0
        }
        """
        return try apiDecoder().decode(SellerDashboardMetrics.self, from: Data(json.utf8))
    }

    // MARK: - Conversion

    /// `null` is what the server sends when there were no views to divide by.
    /// It is not a rate of zero and must never be read as one.
    func testNullConversionIsNoViewsRatherThanZeroPercent() throws {
        let reading = try metrics(conversion: "null").conversionReading
        XCTAssertEqual(reading, .noViewsYet)
    }

    /// Views happened, no order did. This is the one genuine zero.
    func testZeroConversionWithNoOrdersReadsAsNoOrdersYet() throws {
        let reading = try metrics(ordersTotal: 0, conversion: "0.0", views: 4_212).conversionReading
        XCTAssertEqual(reading, .noOrdersYet)
    }

    /// The trap: the server rounds to two places, so a real sale against a
    /// large view count arrives as `0.0`. Printing "0%" beside sales that
    /// happened states the opposite of the truth.
    func testConversionRoundedAwayByTheServerIsNotPrintedAsZero() throws {
        let reading = try metrics(ordersTotal: 3, conversion: "0.0", views: 90_000).conversionReading
        XCTAssertEqual(reading, .belowPrecision)
    }

    func testConversionKeepsTheServersTwoPlacesAndDropsTrailingZeros() throws {
        XCTAssertEqual(try metrics(ordersTotal: 6, conversion: "0.02", views: 29_754).conversionReading, .rate("0.02"))
        XCTAssertEqual(try metrics(ordersTotal: 5, conversion: "12.50", views: 40).conversionReading, .rate("12.5"))
        XCTAssertEqual(try metrics(ordersTotal: 4, conversion: "20.0", views: 20).conversionReading, .rate("20"))
    }

    // MARK: - The money gap

    /// Both figures are `Numeric(12,2)` on the wire. The subtraction stays in
    /// `Decimal`, where 40550.00 − 34850.13 is 5699.87 exactly; the same sum
    /// in `Double` lands on 5699.869999999999 and prints a cent short.
    func testWithheldIsExactDecimalArithmeticOnTheServersFigures() throws {
        let block = try metrics(gross: "40550.00", net: "34850.13")
        XCTAssertEqual(block.withheldFromSales, Decimal(string: "5699.87"))
    }

    func testWithheldIsZeroWhenTheWholeSaleReachedTheSeller() throws {
        let block = try metrics(gross: "7150.00", net: "7150.00")
        XCTAssertEqual(block.withheldFromSales, Decimal.zero)
    }
}
