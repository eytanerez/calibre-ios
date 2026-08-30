import CalibreDesign
import CalibreKit
import SwiftUI

/// Reference-level market board: every reference Calibre publishes a price
/// for, filterable and sortable, with a tap-through to the reference's own
/// chart and spec sheet.
///
/// The set is whatever `/market/reference-prices` says it is. A reference
/// only publishes once there is enough of Calibre's own trade behind it, so
/// an empty board is a real answer — "nothing published yet" — and reads as
/// one rather than as a screen that failed to load.
struct MarketBoardView: View {
    /// One reference plus the series drawn from its change-points, built once
    /// per load rather than per render — resampling every card's history on
    /// every scroll tick is work nobody asked for.
    private struct BoardRow: Identifiable {
        let price: MarketReferencePrice
        let series: MarketSeries

        var id: String { price.id }
        var change: Double { series.change }
    }

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

    @Environment(AppServices.self) private var services

    @State private var rows: [BoardRow] = []
    @State private var asOf: String?
    @State private var isLoading = true
    @State private var loadFailed = false

    @State private var searchText = ""
    @State private var selectedBrand: String?
    @State private var trend: TrendFilter = .all
    @State private var sort: SortKey = .gainers
    @State private var selectedReference: MarketReferencePrice?

    private var brands: [String] {
        Array(Set(rows.map(\.price.brand))).sorted()
    }

    private var advancingCount: Int { rows.filter { $0.change >= 0 }.count }
    private var decliningCount: Int { rows.count - advancingCount }

    private var visibleRows: [BoardRow] {
        var filtered = rows
        if let selectedBrand {
            filtered = filtered.filter { $0.price.brand == selectedBrand }
        }
        switch trend {
        case .all: break
        case .advancing: filtered = filtered.filter { $0.change >= 0 }
        case .declining: filtered = filtered.filter { $0.change < 0 }
        }
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !term.isEmpty {
            filtered = filtered.filter {
                "\($0.price.brand) \($0.price.model ?? "") \($0.price.reference)".lowercased().contains(term)
            }
        }
        switch sort {
        case .gainers: filtered.sort { $0.change > $1.change }
        case .losers: filtered.sort { $0.change < $1.change }
        case .price: filtered.sort { $0.price.currentValue > $1.price.currentValue }
        case .name: filtered.sort { name(for: $0) < name(for: $1) }
        }
        return filtered
    }

    private func name(for row: BoardRow) -> String {
        "\(row.price.brand) \(row.price.model ?? row.price.reference)"
    }

    private var hasActiveFilters: Bool {
        selectedBrand != nil || trend != .all || !searchText.isEmpty
    }

    var body: some View {
        Group {
            if isLoading, rows.isEmpty {
                skeleton
            } else if rows.isEmpty, loadFailed {
                EmptyState(
                    icon: "wifi.slash",
                    title: "Couldn't load market prices",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    Task { await load() }
                }
            } else if rows.isEmpty {
                EmptyState(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No prices published yet",
                    message: "Calibre publishes a reference price once there's enough of its own trade behind it. Nothing is published today \u{2014} check back."
                )
            } else {
                board
            }
        }
        .task {
            guard rows.isEmpty else { return }
            await load()
        }
        .sheet(item: $selectedReference) { price in
            MarketDetailSheet(price: price)
        }
    }

    private func load() async {
        loadFailed = false
        do {
            let prices = try await services.community.loadReferencePrices()
            rows = prices.map { BoardRow(price: $0, series: MarketSeries(history: $0.history)) }
            asOf = services.community.referencePricesAsOf
        } catch {
            if rows.isEmpty { loadFailed = true }
        }
        isLoading = false
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            summaryTiles
            watchBoard
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.l) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .fill(Color.calibre.card)
                    .frame(height: 140)
                    .shimmer()
            }
        }
    }

    // MARK: - Summary tiles

    private var summaryTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
            statTile(label: "Advancing", value: "\(advancingCount)", tone: .up) {
                Text("since first published price")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            statTile(label: "Declining", value: "\(decliningCount)", tone: .down) {
                Text("since first published price")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            if let updated = MarketFormat.day(iso: asOf) {
                statTile(label: "Last updated", value: updated, tone: .neutral) {
                    Text("Calibre's own trade")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
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
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
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
                ForEach(visibleRows) { row in
                    TickerCard(price: row.price, series: row.series) {
                        Haptics.shared.play(.selection)
                        selectedReference = row.price
                    }
                }
            }

            if visibleRows.isEmpty {
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

            Text("Reference-level pricing from Calibre's own listings and completed sales \u{2014} not offers to buy or sell. Individual listings set their own asking prices.")
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

    /// Shared pill for the board's dropdowns: icon, current value, caret.
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

    /// The arrow and the figure sit below the body sizes so the pill reads as a
    /// ticker mark. Scaled rather than frozen: at the default size these are
    /// exactly 10 and 12 points, so nothing moves, and above it the percentage
    /// grows instead of staying a fleck of type nobody can read. The capsule's
    /// padding and the free HStack grow with the content, so it needs no
    /// layout work of its own.
    @ScaledMetric(relativeTo: .caption) private var arrowSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var valueSize: CGFloat = 12

    var body: some View {
        let positive = change >= 0
        HStack(spacing: 3) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: arrowSize, weight: .semibold))
            Text(MarketFormat.percent(change))
                .font(.system(size: valueSize, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(positive ? Color.calibre.success : Color.calibre.destructive)
        .padding(.horizontal, Space.s)
        .padding(.vertical, 3)
        .background((positive ? Color.calibre.success : Color.calibre.destructive).opacity(0.1), in: Capsule())
    }
}

private struct TickerCard: View {
    let price: MarketReferencePrice
    let series: MarketSeries
    let onSelect: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The brand eyebrow and the reference number are the smallest type on the
    /// card. Scaled rather than frozen: at the default size these are exactly
    /// 10 and 11 points, so the grid is untouched, and above it the reference
    /// grows with everything else instead of staying unreadably small.
    @ScaledMetric(relativeTo: .caption) private var brandSize: CGFloat = 10
    @ScaledMetric(relativeTo: .caption) private var referenceSize: CGFloat = 11

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(price.brand.uppercased())
                            .font(.system(size: brandSize, weight: .semibold))
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Text(price.model ?? price.reference)
                            .font(CalibreType.serif(.semiBold, 15, relativeTo: .subheadline))
                            .foregroundStyle(Color.calibre.foreground)
                            .lineLimit(1)
                        Text("Ref. \(price.reference)")
                            .font(.system(size: referenceSize))
                            .foregroundStyle(Color.calibre.mutedForeground)
                            // One line at every normal size — the second line
                            // only exists at accessibility sizes, where a
                            // reference truncated to "Ref. 126…" identifies
                            // nothing.
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    }
                    Spacer(minLength: Space.s)
                    if series.isDrawable {
                        ChangePillView(change: series.change)
                    }
                }

                if series.isDrawable {
                    MarketSparkline(series: series.values, change: series.change)
                } else {
                    // One published price has no shape to draw. The card says
                    // what it knows and leaves the chart's height alone, so a
                    // grid of cards still lines up.
                    Text("First published price")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        // 44 is the sparkline's height, so the grid still lines
                        // up — but as a floor, not a ceiling: at large text
                        // sizes the caption wraps out of a fixed 44 and gets
                        // clipped mid-sentence.
                        .frame(minHeight: 44, alignment: .leading)
                }

                Text(MarketFormat.usdFull(price.currentValue))
                    .font(CalibreType.serif(.semiBold, 17, relativeTo: .headline))
                    .foregroundStyle(Color.calibre.foreground)
                    .monospacedDigit()
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}
