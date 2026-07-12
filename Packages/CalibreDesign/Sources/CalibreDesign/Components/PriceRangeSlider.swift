import SwiftUI

/// Dual-thumb price filter. Warm hairline track, chocolate active segment,
/// 28pt card-filled thumbs with a resting shadow. The serif readout above
/// formats as "$5,200 – $38,000+" by default ("+" when the upper thumb sits
/// at the range ceiling); pass `format` to override.
public struct PriceRangeSlider: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let format: ((Double, Double) -> String)?

    @GestureState private var lowerActive = false
    @GestureState private var upperActive = false

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 4

    public init(
        lowerValue: Binding<Double>,
        upperValue: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double = 1,
        format: ((Double, Double) -> String)? = nil
    ) {
        self._lowerValue = lowerValue
        self._upperValue = upperValue
        self.bounds = bounds
        self.step = step
        self.format = format
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(rangeText)
                .font(CalibreType.priceSmall)
                .foregroundStyle(Color.calibre.foreground)
                .monospacedDigit()

            GeometryReader { geometry in
                let width = geometry.size.width
                let lowerX = x(for: lowerValue, width: width)
                let upperX = x(for: upperValue, width: width)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.calibre.border)
                        .frame(height: trackHeight)
                        .padding(.horizontal, thumbSize / 2 - 2)

                    Capsule()
                        .fill(Color.calibre.primary)
                        .frame(width: max(0, upperX - lowerX), height: trackHeight)
                        .offset(x: lowerX)

                    thumb(active: lowerActive)
                        .position(x: lowerX, y: thumbSize / 2)
                        .gesture(lowerDrag(width: width))

                    thumb(active: upperActive)
                        .position(x: upperX, y: thumbSize / 2)
                        .gesture(upperDrag(width: width))
                }
            }
            .frame(height: thumbSize)
            .onChange(of: lowerActive) { _, grabbed in
                if grabbed { Haptics.shared.play(.selection) }
            }
            .onChange(of: upperActive) { _, grabbed in
                if grabbed { Haptics.shared.play(.selection) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Price range")
        .accessibilityValue(rangeText)
    }

    private func thumb(active: Bool) -> some View {
        Circle()
            .fill(Color.calibre.card)
            .strokeBorder(Color.calibre.borderBright, lineWidth: 1)
            .frame(width: thumbSize, height: thumbSize)
            .calibreShadow(.resting)
            .scaleEffect(active ? Motion.pressScale : 1)
            .animation(Motion.easeFast, value: active)
    }

    private func lowerDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($lowerActive) { _, state, _ in state = true }
            .onChanged { gesture in
                lowerValue = min(value(atX: gesture.location.x, width: width), upperValue)
            }
    }

    private func upperDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($upperActive) { _, state, _ in state = true }
            .onChanged { gesture in
                upperValue = max(value(atX: gesture.location.x, width: width), lowerValue)
            }
    }

    private var span: Double {
        bounds.upperBound - bounds.lowerBound
    }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        let usable = max(width - thumbSize, 1)
        let t = span > 0 ? (value - bounds.lowerBound) / span : 0
        return thumbSize / 2 + usable * CGFloat(t)
    }

    private func value(atX x: CGFloat, width: CGFloat) -> Double {
        let usable = max(width - thumbSize, 1)
        let t = min(max((x - thumbSize / 2) / usable, 0), 1)
        let raw = bounds.lowerBound + Double(t) * span
        let stepped = step > 0 ? (raw / step).rounded() * step : raw
        return min(max(stepped, bounds.lowerBound), bounds.upperBound)
    }

    private var rangeText: String {
        if let format { return format(lowerValue, upperValue) }
        let lower = "$" + Int(lowerValue).formatted(.number.grouping(.automatic))
        var upper = "$" + Int(upperValue).formatted(.number.grouping(.automatic))
        if upperValue >= bounds.upperBound { upper += "+" }
        return "\(lower) – \(upper)"
    }
}

private struct PriceRangeSliderPreviewHost: View {
    @State private var lower: Double = 5_200
    @State private var upper: Double = 38_000

    var body: some View {
        PriceRangeSlider(lowerValue: $lower, upperValue: $upper, in: 0...50_000, step: 100)
            .padding()
            .background(Color.calibre.background)
    }
}

#Preview("Price range — light", traits: .sizeThatFitsLayout) {
    PriceRangeSliderPreviewHost()
}

#Preview("Price range — dark", traits: .sizeThatFitsLayout) {
    PriceRangeSliderPreviewHost()
        .preferredColorScheme(.dark)
}
