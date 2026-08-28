import SwiftUI

/// In transit. Three walls and two flaps: the flaps fold in sequence — never
/// together, together reads as a lid — until they meet at the seam and complete
/// the carton. Then it gathers itself and travels.
///
/// It travels rather than leaving: a mark may not come to rest on an empty
/// frame, and a parcel that has gone is an empty frame. What it comes to rest
/// as is the thing it is saying — packed, sealed, square.
///
/// Kraft is one of the materials the vocabulary lets a mark fill.
struct BoxMark: View {
    private var stillness = MarkStillness()

    let size: CGFloat
    let trigger: AnyHashable

    private struct Frame {
        var nearFlap: Double = 0
        var farFlap: Double = 0
        /// The pull-back before it goes, and the run itself.
        var carry: Double = 0
    }

    init(size: CGFloat, trigger: AnyHashable) {
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        Group {
            if stillness.isRequested {
                render(Frame(nearFlap: 1, farFlap: 1, carry: 0))
            } else {
                KeyframeAnimator(initialValue: Frame(), trigger: trigger) { frame in
                    render(frame)
                } keyframes: { _ in
                    KeyframeTrack(\.nearFlap) {
                        LinearKeyframe(1, duration: MarkMotion.fold, timingCurve: MarkMotion.falling)
                    }
                    KeyframeTrack(\.farFlap) {
                        LinearKeyframe(0, duration: MarkMotion.foldStagger)
                        LinearKeyframe(1, duration: MarkMotion.fold, timingCurve: MarkMotion.falling)
                    }
                    KeyframeTrack(\.carry) {
                        LinearKeyframe(0, duration: MarkMotion.foldStagger + MarkMotion.fold)
                        // Dip back, run, and set down.
                        LinearKeyframe(-1, duration: MarkMotion.dip, timingCurve: MarkMotion.settling)
                        LinearKeyframe(5.4, duration: MarkMotion.whip * 0.6, timingCurve: MarkMotion.falling)
                        LinearKeyframe(0, duration: MarkMotion.whip * 0.4, timingCurve: MarkMotion.settling)
                    }
                }
            }
        }
        .markCanvas(size)
        .accessibilityHidden(true)
    }

    private func render(_ frame: Frame) -> some View {
        ZStack {
            Self.kraft.fill(Color.calibre.primary.opacity(0.1))
            Self.carton.stroke(Color.calibre.primary, style: MarkGrid.style)
            flaps(frame).stroke(Color.calibre.primary, style: MarkGrid.style)
            Self.tape
                .stroke(Color.calibre.primary, style: MarkGrid.style)
                .opacity(min(frame.nearFlap, frame.farFlap))
        }
        .offset(x: 10 * frame.carry)
    }

    /// Each flap swings on its own top corner, from standing open past the
    /// vertical to lying closed with its tip at the seam — where the two of
    /// them become the carton's top edge.
    private func flaps(_ frame: Frame) -> Path {
        Path { path in
            path.move(to: Self.nearHinge)
            path.addLine(to: markPoint(
                Self.nearHinge, Self.flapLength, .degrees(-Self.flapOpen * (1 - frame.nearFlap))
            ))

            path.move(to: Self.farHinge)
            path.addLine(to: markPoint(
                Self.farHinge, Self.flapLength, .degrees(-180 + Self.flapOpen * (1 - frame.farFlap))
            ))
        }
    }

    /// Three walls, open at the top, and set down on rounded corners rather
    /// than on points — a carton is board, and board does not come to a knife
    /// edge. The flaps are the fourth side, so the stroke stops at the hinges.
    static var carton: Path {
        Path { path in
            path.move(to: nearHinge)
            path.addLine(to: CGPoint(x: left, y: floorLine - corner))
            path.addQuadCurve(
                to: CGPoint(x: left + corner, y: floorLine),
                control: CGPoint(x: left, y: floorLine)
            )
            path.addLine(to: CGPoint(x: right - corner, y: floorLine))
            path.addQuadCurve(
                to: CGPoint(x: right, y: floorLine - corner),
                control: CGPoint(x: right, y: floorLine)
            )
            path.addLine(to: farHinge)
        }
    }

    /// The kraft closes across the opening even while the flaps are still up:
    /// what is being drawn is a full box seen from the side, not a container of
    /// air.
    private static var kraft: Path {
        Path(
            roundedRect: CGRect(x: left, y: lid, width: right - left, height: floorLine - lid),
            cornerRadius: corner
        )
    }

    /// The tape down the closed seam, and only there — a line standing in the
    /// middle of a parcel that is still open is what turns it into a book.
    static var tape: Path {
        Path { path in
            path.move(to: CGPoint(x: seam, y: lid))
            path.addLine(to: CGPoint(x: seam, y: lid + 15))
        }
    }

    private static let left: CGFloat = 28
    private static let right: CGFloat = 92
    static let lid: CGFloat = 50
    static let floorLine: CGFloat = 96
    private static let corner: CGFloat = 3
    private static let seam = (left + right) / 2
    private static let nearHinge = CGPoint(x: left, y: lid)
    private static let farHinge = CGPoint(x: right, y: lid)
    private static let flapLength = seam - left
    /// How far past the vertical an open flap leans.
    private static let flapOpen: Double = 105
}

#Preview("box", traits: .sizeThatFitsLayout) {
    CalibreMark.box()
        .padding(Space.xl)
        .calibrePageBackground()
}
