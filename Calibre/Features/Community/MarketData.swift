import Foundation

/// Reference-level market data for the Market board.
///
/// There is no live pricing feed wired up yet, so this fabricates a
/// realistic-looking secondary-market dataset: 20 well-known references with
/// a current price plus a deterministic 90-day daily price history. This is a
/// line-for-line Swift port of the web app's `src/lib/marketData.ts` — same
/// seeds, same hash and PRNG — so the figures match between the site and the
/// app on any given day.
enum MarketData {
    static let historyDays = 90

    struct Seed {
        let id: String
        let brand: String
        let model: String
        let reference: String
        /// Current secondary-market price in USD (the series' last point).
        let price: Double
        /// Net drift over the full window, as a fraction, e.g. 0.045 = +4.5%.
        let bias: Double
        /// Day-to-day noisiness of the series (0.006–0.02 reads well).
        let volatility: Double
    }

    // Twenty iconic references with plausible mid-2026 secondary-market
    // values. A handful are biased negative so the board has genuine
    // decliners, not just a wall of green.
    static let seeds: [Seed] = [
        Seed(id: "rolex-daytona-116500", brand: "Rolex", model: "Cosmograph Daytona", reference: "116500LN", price: 31800, bias: 0.045, volatility: 0.010),
        Seed(id: "rolex-submariner-126610", brand: "Rolex", model: "Submariner Date", reference: "126610LN", price: 14400, bias: 0.018, volatility: 0.009),
        Seed(id: "rolex-gmt-pepsi-126710", brand: "Rolex", model: "GMT-Master II \u{201C}Pepsi\u{201D}", reference: "126710BLRO", price: 19600, bias: -0.022, volatility: 0.012),
        Seed(id: "patek-nautilus-5711", brand: "Patek Philippe", model: "Nautilus", reference: "5711/1A", price: 188000, bias: 0.061, volatility: 0.013),
        Seed(id: "patek-aquanaut-5167", brand: "Patek Philippe", model: "Aquanaut", reference: "5167A", price: 54500, bias: 0.028, volatility: 0.011),
        Seed(id: "ap-royal-oak-15500", brand: "Audemars Piguet", model: "Royal Oak", reference: "15500ST", price: 44200, bias: -0.014, volatility: 0.012),
        Seed(id: "ap-royal-oak-offshore-26470", brand: "Audemars Piguet", model: "Royal Oak Offshore", reference: "26470ST", price: 37800, bias: 0.009, volatility: 0.013),
        Seed(id: "omega-speedmaster-310", brand: "Omega", model: "Speedmaster Moonwatch", reference: "310.30.42", price: 7150, bias: 0.006, volatility: 0.008),
        Seed(id: "omega-seamaster-300m", brand: "Omega", model: "Seamaster Diver 300M", reference: "210.30.42", price: 5250, bias: 0.012, volatility: 0.009),
        Seed(id: "rolex-datejust-126334", brand: "Rolex", model: "Datejust 41", reference: "126334", price: 11300, bias: 0.004, volatility: 0.007),
        Seed(id: "rolex-day-date-228238", brand: "Rolex", model: "Day-Date 40", reference: "228238", price: 41500, bias: 0.020, volatility: 0.010),
        Seed(id: "rolex-explorer-ii-226570", brand: "Rolex", model: "Explorer II", reference: "226570", price: 10900, bias: -0.031, volatility: 0.010),
        Seed(id: "tudor-black-bay-58", brand: "Tudor", model: "Black Bay Fifty-Eight", reference: "79030N", price: 3580, bias: 0.015, volatility: 0.008),
        Seed(id: "cartier-santos-lg", brand: "Cartier", model: "Santos de Cartier (Large)", reference: "WSSA0018", price: 7950, bias: 0.033, volatility: 0.010),
        Seed(id: "cartier-tank-must", brand: "Cartier", model: "Tank Must (Large)", reference: "WSTA0041", price: 3180, bias: 0.041, volatility: 0.011),
        Seed(id: "vacheron-overseas-4500v", brand: "Vacheron Constantin", model: "Overseas", reference: "4500V", price: 31900, bias: 0.024, volatility: 0.011),
        Seed(id: "lange-lange1-191", brand: "A. Lange & S\u{00F6}hne", model: "Lange 1", reference: "191.032", price: 47800, bias: 0.016, volatility: 0.010),
        Seed(id: "iwc-portugieser-371617", brand: "IWC", model: "Portugieser Chronograph", reference: "IW371617", price: 8450, bias: -0.009, volatility: 0.009),
        Seed(id: "patek-calatrava-5227", brand: "Patek Philippe", model: "Calatrava", reference: "5227", price: 42300, bias: 0.013, volatility: 0.009),
        Seed(id: "richard-mille-rm011", brand: "Richard Mille", model: "RM 011 Felipe Massa", reference: "RM 011", price: 278000, bias: -0.045, volatility: 0.016),
    ]

    struct Market: Identifiable, Hashable {
        let id: String
        let brand: String
        let model: String
        let reference: String
        let price: Double
        /// Daily closing prices, oldest first, length == historyDays.
        let series: [Double]
        /// Net change over the window, as a fraction.
        let change: Double
        /// Net change over the window, in dollars.
        let changeAbs: Double
        let high: Double
        let low: Double
    }

    /// FNV-1a — small, fast, good enough spread for seeding the PRNG.
    private static func hashSeed(_ input: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for unit in input.utf16 {
            h ^= UInt32(unit)
            h = h &* 16777619
        }
        return h
    }

    /// mulberry32 — same generator as the web port, bit-for-bit (all math on
    /// UInt32 mirrors JS's `|0`/`>>>0` 32-bit wrapping semantics).
    private static func mulberry32(seed: UInt32) -> () -> Double {
        var a = seed
        return {
            a = a &+ 0x6D2B79F5
            var t: UInt32 = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
    }

    /// Round to a sensible tick for the price magnitude (whole dollars stay
    /// noisy-but-clean).
    private static func quantize(_ value: Double) -> Double {
        if value >= 100_000 { return (value / 100).rounded() * 100 }
        if value >= 10_000 { return (value / 10).rounded() * 10 }
        if value >= 1_000 { return (value / 5).rounded() * 5 }
        return value.rounded()
    }

    private static func buildSeries(_ seed: Seed) -> [Double] {
        let rng = mulberry32(seed: hashSeed("\(seed.reference)|\(seed.model)"))
        let end = seed.price
        let start = end / (1 + seed.bias)
        var out: [Double] = []
        out.reserveCapacity(historyDays)
        var drift = 0.0

        for i in 0..<historyDays {
            let t = Double(i) / Double(historyDays - 1)
            let baseline = start + (end - start) * t
            // Mildly auto-correlated walk so adjacent days move together.
            drift = drift * 0.72 + (rng() * 2 - 1)
            // Sine envelope pins both endpoints: line starts at `start`,
            // lands exactly on `end`.
            let envelope = sin(Double.pi * t)
            let noise = baseline * seed.volatility * drift * envelope
            out.append(quantize(baseline + noise))
        }

        out[0] = quantize(start)
        out[historyDays - 1] = end
        return out
    }

    static func buildMarkets() -> [Market] {
        seeds.map { seed in
            let series = buildSeries(seed)
            let first = series[0]
            let last = series[series.count - 1]
            return Market(
                id: seed.id,
                brand: seed.brand,
                model: seed.model,
                reference: seed.reference,
                price: seed.price,
                series: series,
                change: first == 0 ? 0 : (last - first) / first,
                changeAbs: last - first,
                high: series.max() ?? last,
                low: series.min() ?? last
            )
        }
    }

    /// Equal-weighted index: each watch normalized to 100 at the start of the
    /// window, then averaged. Reads like a market index (base 100 → e.g.
    /// 103.4 = +3.4%).
    static func buildIndexSeries(_ markets: [Market]) -> [Double] {
        guard !markets.isEmpty else { return [] }
        return (0..<historyDays).map { i in
            let mean = markets.reduce(0.0) { $0 + $1.series[i] / $1.series[0] } / Double(markets.count)
            return mean * 100
        }
    }

    /// Dates for the window, oldest first, ending today.
    static func buildHistoryDates(reference: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)
        return (0..<historyDays).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }
    }

    /// Net change over the trailing `days` window of a series.
    static func windowChange(_ series: [Double], days: Int) -> Double {
        guard !series.isEmpty else { return 0 }
        let idx = max(0, series.count - 1 - days)
        let base = series[idx]
        return base == 0 ? 0 : (series[series.count - 1] - base) / base
    }
}
