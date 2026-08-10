import CalibreDesign
import CalibreKit
import SwiftUI

/// Full-screen(ish) detail for a single watch on the market board: the big
/// chart, trailing performance windows, a stat grid, and a way to go find
/// the real thing on the marketplace.
struct MarketDetailSheet: View {
    let market: MarketData.Market
    let dates: [Date]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    private static let usd: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static func usdFull(_ value: Double) -> String {
        usd.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private static func usdCompact(_ value: Double) -> String {
        if value >= 1000 {
            let thousands = value / 1000
            return String(format: thousands >= 100 ? "$%.0fk" : "$%.1fk", thousands)
        }
        return "$\(Int(value.rounded()))"
    }

    private var performanceWindows: [(label: String, value: Double)] {
        [
            ("7-day", MarketData.windowChange(market.series, days: 7)),
            ("30-day", MarketData.windowChange(market.series, days: 30)),
            ("\(MarketData.historyDays)-day", market.change),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    priceHeader
                    MarketAreaChart(
                        series: market.series,
                        dates: dates,
                        color: MarketTrend.color(for: market.change),
                        formatValue: Self.usdCompact
                    )
                    performanceRow
                    statGrid
                    footer
                }
                .padding(Space.l)
            }
            .background(Color.calibre.background)
            .navigationTitle(market.model)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(
                        item: URL(string: "https://buycalibre.com/community?room=market&watch=\(market.id)")
                            ?? URL(string: "https://buycalibre.com/community?room=market")!,
                        message: Text(
                            "\(market.brand) \(market.model) (Ref. \(market.reference)) on Calibre."
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Color.calibre.primary)
                    .accessibilityLabel("Share \(market.brand) \(market.model)")
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
            Text(market.brand.uppercased())
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
            Text(market.model)
                .font(CalibreType.serif(.semiBold, 26, relativeTo: .title))
                .foregroundStyle(Color.calibre.foreground)
            Text("Ref. \(market.reference)")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)

            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                Text(Self.usdFull(market.price))
                    .font(CalibreType.serif(.semiBold, 32, relativeTo: .largeTitle))
                    .foregroundStyle(Color.calibre.foreground)
                    .monospacedDigit()
                ChangePillView(change: market.change)
            }
            .padding(.top, Space.xs)
            Text("Estimated market value \u{00B7} past \(MarketData.historyDays) days")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
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
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)], spacing: Space.m) {
            statCell(label: "Current value", value: Self.usdFull(market.price))
            statCell(label: "\(MarketData.historyDays)-day high", value: Self.usdFull(market.high))
            statCell(label: "\(MarketData.historyDays)-day low", value: Self.usdFull(market.low))
            statCell(
                label: "Net change",
                value: "\(market.changeAbs >= 0 ? "+" : "\u{2212}")\(Self.usdFull(abs(market.changeAbs)))",
                tone: market.changeAbs >= 0 ? .up : .down
            )
            statCell(label: "Period range", value: Self.usdFull(market.high - market.low))
            statCell(label: "Reference", value: market.reference)
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
                let brand = market.brand
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
