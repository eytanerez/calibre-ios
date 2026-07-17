import CalibreDesign
import SwiftUI

/// Shared trend tint: green when a series is up over its window, the
/// destructive red when it's down. Matches the web board's color logic.
enum MarketTrend {
    static func color(for change: Double) -> Color {
        change >= 0 ? Color.calibre.success : Color.calibre.destructive
    }
}

/// Compact, axis-free trend line for ticker cards.
struct MarketSparkline: View {
    let series: [Double]
    let change: Double

    var body: some View {
        Canvas { context, size in
            guard series.count > 1 else { return }
            let minValue = series.min() ?? 0
            let maxValue = series.max() ?? 1
            let span = max(maxValue - minValue, 1)
            let stepX = size.width / CGFloat(series.count - 1)
            let inset: CGFloat = 3

            func point(_ index: Int) -> CGPoint {
                let x = CGFloat(index) * stepX
                let normalized = (series[index] - minValue) / span
                let y = size.height - inset - CGFloat(normalized) * (size.height - inset * 2)
                return CGPoint(x: x, y: y)
            }

            var line = Path()
            line.move(to: point(0))
            for index in 1..<series.count {
                line.addLine(to: point(index))
            }

            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            let tint = MarketTrend.color(for: change)
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.18), tint.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            let last = point(series.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)), with: .color(tint))
        }
        .frame(height: 44)
    }
}

/// Large interactive area + line chart with a drag crosshair and tooltip —
/// the touch equivalent of the web board's hover chart.
struct MarketAreaChart: View {
    let series: [Double]
    let dates: [Date]
    let color: Color
    let formatValue: (Double) -> String

    @State private var dragIndex: Int?

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let padL: CGFloat = 44
            let padR: CGFloat = 8
            let padT: CGFloat = 8
            let padB: CGFloat = 22
            let plotW = max(size.width - padL - padR, 1)
            let plotH = max(size.height - padT - padB, 1)

            let rawMin = series.min() ?? 0
            let rawMax = series.max() ?? 1
            let headroom = max(rawMax - rawMin, rawMax * 0.02) * 0.12
            let minValue = rawMin - headroom
            let maxValue = rawMax + headroom
            let valueSpan = max(maxValue - minValue, 1)

            let xPos: (Int) -> CGFloat = { index in
                guard series.count > 1 else { return padL }
                return padL + CGFloat(index) / CGFloat(series.count - 1) * plotW
            }
            let yPos: (Double) -> CGFloat = { value in
                padT + (1 - CGFloat((value - minValue) / valueSpan)) * plotH
            }

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    // Gridlines + y-axis labels.
                    for step in 0..<4 {
                        let value = minValue + valueSpan * Double(step) / 3
                        let y = yPos(value)
                        var grid = Path()
                        grid.move(to: CGPoint(x: padL, y: y))
                        grid.addLine(to: CGPoint(x: size.width - padR, y: y))
                        context.stroke(
                            grid,
                            with: .color(Color.calibre.border),
                            style: StrokeStyle(lineWidth: 1, dash: step == 0 ? [] : [3, 5])
                        )
                        context.draw(
                            Text(formatValue(value)).font(.system(size: 10)).foregroundColor(Color.calibre.mutedForeground),
                            at: CGPoint(x: padL - 6, y: y),
                            anchor: .trailing
                        )
                    }

                    guard series.count > 1 else { return }

                    var line = Path()
                    line.move(to: CGPoint(x: xPos(0), y: yPos(series[0])))
                    for index in 1..<series.count {
                        line.addLine(to: CGPoint(x: xPos(index), y: yPos(series[index])))
                    }
                    var area = line
                    area.addLine(to: CGPoint(x: xPos(series.count - 1), y: padT + plotH))
                    area.addLine(to: CGPoint(x: padL, y: padT + plotH))
                    area.closeSubpath()

                    context.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                            startPoint: CGPoint(x: 0, y: padT),
                            endPoint: CGPoint(x: 0, y: padT + plotH)
                        )
                    )
                    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))

                    let lastPoint = CGPoint(x: xPos(series.count - 1), y: yPos(series[series.count - 1]))
                    context.fill(Path(ellipseIn: CGRect(x: lastPoint.x - 4, y: lastPoint.y - 4, width: 8, height: 8)), with: .color(color.opacity(0.16)))
                    context.fill(Path(ellipseIn: CGRect(x: lastPoint.x - 3, y: lastPoint.y - 3, width: 6, height: 6)), with: .color(color))

                    if let dragIndex, series.indices.contains(dragIndex) {
                        var crosshair = Path()
                        crosshair.move(to: CGPoint(x: xPos(dragIndex), y: padT))
                        crosshair.addLine(to: CGPoint(x: xPos(dragIndex), y: padT + plotH))
                        context.stroke(
                            crosshair,
                            with: .color(color.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        let markerPoint = CGPoint(x: xPos(dragIndex), y: yPos(series[dragIndex]))
                        context.fill(Path(ellipseIn: CGRect(x: markerPoint.x - 5, y: markerPoint.y - 5, width: 10, height: 10)), with: .color(Color.calibre.card))
                        context.stroke(Path(ellipseIn: CGRect(x: markerPoint.x - 5, y: markerPoint.y - 5, width: 10, height: 10)), with: .color(color), lineWidth: 2.5)
                    }

                    // X-axis date labels: first, middle, last.
                    for index in [0, series.count / 2, series.count - 1] where dates.indices.contains(index) {
                        let anchor: UnitPoint = index == 0 ? .bottomLeading : (index == series.count - 1 ? .bottomTrailing : .bottom)
                        context.draw(
                            Text(Self.axisDateFormatter.string(from: dates[index])).font(.system(size: 10)).foregroundColor(Color.calibre.mutedForeground),
                            at: CGPoint(x: xPos(index), y: size.height - 4),
                            anchor: anchor
                        )
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard series.count > 1 else { return }
                            let fraction = (drag.location.x - padL) / plotW
                            let index = Int((fraction * CGFloat(series.count - 1)).rounded())
                            dragIndex = min(max(index, 0), series.count - 1)
                        }
                        .onEnded { _ in dragIndex = nil }
                )

                if let dragIndex, series.indices.contains(dragIndex), dates.indices.contains(dragIndex) {
                    tooltip(index: dragIndex, xPos: xPos(dragIndex), yPos: yPos(series[dragIndex]), size: size)
                }
            }
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private func tooltip(index: Int, xPos: CGFloat, yPos: CGFloat, size: CGSize) -> some View {
        let tooltipWidth: CGFloat = 128
        let clampedX = min(max(xPos, tooltipWidth / 2 + 4), size.width - tooltipWidth / 2 - 4)

        VStack(spacing: 2) {
            Text(formatValue(series[index]))
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
            Text(Self.tooltipDateFormatter.string(from: dates[index]))
                .font(.system(size: 10))
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(width: tooltipWidth)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        .shadow(color: Color.calibre.shadowTint.opacity(0.12), radius: 8, y: 4)
        .position(x: clampedX, y: max(yPos - 34, 24))
        .allowsHitTesting(false)
    }
}
