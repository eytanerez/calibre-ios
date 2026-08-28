import SwiftUI

/// Inspection. It swoops in, settles over the jewel, the jewel comes up under
/// the glass — and it stays there. The resting pose is the whole mark: a glass
/// resting on a magnified detail reads as *examined*.
///
/// The glass used to move on and leave the finding behind. Rendered beside the
/// rest of the set, what it left was a dot in a ring — the same silhouette as
/// the jewel that already sits inside several of the others. And it is the only
/// frame anyone with reduced motion ever sees, because that is the end state,
/// so the mark spent its whole life as a bullet point.
///
/// A lens and a handle, and not the concentric rings it started as: at the size
/// these render, rings on rings were indistinguishable from the stamp.
struct LoupeMark: View {
    private var stillness = MarkStillness()

    let size: CGFloat
    let trigger: AnyHashable

    private struct Frame {
        /// 0 is off over the shoulder; 1 is settled over the jewel.
        var travel: Double = 0
        /// How far the jewel has come up under the glass.
        var magnified: Double = 0
    }

    init(size: CGFloat, trigger: AnyHashable) {
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        Group {
            if stillness.isRequested {
                render(Self.rested)
            } else {
                KeyframeAnimator(initialValue: Frame(), trigger: trigger) { frame in
                    render(frame)
                } keyframes: { _ in
                    KeyframeTrack(\.travel) {
                        // Past the mark, then back onto it.
                        LinearKeyframe(
                            Self.rested.travel + 0.06,
                            duration: MarkMotion.swoop,
                            timingCurve: MarkMotion.falling
                        )
                        LinearKeyframe(
                            Self.rested.travel,
                            duration: MarkMotion.settle,
                            timingCurve: MarkMotion.settling
                        )
                    }
                    KeyframeTrack(\.magnified) {
                        LinearKeyframe(0, duration: MarkMotion.swoop + MarkMotion.settle)
                        LinearKeyframe(
                            Self.rested.magnified,
                            duration: MarkMotion.reveal,
                            timingCurve: MarkMotion.settling
                        )
                    }
                }
            }
        }
        .markCanvas(size)
        .accessibilityHidden(true)
    }

    private func render(_ frame: Frame) -> some View {
        ZStack {
            jewel
                .scaleEffect(1 + (Self.magnification - 1) * frame.magnified)
            loupe
                .offset(
                    x: Self.entry * (1 - frame.travel),
                    y: -Self.entry * (1 - frame.travel)
                )
        }
    }

    private var loupe: some View {
        Self.glass.stroke(Color.calibre.primary, style: MarkGrid.style)
    }

    /// Lens and handle. The handle is the whole reason this is not another set
    /// of concentric rings: rings on rings are the stamp, and a jewel already
    /// sits inside several of the other marks.
    static var glass: Path {
        Path { path in
            path.addEllipse(in: CGRect(
                x: 60 - lens, y: 60 - lens, width: lens * 2, height: lens * 2
            ))
            path.move(to: markPoint(MarkGrid.centre, lens, .degrees(45)))
            path.addLine(to: markPoint(MarkGrid.centre, 56, .degrees(45)))
        }
    }

    static let lens: CGFloat = 30

    /// The logo's own jewel, sitting under the glass. What the loupe is for,
    /// and what it leaves behind — drawn at the size the logo draws it and
    /// grown into the lens, because magnified means larger than it was.
    private var jewel: some View {
        ZStack {
            Self.centred(10.71).stroke(Color.calibre.primary, style: MarkGrid.style)
            Self.centred(4.88).fill(Color.calibre.primary)
        }
    }

    /// `r 10.71` around `r 4.88` is the logo's jewel out of §3, on the grid's
    /// own centre rather than the logo's slightly-off-centre one.
    static func centred(_ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: MarkGrid.centre.x - radius, y: MarkGrid.centre.y - radius,
            width: radius * 2, height: radius * 2
        ))
    }

    /// What the glass is worth: the jewel is left at the size it was read at.
    static let magnification: CGFloat = 1.87
    /// Where the sweep comes to rest, and — being the same value rather than a
    /// matching one — exactly what reduced motion renders. The two cannot drift
    /// apart, because there is only one of them.
    private static let rested = Frame(travel: 1, magnified: 1)

    /// Where it comes in from — over the shoulder, on the diagonal the handle
    /// already lies along, so the run in reads as a reach rather than a slide.
    private static let entry: CGFloat = 34
}

#Preview("loupe", traits: .sizeThatFitsLayout) {
    CalibreMark.loupe()
        .padding(Space.xl)
        .calibrePageBackground()
}
