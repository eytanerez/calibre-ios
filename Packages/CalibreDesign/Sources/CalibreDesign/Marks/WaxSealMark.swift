import SwiftUI

/// Agreed and binding. The same press as the stamp, and deliberately so — the
/// two are the same gesture on different material, and a deal closing should
/// feel like the same kind of event as an authentication passing.
///
/// Wax is one of the materials the vocabulary lets a mark fill. It gets one
/// because a seal that reads as an outline reads as a coin.
///
/// This is the only mark that carries its own colour, because sealing wax has
/// one. Every other mark takes the page's ink and must go on doing so — in the
/// primary this seal is a brown disc, which is the coin the scallop was already
/// working to keep it from being. Recorded in CALIBRE_BY_HAND_CONTRACTS.md §17;
/// do not put it back.
///
/// The die is embossed rather than knocked out: a knockout would need the
/// surface colour to paint with, and the surface is whatever the seal was
/// pressed onto.
struct WaxSealMark: View {
    private var stillness = MarkStillness()

    let size: CGFloat
    let trigger: AnyHashable

    private struct Frame {
        var lift: Double = 0.9
        var throwOff: Double = 0
        var flecks: Double = 0
    }

    init(size: CGFloat, trigger: AnyHashable) {
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        Group {
            if stillness.isRequested {
                render(Frame(lift: 0, throwOff: 0, flecks: 0))
            } else {
                KeyframeAnimator(initialValue: Frame(), trigger: trigger) { frame in
                    render(frame)
                } keyframes: { _ in
                    KeyframeTrack(\.lift) {
                        LinearKeyframe(1.25, duration: MarkMotion.windUp, timingCurve: MarkMotion.settling)
                        LinearKeyframe(0, duration: MarkMotion.strike, timingCurve: MarkMotion.falling)
                    }
                    KeyframeTrack(\.throwOff) {
                        LinearKeyframe(0, duration: MarkMotion.windUp + MarkMotion.strike)
                        LinearKeyframe(1, duration: MarkMotion.debris, timingCurve: MarkMotion.settling)
                    }
                    KeyframeTrack(\.flecks) {
                        LinearKeyframe(0, duration: MarkMotion.windUp + MarkMotion.strike)
                        MoveKeyframe(0.9)
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
            flecks(frame)
            seal
                .scaleEffect(1 + frame.lift * 0.1)
                .offset(y: -frame.lift * 20)
        }
    }

    private var seal: some View {
        ZStack {
            Self.halo.stroke(Color.calibre.wax.opacity(0.3), style: MarkGrid.style)
            Self.wax.fill(Color.calibre.wax)
            Self.wax.stroke(Color.calibre.waxHighlight, style: MarkGrid.style)
            Self.impression.stroke(Self.struck, style: MarkGrid.style)
        }
    }

    /// The die stands proud of the wax and catches the light, so it is struck
    /// as a highlight of the lit edge rather than in the body colour: at the
    /// body colour the monogram is a shape you can only find by looking for it,
    /// and whose seal it is was the whole point of pressing one. White here is
    /// light rather than a palette colour — it is what a raised edge catches,
    /// in either appearance.
    private static var struck: Color {
        Color.calibre.waxHighlight.mix(with: .white, by: 0.45, in: .device)
    }

    /// The die: the Calibre mark, taken from `CalibreLogoMark` and shrunk about
    /// its own jewel until it sits inside the wax. The jewel's filled centre is
    /// left out — a die presses its raised parts in, and the centre is the part
    /// the wax fills back up.
    static var impression: Path {
        CalibreLogoMark.strokes.applying(
            CGAffineTransform(translationX: 60, y: 60)
                .scaledBy(x: 0.62, y: 0.62)
                .translatedBy(x: -60.48, y: -58.52)
        )
    }

    /// The ring of thinner wax that spreads past the seal under the press.
    private static var halo: Path {
        Path(ellipseIn: CGRect(x: 14.5, y: 14.5, width: 91, height: 91))
    }

    /// The lobed edge. Wax spreads unevenly under a seal; a true circle here
    /// is the difference between a seal and a button.
    static var wax: Path {
        var path = Path()
        let samples = 240
        for sample in 0...samples {
            let angle = Angle.degrees(Double(sample) / Double(samples) * 360)
            let radius = 40 + 1.8 * cos(12 * angle.radians)
            let point = markPoint(MarkGrid.centre, radius, angle)
            if sample == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Wax flung clear of the press, along the line it was pushed.
    private func flecks(_ frame: Frame) -> some View {
        Path { path in
            let reach = 44 + frame.throwOff * 16
            for step in 0..<6 {
                let angle = Angle.degrees(Double(step) * 60 + 24)
                path.move(to: markPoint(MarkGrid.centre, reach, angle))
                path.addLine(to: markPoint(MarkGrid.centre, reach + 7, angle))
            }
        }
        .stroke(Color.calibre.wax, style: MarkGrid.hairline)
        .opacity(frame.flecks)
    }
}

#Preview("waxSeal", traits: .sizeThatFitsLayout) {
    CalibreMark.waxSeal()
        .padding(Space.xl)
        .calibrePageBackground()
}
