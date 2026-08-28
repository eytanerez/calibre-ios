import SwiftUI

/// Stored value — a seller's balance, a payout released. A mainspring, which
/// is the part of a watch that actually stores energy, and the reason this is
/// not a second gauge: `dialArc` already owns the arc-and-needle silhouette,
/// and two of them side by side say the same thing twice.
///
/// The winding grammar is the gauge's, though — run past the figure, damp back
/// onto it — because a reserve is still a reading and a reading that arrives
/// exactly on value looks like a progress bar wearing a costume.
struct PowerReserveMark: View {
    private var stillness = MarkStillness()

    let value: Double
    let size: CGFloat
    let trigger: AnyHashable

    init(value: Double, size: CGFloat, trigger: AnyHashable) {
        self.value = min(max(value, 0), 1)
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        Group {
            if stillness.isRequested {
                render(value)
            } else {
                KeyframeAnimator(initialValue: 0.0, trigger: trigger) { reading in
                    render(reading)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(
                            MarkMotion.gaugePeak(value),
                            duration: MarkMotion.sweepUp,
                            timingCurve: MarkMotion.falling
                        )
                        LinearKeyframe(
                            max(value - 0.015, 0),
                            duration: MarkMotion.damp * 0.55,
                            timingCurve: MarkMotion.settling
                        )
                        LinearKeyframe(
                            value,
                            duration: MarkMotion.damp * 0.45,
                            timingCurve: MarkMotion.settling
                        )
                    }
                }
            }
        }
        .markCanvas(size)
        .accessibilityHidden(true)
    }

    private func render(_ reading: Double) -> some View {
        ZStack {
            Self.spring(1).stroke(Color.calibre.primary.opacity(0.22), style: MarkGrid.style)
            Self.spring(reading).stroke(Color.calibre.primary, style: MarkGrid.style)
        }
    }

    /// The spring wound to `reading` of its own length, from the core outward.
    /// Whatever is left of it stays visible underneath as the track, which is
    /// what makes the reading a proportion rather than a quantity.
    static func spring(_ reading: Double) -> Path {
        var path = Path()
        var remaining = length * min(max(reading, 0), 1)

        for (turn, radius) in coils.enumerated() {
            let half = CGFloat.pi * radius
            let drawn = min(remaining / half, 1)
            guard drawn > 0 else { break }

            path.addCircularArc(
                centre: pivots[turn % pivots.count],
                radius: radius,
                start: .degrees(turn.isMultiple(of: 2) ? 180 : 0),
                delta: .degrees(180 * drawn)
            )
            remaining -= half
        }

        return path
    }

    /// Half-turns of growing radius. The path and the length it is measured
    /// against both come off this, so a coil cannot be added to one and not the
    /// other and leave the reading quietly wrong.
    static let coils: [CGFloat] = [4, 8, 12, 16, 20, 24, 28]

    private static var length: CGFloat { coils.reduce(0) { $0 + .pi * $1 } }

    /// The centres the coil alternates between. The gap between them is the
    /// spiral's pitch — turn every coil about one centre and it is a stack of
    /// rings.
    private static let pivots = [CGPoint(x: 60, y: 60), CGPoint(x: 56, y: 60)]
}

#Preview("powerReserve", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.l) {
        CalibreMark.powerReserve(0.35, size: 96)
        CalibreMark.powerReserve(0.9, size: 96)
    }
    .padding(Space.xl)
    .calibrePageBackground()
}
