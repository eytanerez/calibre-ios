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
                        .accessibilityLabel("Minimum price")
                        .accessibilityValue(priceText(lowerValue))
                        .accessibilityAdjustableAction { direction in
                            adjust(&lowerValue, direction, upperBound: upperValue)
                        }
                        .zIndex(lowerTakesTouch(lowerX: lowerX, upperX: upperX) ? 1 : 0)

                    thumb(active: upperActive)
                        .position(x: upperX, y: thumbSize / 2)
                        .gesture(upperDrag(width: width))
                        .accessibilityLabel("Maximum price")
                        .accessibilityValue(priceText(upperValue))
                        .accessibilityAdjustableAction { direction in
                            adjust(&upperValue, direction, lowerBound: lowerValue)
                        }
                        .zIndex(lowerTakesTouch(lowerX: lowerX, upperX: upperX) ? 0 : 1)
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
        // `children: .contain` rather than `.ignore`: the two thumbs below are
        // the only way to change a price without a continuous drag, so they have
        // to stay reachable. `.ignore` flattened them into one read-only summary
        // and left VoiceOver, Switch Control and Voice Control with a value they
        // could hear and no gesture that could move it.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Price range")
    }

    /// Which thumb answers a touch when the two are stacked on each other.
    ///
    /// The thumbs are drawn 28pt and grabbed at 44pt (`a11yExpandTarget`), so
    /// their hit regions overlap long before their circles do, and the later
    /// sibling — the maximum — silently wins every touch in the overlap. Drag
    /// the minimum up until `lowerDrag`'s `min(_, upperValue)` clamp parks it
    /// against the maximum, and the minimum is now under a thumb that cannot
    /// help it: dragging left is clamped at `lowerValue`, dragging right only
    /// widens while the maximum is still below the bound.
    ///
    /// Measured on the shipped build against the live $0–$128,100 filter:
    /// dragging the minimum to the right edge left "$128,000 – $128,100+",
    /// and one drag to the left took the *maximum* down to $128,000 instead
    /// of the minimum. From "$128,000 – $128,000" no drag separated them
    /// again — "Clear all" was the only way out. The sheet's own tutorial
    /// promises "a low end and a high end move independently", which is
    /// precisely what was not happening.
    ///
    /// The test has to be about pixels, not values: at that price step the
    /// two values differ by $100 and their centres by about a third of a
    /// point, so a rule keyed on `lower >= upper` never fires on the state
    /// that actually traps people.
    ///
    /// When the regions do overlap, the thumb with more room to travel takes
    /// the top of the stack. That thumb can always be moved, and moving it
    /// uncovers the other one, so whichever end the reader grabbed, the range
    /// opens again. Thumbs that are apart on screen are untouched: the
    /// maximum stays on top exactly as it shipped.
    private func lowerTakesTouch(lowerX: CGFloat, upperX: CGFloat) -> Bool {
        PriceRangeSlider.lowerThumbTakesTouch(
            lowerX: lowerX,
            upperX: upperX,
            grabRadius: Space.touchTarget / 2,
            lower: lowerValue,
            upper: upperValue,
            in: bounds
        )
    }

    /// The rule above, as a value function so it can be tested without a view
    /// hierarchy or a hit test.
    static func lowerThumbTakesTouch(
        lowerX: CGFloat,
        upperX: CGFloat,
        grabRadius: CGFloat,
        lower: Double,
        upper: Double,
        in bounds: ClosedRange<Double>
    ) -> Bool {
        // Far enough apart that the maximum's grab region does not reach the
        // minimum's centre: nothing is covered, and the shipped order stands.
        guard upperX - lowerX < grabRadius else { return false }
        let roomBelow = lower - bounds.lowerBound
        let roomAbove = bounds.upperBound - upper
        return roomBelow > roomAbove
    }

    private func thumb(active: Bool) -> some View {
        Circle()
            .fill(Color.calibre.card)
            .strokeBorder(Color.calibre.borderBright, lineWidth: 1)
            .frame(width: thumbSize, height: thumbSize)
            .calibreShadow(.resting)
            .scaleEffect(active ? Motion.pressScale : 1)
            .animation(Motion.easeFast, value: active)
            // 28pt drawn, 44pt grabbable. `.position` places by centre and the
            // negative padding hands the size back, so the thumb does not move.
            .a11yExpandTarget(currentSize: thumbSize)
    }

    /// One increment of VoiceOver's swipe-up/swipe-down on a thumb. Steps by
    /// `step` where that is a sensible fraction of the range, otherwise by a
    /// twentieth of it, so a $0–$50,000 filter is twenty gestures end to end
    /// rather than five hundred.
    private func adjust(
        _ value: inout Double,
        _ direction: AccessibilityAdjustmentDirection,
        lowerBound: Double? = nil,
        upperBound: Double? = nil
    ) {
        let increment = max(step, (span / 20).rounded())
        let moved = direction == .increment ? value + increment : value - increment
        let floor = max(lowerBound ?? bounds.lowerBound, bounds.lowerBound)
        let ceiling = min(upperBound ?? bounds.upperBound, bounds.upperBound)
        value = min(max(moved, floor), ceiling)
        Haptics.shared.play(.selection)
    }

    private func priceText(_ value: Double) -> String {
        let text = "$" + Int(value).formatted(.number.grouping(.automatic))
        return value >= bounds.upperBound ? text + " or more" : text
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
