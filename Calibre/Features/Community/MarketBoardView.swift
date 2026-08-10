import CalibreDesign
import SwiftUI

/// Reference-level market board: the Calibre Index, a filterable/sortable
/// grid of tickers, and a tap-through to each watch's detail chart. Mirrors
/// the web app's Market Data page — same figures, same interactions.
struct MarketBoardView: View {
    enum SortKey: String, CaseIterable, Identifiable {
        case gainers, losers, price, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .gainers: return "Top gainers"
            case .losers: return "Top losers"
            case .price: return "Price: high to low"
            case .name: return "Name: A\u{2013}Z"
            }
        }
    }

    enum TrendFilter: String, CaseIterable, Identifiable {
        case all, advancing, declining
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .advancing: return "Advancing"
            case .declining: return "Declining"
            }
        }
    }

    private static let usd: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func usdCompact(_ value: Double) -> String {
        if value >= 1000 {
            let thousands = value / 1000
            return String(format: thousands >= 100 ? "$%.0fk" : "$%.1fk", thousands)
        }
        return "$\(Int(value.rounded()))"
    }

    private static func usdFull(_ value: Double) -> String {
        usd.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private static func formatPercent(_ fraction: Double) -> String {
        let pct = abs(fraction * 100)
        let sign = fraction >= 0 ? "+" : "\u{2212}"
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    private let markets = MarketData.buildMarkets()
    private let dates = MarketData.buildHistoryDates()
    private var indexSeries: [Double] { MarketData.buildIndexSeries(markets) }

    @State private var searchText = ""
    @State private var selectedBrand: String?
    @State private var trend: TrendFilter = .all
    @State private var sort: SortKey = .gainers
    @State private var selectedMarket: MarketData.Market?

    private var brands: [String] {
        Array(Set(markets.map(\.brand))).sorted()
    }

    private var indexCurrent: Double { indexSeries.last ?? 100 }
    private var indexChange: Double {
        guard let first = indexSeries.first, first != 0 else { return 0 }
        return indexCurrent / first - 1
    }
    private var advancingCount: Int { markets.filter { $0.change >= 0 }.count }
    private var decliningCount: Int { markets.count - advancingCount }
    private var topMover: MarketData.Market? {
        markets.max { $0.change < $1.change }
    }

    private var visibleMarkets: [MarketData.Market] {
        var filtered = markets
        if let selectedBrand {
            filtered = filtered.filter { $0.brand == selectedBrand }
        }
        switch trend {
        case .all: break
        case .advancing: filtered = filtered.filter { $0.change >= 0 }
        case .declining: filtered = filtered.filter { $0.change < 0 }
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            filtered = filtered.filter { "\($0.brand) \($0.model) \($0.reference)".lowercased().contains(term) }
        }
        switch sort {
        case .gainers: filtered.sort { $0.change > $1.change }
        case .losers: filtered.sort { $0.change < $1.change }
        case .price: filtered.sort { $0.price > $1.price }
        case .name: filtered.sort { "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)" }
        }
        return filtered
    }

    private var hasActiveFilters: Bool {
        selectedBrand != nil || trend != .all || !searchText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            summaryTiles
            indexOverview
            watchBoard
        }
        .sheet(item: $selectedMarket) { market in
            MarketDetailSheet(market: market, dates: dates)
        }
    }

    // MARK: - Summary tiles

    private var summaryTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
            statTile(label: "Calibre Index", value: String(format: "%.2f", indexCurrent), tone: indexChange >= 0 ? .up : .down) {
                ChangePillView(change: indexChange)
            }
            statTile(label: "Advancing", value: "\(advancingCount)", tone: .up) {
                Text("of \(markets.count) references").font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
            }
            statTile(label: "Declining", value: "\(decliningCount)", tone: .down) {
                Text("of \(markets.count) references").font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
            }
            if let topMover {
                statTile(label: "Top mover (\(MarketData.historyDays)d)", value: Self.formatPercent(topMover.change), tone: .up) {
                    Text("\(topMover.brand) \(topMover.model)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(1)
                }
            }
        }
    }

    private enum StatTone { case neutral, up, down }

    @ViewBuilder
    private func statTile<Sub: View>(label: String, value: String, tone: StatTone, @ViewBuilder sub: () -> Sub) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label.uppercased())
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(value)
                .font(CalibreType.serif(.semiBold, 22, relativeTo: .title2))
                .foregroundStyle(tone == .up ? Color.calibre.success : (tone == .down ? Color.calibre.destructive : Color.calibre.foreground))
                .monospacedDigit()
            sub()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    // MARK: - Index overview

    private var indexOverview: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("CALIBRE INDEX")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                    Text("Market Overview")
                        .font(CalibreType.serif(.semiBold, 22, relativeTo: .title2))
                        .foregroundStyle(Color.calibre.foreground)
                    Text("Equal-weighted across all \(markets.count) references")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xs) {
                    ShareLink(
                        item: URL(string: "https://buycalibre.com/community?room=market")!,
                        message: Text(
                            "The Calibre Index is at \(String(format: "%.2f", indexCurrent)) "
                                + "(\(Self.formatPercent(indexChange))) over \(MarketData.historyDays) days."
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                    .accessibilityLabel("Share the Calibre Index")
                    Text(String(format: "%.2f", indexCurrent))
                        .font(CalibreType.serif(.semiBold, 24, relativeTo: .title2))
                        .foregroundStyle(Color.calibre.foreground)
                        .monospacedDigit()
                    ChangePillView(change: indexChange)
                }
            }

            MarketAreaChart(
                series: indexSeries,
                dates: dates,
                color: MarketTrend.color(for: indexChange),
                formatValue: { String(format: "%.1f", $0) }
            )

            HStack(spacing: 0) {
                indexMetric(label: "Period high", value: String(format: "%.2f", indexSeries.max() ?? indexCurrent))
                Divider().frame(height: 32)
                indexMetric(label: "Period low", value: String(format: "%.2f", indexSeries.min() ?? indexCurrent))
                Divider().frame(height: 32)
                indexMetric(label: "Window", value: "\(MarketData.historyDays) days")
            }
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private func indexMetric(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.calibre.mutedForeground)
            Text(value).font(CalibreType.bodyMedium).foregroundStyle(Color.calibre.foreground).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Watch board (filters + grid)

    private var watchBoard: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Watch board")
                .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                .foregroundStyle(Color.calibre.foreground)

            searchField

            // A grid, not a row of chips: the trend rail was the one
            // horizontally-scrolling thing left on this page, and at large
            // Dynamic Type its content outgrew the screen and let the whole
            // board slide sideways. Three dropdowns can't scroll at all, and
            // they wrap instead of overflowing.
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Space.m),
                    GridItem(.flexible(), spacing: Space.m),
                ],
                spacing: Space.m
            ) {
                brandMenu
                sortMenu
                trendMenu
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.l), GridItem(.flexible(), spacing: Space.l)], spacing: Space.l) {
                ForEach(visibleMarkets) { market in
                    TickerCard(market: market, formatPrice: Self.usdFull) {
                        Haptics.shared.play(.selection)
                        selectedMarket = market
                    }
                }
            }

            if visibleMarkets.isEmpty {
                VStack(spacing: Space.s) {
                    Text("No references match your filters.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                    if hasActiveFilters {
                        Button("Clear filters") {
                            selectedBrand = nil
                            trend = .all
                            searchText = ""
                        }
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xxl)
            }

            Text("Reference-level market pricing across the most-traded references. Figures reflect secondary-market estimates, not offers to buy or sell \u{2014} individual listings set their own asking prices.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .padding(.top, Space.s)
        }
    }

    private var searchField: some View {
        SearchField(text: $searchText, placeholder: "Filter references\u{2026}")
    }

    private var brandMenu: some View {
        Menu {
            Picker("Brand", selection: $selectedBrand) {
                Text("All brands").tag(String?.none)
                ForEach(brands, id: \.self) { brand in
                    Text(brand).tag(String?.some(brand))
                }
            }
        } label: {
            dropdownLabel(
                icon: "tag",
                title: selectedBrand ?? "All brands"
            )
        }
        .accessibilityLabel("Brand filter, \(selectedBrand ?? "all brands")")
    }

    private var trendMenu: some View {
        Menu {
            Picker("Trend", selection: $trend) {
                ForEach(TrendFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            dropdownLabel(icon: "chart.line.uptrend.xyaxis", title: trend.label)
        }
        .accessibilityLabel("Trend filter, \(trend.label)")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(SortKey.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
        } label: {
            dropdownLabel(icon: "arrow.up.arrow.down", title: sort.label)
        }
        .accessibilityLabel("Sort, \(sort.label)")
    }

    /// Shared pill for the board's two dropdowns: icon, current value, caret.
    private func dropdownLabel(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium))
            Text(title)
                .font(CalibreType.label)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 2)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.calibre.foreground)
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity)
        .frame(minHeight: Space.touchTarget)
        .background(Color.calibre.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.calibre.border, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Change-over-window pill: green/up or red/down, with the right arrow.
struct ChangePillView: View {
    let change: Double

    var body: some View {
        let positive = change >= 0
        HStack(spacing: 3) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
            Text(formatted)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(positive ? Color.calibre.success : Color.calibre.destructive)
        .padding(.horizontal, Space.s)
        .padding(.vertical, 3)
        .background((positive ? Color.calibre.success : Color.calibre.destructive).opacity(0.1), in: Capsule())
    }

    private var formatted: String {
        let pct = abs(change * 100)
        let sign = change >= 0 ? "+" : "\u{2212}"
        return "\(sign)\(String(format: "%.2f", pct))%"
    }
}

private struct TickerCard: View {
    let market: MarketData.Market
    let formatPrice: (Double) -> String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(market.brand.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Text(market.model)
                            .font(CalibreType.serif(.semiBold, 15, relativeTo: .subheadline))
                            .foregroundStyle(Color.calibre.foreground)
                            .lineLimit(1)
                        Text("Ref. \(market.reference)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.s)
                    ChangePillView(change: market.change)
                }

                MarketSparkline(series: market.series, change: market.change)

                Text(formatPrice(market.price))
                    .font(CalibreType.serif(.semiBold, 17, relativeTo: .headline))
                    .foregroundStyle(Color.calibre.foreground)
                    .monospacedDigit()
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}
