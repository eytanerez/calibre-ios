import CalibreDesign
import CalibreKit
import SwiftUI

/// One reference from the board: the published price, the chart drawn from
/// its change-points, what Calibre knows about the watch itself, and a way to
/// go find the real thing on the marketplace.
struct MarketDetailSheet: View {
    let price: MarketReferencePrice
    /// Resampled once here rather than per body pass — the sheet reads it
    /// from half a dozen places.
    private let series: MarketSeries

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    init(price: MarketReferencePrice) {
        self.price = price
        self.series = MarketSeries(history: price.history)
    }

    private var title: String { price.model ?? price.reference }

    /// Only the windows the published history actually reaches back over. A
    /// 30-day figure on a reference first priced last week would be a number
    /// nobody could stand behind.
    private var performanceWindows: [(label: String, value: Double)] {
        var windows: [(label: String, value: Double)] = []
        if let month = series.change(overDays: 30) { windows.append(("30-day", month)) }
        if let quarter = series.change(overDays: 90) { windows.append(("90-day", quarter)) }
        if let year = series.change(overDays: 365) { windows.append(("1-year", year)) }
        if series.isDrawable { windows.append(("All time", series.change)) }
        return windows
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    priceHeader
                    chart
                    if !performanceWindows.isEmpty {
                        performanceRow
                    }
                    statGrid
                    specSheet
                    footer
                }
                .padding(Space.l)
            }
            .calibrePageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(
                        item: URL(string: "https://buycalibre.com/community?room=market&reference=\(price.slug)")
                            ?? URL(string: "https://buycalibre.com/community?room=market")!,
                        message: Text("\(price.brand) \(title) (Ref. \(price.reference)) on Calibre.")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Color.calibre.primary)
                    .accessibilityLabel("Share \(price.brand) \(title)")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(Color.calibre.primary)
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(price.brand.uppercased())
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(title)
                .font(CalibreType.serif(.semiBold, 26, relativeTo: .title))
                .foregroundStyle(Color.calibre.foreground)
            Text("Ref. \(price.reference)")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)

            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                Text(MarketFormat.usdFull(price.currentValue))
                    .font(CalibreType.serif(.semiBold, 32, relativeTo: .largeTitle))
                    .foregroundStyle(Color.calibre.foreground)
                    .monospacedDigit()
                if series.isDrawable {
                    ChangePillView(change: series.change)
                }
            }
            .padding(.top, Space.xs)
            Text(publishedLine)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    private var publishedLine: String {
        if let day = MarketFormat.day(iso: price.setAt) {
            return "Calibre reference price \u{00B7} set \(day)"
        }
        return "Calibre reference price"
    }

    @ViewBuilder
    private var chart: some View {
        if series.isDrawable {
            MarketAreaChart(
                series: series.values,
                dates: series.dates,
                color: MarketTrend.color(for: series.change),
                formatValue: MarketFormat.usdCompact
            )
        } else {
            Text("This is the first price we've published for this reference, so there's no history to chart yet.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
        }
    }

    private var performanceRow: some View {
        HStack(spacing: 0) {
            ForEach(performanceWindows, id: \.label) { window in
                VStack(spacing: Space.xs) {
                    Text(window.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                    ChangePillView(change: window.value)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
            statCell(label: "Current price", value: MarketFormat.usdFull(price.currentValue))
            statCell(label: "Reference", value: price.reference)
            if series.isDrawable {
                statCell(label: "Published high", value: MarketFormat.usdFull(series.high))
                statCell(label: "Published low", value: MarketFormat.usdFull(series.low))
                statCell(
                    label: "Net change",
                    value: "\(series.changeAbs >= 0 ? "+" : "\u{2212}")\(MarketFormat.usdFull(abs(series.changeAbs)))",
                    tone: series.changeAbs >= 0 ? .up : .down
                )
                if let first = series.firstDate {
                    statCell(label: "First published", value: MarketFormat.day(first))
                }
            }
        }
    }

    @ViewBuilder
    private var specSheet: some View {
        let rows = price.specs.rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("The watch")
                    .font(CalibreType.serif(.semiBold, 20, relativeTo: .title3))
                    .foregroundStyle(Color.calibre.foreground)
                SpecList(rows)
            }
        }
    }

    private enum Tone { case neutral, up, down }

    private func statCell(label: String, value: String, tone: Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(value)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(tone == .up ? Color.calibre.success : (tone == .down ? Color.calibre.destructive : Color.calibre.foreground))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Reference-level pricing. Availability and asking prices vary by listing.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)

            Button {
                let brand = price.brand
                dismiss()
                router.open(.brand(brand))
            } label: {
                HStack(spacing: Space.s) {
                    Text("Find on the marketplace")
                    Image(systemName: "arrow.right")
                }
                .font(CalibreType.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.m)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.calibre.primary)
        }
    }
}
