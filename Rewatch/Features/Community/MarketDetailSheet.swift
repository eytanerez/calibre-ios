import RewatchDesign
import RewatchKit
import SwiftUI

/// One reference from the board: the published price, the chart drawn from
/// its change-points, what Rewatch knows about the watch itself, and a way to
/// go find the real thing on the marketplace.
struct MarketDetailSheet: View {
    let price: MarketReferencePrice
    /// Resampled once here rather than per body pass — the sheet reads it
    /// from half a dozen places.
    private let series: MarketSeries

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.routePush) private var routePush

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
            .rewatchPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(
                        item: URL(string: "https://shoprewatch.com/community?room=market&reference=\(price.slug)")
                            ?? URL(string: "https://shoprewatch.com/community?room=market")!,
                        message: Text("\(price.brand) \(title) (Ref. \(price.reference)) on Rewatch.")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Color.rewatch.primary)
                    .accessibilityLabel("Share \(price.brand) \(title)")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(Color.rewatch.primary)
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private var priceHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(price.brand.uppercased())
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.mutedForeground)
            Text(title)
                .font(RewatchType.serif(.semiBold, 26, relativeTo: .title))
                .foregroundStyle(Color.rewatch.foreground)
            Text("Ref. \(price.reference)")
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)

            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                Text(MarketFormat.usdFull(price.currentValue))
                    .font(RewatchType.serif(.semiBold, 32, relativeTo: .largeTitle))
                    .foregroundStyle(Color.rewatch.foreground)
                    .monospacedDigit()
                if series.isDrawable {
                    ChangePillView(change: series.change)
                }
            }
            .padding(.top, Space.xs)
            Text(publishedLine)
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
        }
    }

    private var publishedLine: String {
        if let day = MarketFormat.day(iso: price.setAt) {
            return "Rewatch reference price \u{00B7} set \(day)"
        }
        return "Rewatch reference price"
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
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.rewatch.border, lineWidth: 1))
        }
    }

    private var performanceRow: some View {
        HStack(spacing: 0) {
            ForEach(performanceWindows, id: \.label) { window in
                VStack(spacing: Space.xs) {
                    Text(window.label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.rewatch.mutedForeground)
                    ChangePillView(change: window.value)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Space.m)
        .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.rewatch.border, lineWidth: 1))
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
                    .font(RewatchType.serif(.semiBold, 20, relativeTo: .title3))
                    .foregroundStyle(Color.rewatch.foreground)
                SpecList(rows)
            }
        }
    }

    private enum Tone { case neutral, up, down }

    private func statCell(label: String, value: String, tone: Tone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.rewatch.mutedForeground)
            Text(value)
                .font(RewatchType.bodyMedium)
                .foregroundStyle(tone == .up ? Color.rewatch.success : (tone == .down ? Color.rewatch.destructive : Color.rewatch.foreground))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.rewatch.border, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Reference-level pricing. Availability and asking prices vary by listing.")
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)

            Button {
                let brand = price.brand
                dismiss()
                // The board this sheet came off is worth coming back to, so
                // the brand opens on the stack the reader is standing on
                // rather than on the Home tab the brand route calls home.
                routePush(.brand(brand))
            } label: {
                HStack(spacing: Space.s) {
                    Text("Find on the marketplace")
                    Image(systemName: "arrow.right")
                }
                .font(RewatchType.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.m)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.rewatch.primary)
        }
    }
}
