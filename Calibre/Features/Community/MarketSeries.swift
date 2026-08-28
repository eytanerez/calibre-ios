import CalibreKit
import Foundation

/// A reference's published price history, prepared for drawing.
///
/// The server sends change-points: a price, the day it moved, and nothing in
/// between — because nothing happened in between. Plotting those points at
/// equal spacing would put a month and a day the same distance apart, so the
/// step is sampled onto an evenly spaced grid instead, carrying each price
/// forward until the day it changed. That is what a change-point series
/// means; it invents nothing.
struct MarketSeries {
    /// Sampled values, oldest first. Empty when the history had nothing
    /// readable in it.
    let values: [Double]
    /// One date per value, same order.
    let dates: [Date]
    /// The change-points themselves, cleaned and ordered — the days this
    /// price actually moved.
    let points: [(date: Date, value: Double)]

    var current: Double { values.last ?? 0 }
    var first: Double { values.first ?? 0 }
    var high: Double { values.max() ?? current }
    var low: Double { values.min() ?? current }

    /// Net change across the whole published history, as a fraction. A price
    /// that has never moved is a flat zero, not a missing value.
    var change: Double {
        guard let first = values.first, first != 0, let last = values.last else { return 0 }
        return (last - first) / first
    }

    var changeAbs: Double { current - first }

    /// A line needs two points and two different days; one published price is
    /// a fact with no shape, and the screens say so in words instead.
    var isDrawable: Bool { values.count > 1 }

    var firstDate: Date? { points.first?.date }
    var lastDate: Date? { points.last?.date }

    /// Change over the trailing `days`, or nil when the history doesn't reach
    /// back that far — a window we can't measure is left out rather than
    /// quietly measured from the earliest price we happen to have.
    func change(overDays days: Int) -> Double? {
        guard let last = points.last, let first = points.first else { return nil }
        guard let cutoff = Calendar.marketCalendar.date(byAdding: .day, value: -days, to: last.date),
              first.date <= cutoff else { return nil }
        let base = value(on: cutoff)
        guard base != 0 else { return nil }
        return (last.value - base) / base
    }

    /// The price in force on a given day: the most recent change at or before
    /// it.
    private func value(on date: Date) -> Double {
        var carried = points.first?.value ?? 0
        for point in points where point.date <= date {
            carried = point.value
        }
        return carried
    }

    init(history: [MarketReferencePrice.HistoryPoint]) {
        // Several changes can land on one day; the last one is the price that
        // day ended on.
        var byDay: [Date: Double] = [:]
        var order: [Date] = []
        for point in history {
            guard let day = MarketSeries.day(from: point.date) else { continue }
            let value = NSDecimalNumber(decimal: point.price.value).doubleValue
            if byDay[day] == nil { order.append(day) }
            byDay[day] = value
        }
        let cleaned = order.sorted().map { (date: $0, value: byDay[$0] ?? 0) }
        points = cleaned

        guard let start = cleaned.first, let end = cleaned.last, cleaned.count > 1 else {
            values = cleaned.map(\.value)
            dates = cleaned.map(\.date)
            return
        }

        let calendar = Calendar.marketCalendar
        let span = calendar.dateComponents([.day], from: start.date, to: end.date).day ?? 0
        guard span > 0 else {
            values = [end.value]
            dates = [end.date]
            return
        }

        // Enough samples for a smooth step, few enough to stay cheap on a
        // history that spans years.
        let sampleCount = min(span + 1, 120)
        var sampledValues: [Double] = []
        var sampledDates: [Date] = []
        sampledValues.reserveCapacity(sampleCount)
        sampledDates.reserveCapacity(sampleCount)

        var carried = start.value
        var next = 0
        for index in 0..<sampleCount {
            let offset = Int((Double(span) * Double(index) / Double(sampleCount - 1)).rounded())
            guard let day = calendar.date(byAdding: .day, value: offset, to: start.date) else { continue }
            while next < cleaned.count, cleaned[next].date <= day {
                carried = cleaned[next].value
                next += 1
            }
            sampledValues.append(carried)
            sampledDates.append(day)
        }
        // The last sample is the current price by definition, whatever
        // rounding did to the grid.
        if !sampledValues.isEmpty {
            sampledValues[sampledValues.count - 1] = end.value
            sampledDates[sampledDates.count - 1] = end.date
        }
        values = sampledValues
        dates = sampledDates
    }

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func day(from raw: String) -> Date? {
        dayParser.date(from: String(raw.prefix(10)))
    }
}

extension Calendar {
    /// UTC calendar: the server's history dates are calendar days, and a
    /// device in a negative offset must not shift them a day earlier.
    static let marketCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()
}

/// Shared money and percentage formatting for the market screens, so the
/// board, the reference sheet and a vault watch all quote a price the same
/// way.
enum MarketFormat {
    private static let usd: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func usdFull(_ value: Double) -> String {
        usd.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    /// Axis labels, where the digits have to fit.
    static func usdCompact(_ value: Double) -> String {
        if value >= 1000 {
            let thousands = value / 1000
            return String(format: thousands >= 100 ? "$%.0fk" : "$%.1fk", thousands)
        }
        return "$\(Int(value.rounded()))"
    }

    static func percent(_ fraction: Double) -> String {
        let sign = fraction >= 0 ? "+" : "\u{2212}"
        return "\(sign)\(String(format: "%.2f", abs(fraction * 100)))%"
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// An ISO timestamp from the API, as a plain day. Nil rather than a
    /// guess when it doesn't parse.
    static func day(iso: String?) -> String? {
        guard let iso else { return nil }
        if let day = MarketSeries.day(from: iso) { return dayFormatter.string(from: day) }
        return nil
    }
}

extension MarketReferencePrice {
    /// The published price itself, as a Double for the chart's arithmetic.
    /// Every screen quotes this rather than the last point of the series: the
    /// history is a shape, and a payload that arrived without one must never
    /// read as $0.
    var currentValue: Double { NSDecimalNumber(decimal: price.value).doubleValue }
}
