import SwiftUI

/// Time remaining — an offer's expiry, a hold, a return window. It fills the
/// way a real gauge does: the needle runs up, goes a little past, and damps
/// onto the number. A needle that arrives exactly on value looks like a
/// progress bar wearing a costume.
struct DialArcMark: View {
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
            track.stroke(Color.calibre.primary.opacity(0.22), style: MarkGrid.style)
            filled(reading).stroke(Color.calibre.primary, style: MarkGrid.style)
            needle(reading).stroke(Color.calibre.primary, style: MarkGrid.style)
            // Stroked, not filled: web and Android both draw this jewel as a
            // ring, and a fill here would be a fifth mark carrying one.
            Path(ellipseIn: CGRect(x: 55, y: 73, width: 10, height: 10))
                .stroke(Color.calibre.primary, style: MarkGrid.style)
        }
    }

    private var track: Path {
        Path { $0.addCircularArc(centre: Self.pivot, radius: 44, start: Self.start, delta: Self.span) }
    }

    private func filled(_ reading: Double) -> Path {
        Path {
            $0.addCircularArc(
                centre: Self.pivot,
                radius: 44,
                start: Self.start,
                delta: .degrees(Self.span.degrees * reading)
            )
        }
    }

    /// The needle stops short of the pivot rather than running out of its
    /// centre: a round cap sitting in the eye of the jewel fills it, and this
    /// is not one of the marks a fill belongs to.
    private func needle(_ reading: Double) -> Path {
        Path { path in
            let angle = Self.start + .degrees(Self.span.degrees * reading)
            path.move(to: markPoint(Self.pivot, 6, angle))
            path.addLine(to: markPoint(Self.pivot, 33, angle))
        }
    }

    private static let pivot = CGPoint(x: 60, y: 78)
    /// Left, over the top, to the right.
    private static var start: Angle { .degrees(180) }
    private static var span: Angle { .degrees(180) }
}

#Preview("dialArc", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.l) {
        CalibreMark.dialArc(0.28, size: 96)
        CalibreMark.dialArc(0.72, size: 96)
    }
    .padding(Space.xl)
    .calibrePageBackground()
}
