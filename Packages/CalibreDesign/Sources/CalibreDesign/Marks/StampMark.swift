import SwiftUI

/// Authentication passed. It presses: a beat of wind-up, then down, hard, and
/// the ink is what reacts. The stamp itself never deforms — an object that
/// squashes on contact reads as rubber, and rubber is the cheap version of
/// this. Weight comes from the acceleration and from the mess it leaves.
///
/// What comes down is the Calibre mark, shrunk to sit inside its rim. Any
/// borrowed glyph here — a tick above all — says "generic confirmation" where
/// this has to say "this house checked it".
struct StampMark: View {
    private var stillness = MarkStillness()

    let size: CGFloat
    let trigger: AnyHashable

    /// How high the stamp rides, and how far the ink has thrown.
    private struct Frame {
        var lift: Double = 0.9
        var splat: Double = 0
        var ink: Double = 0
    }

    init(size: CGFloat, trigger: AnyHashable) {
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        Group {
            if stillness.isRequested {
                // Stamped. The end state is the whole point of the mark; only
                // the arrival is being declined.
                render(Frame(lift: 0, splat: 0, ink: 0))
            } else {
                KeyframeAnimator(initialValue: Frame(), trigger: trigger) { frame in
                    render(frame)
                } keyframes: { _ in
                    KeyframeTrack(\.lift) {
                        // Pull back, then fall — ease-out up, ease-in down.
                        LinearKeyframe(1.25, duration: MarkMotion.windUp, timingCurve: MarkMotion.settling)
                        LinearKeyframe(0, duration: MarkMotion.strike, timingCurve: MarkMotion.falling)
                    }
                    KeyframeTrack(\.splat) {
                        LinearKeyframe(0, duration: MarkMotion.windUp + MarkMotion.strike)
                        LinearKeyframe(1, duration: MarkMotion.debris, timingCurve: MarkMotion.settling)
                    }
                    KeyframeTrack(\.ink) {
                        LinearKeyframe(0, duration: MarkMotion.windUp + MarkMotion.strike)
                        MoveKeyframe(0.85)
                        LinearKeyframe(0, duration: MarkMotion.debris, timingCurve: MarkMotion.settling)
                    }
                }
            }
        }
        .markCanvas(size)
        .accessibilityHidden(true)
    }

    private func render(_ frame: Frame) -> some View {
        ZStack {
            Self.impression.stroke(Color.calibre.primary, style: MarkGrid.style)
            dust(frame)
            stamp
                .scaleEffect(1 + frame.lift * 0.1)
                .offset(y: -frame.lift * 20)
        }
    }

    private var stamp: some View {
        ZStack {
            Self.head.stroke(Color.calibre.primary, style: MarkGrid.style)
            CalibreLogoMark.jewelCentre.applying(Self.die).fill(Color.calibre.primary)
        }
    }

    /// Rim, and the mark itself cut into it.
    static var head: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 24, y: 24, width: 72, height: 72))
        path.addPath(CalibreLogoMark.strokes, transform: die)
        return path
    }

    /// The logo shrunk about its own jewel until it sits inside the rim. The
    /// paths come from `CalibreLogoMark` rather than being drawn again at this
    /// size — a second trace is a second, slightly different mark.
    ///
    /// Transforming the path leaves the stroke alone, so the weight stays the
    /// system's rather than shrinking with the drawing.
    static let die = CGAffineTransform(translationX: 60, y: 60)
        .scaledBy(x: 0.58, y: 0.58)
        .translatedBy(x: -60.48, y: -58.52)

    /// The line it comes down on. A shallow bow rather than a rule: a straight
    /// line under a stamp reads as an underline, and this is paper.
    private static var impression: Path {
        Path { path in
            path.move(to: CGPoint(x: 16, y: 106))
            path.addQuadCurve(to: CGPoint(x: 104, y: 106), control: CGPoint(x: 60, y: 96.5))
        }
    }

    /// Ink thrown clear of the impact. Debris from something that actually
    /// happened, which is what separates it from confetti — it leaves along
    /// the line the force went, and then it is gone.
    private func dust(_ frame: Frame) -> some View {
        Path { path in
            let inner = 42 + frame.splat * 12
            for step in 0..<10 {
                let angle = Angle.degrees(Double(step) * 36 + 12)
                path.move(to: markPoint(MarkGrid.centre, inner, angle))
                path.addLine(to: markPoint(MarkGrid.centre, inner + 5, angle))
            }
        }
        .stroke(Color.calibre.primary, style: MarkGrid.hairline)
        .opacity(frame.ink)
    }
}

#Preview("stamp", traits: .sizeThatFitsLayout) {
    CalibreMark.stamp()
        .padding(Space.xl)
        .calibrePageBackground()
}
