import Foundation

/// How the seller dashboard's figures are allowed to be *said*.
///
/// `/account/dashboard` sends numbers; several of them have a state that a
/// number alone gets wrong, and every client has to get that state right the
/// same way. The rules live here rather than in a view so the phone, the tab
/// that reads them and the tests all share one answer.
public extension SellerDashboardMetrics {

    /// What the conversion figure actually says.
    ///
    /// `conversion_rate_percent` is `orders ÷ views × 100`, rounded to two
    /// places server-side, and `null` when there were no views to divide by.
    /// Three of the four readings below are not a percentage at all, and
    /// printing "0%" for any of them would state a measurement nobody took.
    enum ConversionReading: Equatable, Sendable {
        /// No views yet, so there is no ratio — not a ratio of zero.
        case noViewsYet
        /// Views happened and no order did. The honest zero.
        case noOrdersYet
        /// Orders happened, but the rate is smaller than the two places the
        /// server rounds to. Saying "0%" would contradict the sale.
        case belowPrecision
        /// The rate, trimmed of trailing zeros ("20", "12.5", "0.02").
        case rate(String)
    }

    var conversionReading: ConversionReading {
        guard let percent = conversionRatePercent else { return .noViewsYet }
        guard ordersTotal > 0 else { return .noOrdersYet }
        let text = Self.percentText(percent)
        guard text != "0" else { return .belowPrecision }
        return .rate(text)
    }

    /// The gap between the two money figures the server sent.
    ///
    /// Deliberately not called commission: `net_sales` is the payout, and the
    /// payout has Calibre's commission, the to-authentication label Calibre
    /// bought and any refund already taken out of it (see
    /// `compute_order_base_payout_amount`). This is all of that together, and
    /// whatever shows it has to say so.
    ///
    /// Decimal subtraction of two server figures — never float arithmetic on
    /// money, and never a percentage worked out here.
    var withheldFromSales: Decimal {
        grossSales.value - netSales.value
    }

    /// The server's two places, with trailing zeros dropped so a whole rate
    /// reads whole. Matches `feePercentText`'s treatment of a fee.
    private static func percentText(_ percent: Double) -> String {
        var text = String(format: "%.2f", percent)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
