import SwiftUI
import UIKit

/// **An order is placed.** The biggest of the five.
///
/// The box is already open when the film starts, flaps up, and its front panel
/// is opaque — so the page you were on genuinely disappears *into* it rather
/// than dissolving beside it. Then the flaps fold shut over it, one after the
/// other, and the box tips and flies off, leaving the order underneath.
///
/// The page that collapses is the screen as it actually stood a frame earlier,
/// so this is a different film for every order and nobody drew any of them.
///
/// **What this platform does differently, and why.** The reference collapsed a
/// card sitting on a stage; here it collapses a whole phone screen, which is a
/// much taller shape. Two consequences: the drop is measured against the box's
/// mouth so the page arrives there at any screen aspect instead of riding a
/// hard-coded translation, and the page is clipped along the box's own bottom
/// edge as it falls — without that its tail hangs out below the carton, which
/// is the one thing a full-screen page does that a small card never did. The
/// beat order, the stop percentages and the easings are unchanged.
///
/// **Where it lands.** The page's TOP edge finishes on the mouth, which is the
/// landing the reference has: everything of it is then under the flaps and
/// behind the opaque front panel, and the box has swallowed a page rather than
/// worn one. Getting that wrong is subtle and it was wrong: the shrink used to
/// be anchored ON the mouth, which holds that one line still and converges the
/// page around it — so half of the shrinking page sat above the opening,
/// in front of the carton, for the whole fall, and then faded out there.
/// Frozen at 0.6s it read as a page resting on top of an open box.
struct OrderPlacedFilm: View {
    let time: TimeInterval
    let stage: CGSize
    let side: MomentLayer
    let outgoing: UIImage?

    static let duration: TimeInterval = 2.45

    /// The page falls; nothing moves the destination screen, which simply
    /// waits underneath until the ground clears.
    static func contentEffect(at _: TimeInterval, stage _: CGSize) -> MomentContentEffect { .none }

    // MARK: - Beats

    private static let fall = MomentClip(delay: 0, duration: 0.8)
    private static let fallCurve = MomentCurve(x1: 0.45, y1: 0, x2: 0.8, y2: 0.25)
    private static let nearFlap = MomentClip(delay: 0.78, duration: 0.34)
    private static let farFlap = MomentClip(delay: 0.88, duration: 0.34)
    private static let flapCurve = MomentCurve(x1: 0.5, y1: 0, x2: 0.4, y2: 1)
    private static let departure = MomentClip(delay: 1.3, duration: 0.95)
    private static let departureCurve = MomentCurve(x1: 0.45, y1: 0, x2: 0.75, y2: 0.2)
    private static let reveal = MomentClip(delay: 1.95, duration: 0.5)

    /// What the page has shrunk to once it is inside. The drop is measured
    /// against it and the track ends on it, and it is written once so those
    /// two readings are the same number rather than two copies of it — a
    /// second copy left free to be edited alone is how the page ends up
    /// overshooting the mouth and landing inside the carton wall.
    private static let landed = 0.14
    static let pageScale = MomentTrack(fallCurve, [
        (at: 0, value: 1), (at: 0.55, value: 0.45), (at: 0.92, value: 0.16), (at: 1, value: landed),
    ])
    private static let pageInk = MomentTrack(fallCurve, [
        (at: 0, value: 1), (at: 0.92, value: 1), (at: 1, value: 0),
    ])
    private static let travel = MomentTrack(departureCurve, [
        (at: 0, value: 0), (at: 0.2, value: -16), (at: 1, value: 460),
    ])
    private static let tip = MomentTrack(departureCurve, [
        (at: 0, value: 0), (at: 0.2, value: -5), (at: 1, value: 18),
    ])

    // MARK: - Geometry

    /// The carton, sized off the screen's width the way every mark is sized
    /// off the square it is drawn on.
    struct Carton {
        let rect: CGRect
        let scale: CGFloat
        /// The line the flaps hinge on — the mouth the page drops through.
        var mouthY: CGFloat { rect.minY + 38 * scale }
        /// The carton's own floor. Below it there is no opaque panel, so this
        /// is where the falling page has to stop being drawn.
        var floorY: CGFloat { rect.minY + 88 * scale }

        init(_ stage: CGSize) {
            let width = stage.width * 132 / 320
            scale = width / 132
            let height = 96 * scale
            rect = CGRect(
                x: (stage.width - width) / 2,
                y: stage.height * 0.54 - height / 2,
                width: width,
                height: height
            )
        }
    }

    var body: some View {
        if side == .over, stage.width > 0 {
            let box = Carton(stage)
            ZStack {
                // The ground the film plays on, holding the destination back
                // until the box has gone.
                // Bleeds past the app's own screen: the safe-area strips are
                // part of what the film covers, or the destination shows
                // through them while the box is still on its way.
                Color.rewound.background
                    .opacity(1 - MomentCurve.easeOut(Self.reveal.progress(time)))
                    .ignoresSafeArea()
                page(box)
                carton(box)
            }
            .frame(width: stage.width, height: stage.height)
        }
    }

    /// The screen you were on, shrinking and dropping into the mouth of the
    /// box until the box has all of it.
    @ViewBuilder
    private func page(_ box: Carton) -> some View {
        let progress = Self.fall.progress(time)
        if let outgoing {
            Image(uiImage: outgoing)
                .resizable()
                .scaledToFill()
                .frame(width: stage.width, height: stage.height)
                .clipped()
                .scaleEffect(Self.pageScale.value(at: progress))
                .offset(y: Self.drop(box, at: progress, stage: stage))
                .clipShape(MomentFixedPath(path: Path(Self.swallowed(box, at: progress, stage: stage))))
                .opacity(Self.pageInk.value(at: progress))
        }
    }

    /// Where the shrinking page's top edge is, in stage coordinates.
    ///
    /// It travels from the top of the screen to the box's mouth over the same
    /// journey the shrink makes: at rest it is zero and the page is the
    /// screen; at the end it is the mouth, and every pixel of the page is
    /// under the flaps and behind the carton's opaque front panel.
    ///
    /// This is the whole of the landing, and it is the arithmetic that was
    /// wrong: the shrink used to be anchored ON the mouth, which holds that
    /// one line still and converges the page around it, so the top edge
    /// finished a seventh of the mouth's depth *above* the opening and half
    /// the page sat in front of the carton for the entire fall.
    static func pageTop(_ box: Carton, at progress: Double) -> CGFloat {
        let scale = pageScale.value(at: progress)
        return CGFloat((1 - scale) / (1 - landed)) * box.mouthY
    }

    /// The `offset` that puts a center-anchored `scaleEffect` there. A page
    /// drawn at `scale` already sits `stage.height * (1 - scale) / 2` down the
    /// screen before anything moves it, because that is where converging on
    /// its own middle leaves it.
    static func drop(_ box: Carton, at progress: Double, stage: CGSize) -> CGFloat {
        let scale = pageScale.value(at: progress)
        return pageTop(box, at: progress) - stage.height * CGFloat(1 - scale) / 2
    }

    /// What is still above the box. The carton's front panel is opaque, so
    /// anything between the mouth and the floor is already hidden; this cuts
    /// the tail a full-screen page would otherwise trail below the carton.
    static func swallowed(_ box: Carton, at progress: Double, stage: CGSize) -> CGRect {
        let bottom = MomentTrack(fallCurve, [
            (at: 0, value: Double(stage.height)),
            (at: 0.55, value: Double(box.floorY)),
            (at: 1, value: Double(box.floorY)),
        ]).value(at: progress)
        return CGRect(x: 0, y: 0, width: stage.width, height: CGFloat(bottom))
    }

    private func carton(_ box: Carton) -> some View {
        let departed = Self.departure.progress(time)
        return Canvas { context, _ in
            context.scaleBy(x: box.scale, y: box.scale)

            var walls = Path()
            walls.move(to: CGPoint(x: 14, y: 38))
            walls.addLine(to: CGPoint(x: 14, y: 88))
            walls.addLine(to: CGPoint(x: 118, y: 88))
            walls.addLine(to: CGPoint(x: 118, y: 38))

            // Opaque, and only then washed with the copper: the page has to
            // vanish behind this panel rather than show through it.
            var panel = walls
            panel.closeSubpath()
            context.fill(panel, with: .color(Color.rewound.background))
            context.fill(panel, with: .color(Color.rewound.primary.opacity(0.10)))
            context.stroke(walls, with: .color(Color.rewound.primary), style: MarkGrid.style)

            for flap in [
                flap(hinge: CGPoint(x: 14, y: 38), tip: CGPoint(x: 66, y: 38), open: -104, clip: Self.nearFlap),
                flap(hinge: CGPoint(x: 118, y: 38), tip: CGPoint(x: 66, y: 38), open: 104, clip: Self.farFlap),
            ] {
                context.stroke(flap, with: .color(Color.rewound.primary), style: MarkGrid.style)
            }
        }
        .frame(width: box.rect.width, height: box.rect.height)
        .position(x: box.rect.midX, y: box.rect.midY)
        .rotationEffect(.degrees(Self.tip.value(at: departed)))
        .offset(x: CGFloat(Self.travel.value(at: departed)) * stage.width / 320)
    }

    /// A flap swings on the hinge it is drawn from: standing well past the
    /// vertical while the box is open, lying on the seam once it has closed.
    private func flap(hinge: CGPoint, tip: CGPoint, open: Double, clip: MomentClip) -> Path {
        let closed = Self.flapCurve(clip.progress(time))
        let length = hypot(tip.x - hinge.x, tip.y - hinge.y)
        let rest = Angle.radians(atan2(tip.y - hinge.y, tip.x - hinge.x))
        var path = Path()
        path.move(to: hinge)
        path.addLine(to: markPoint(hinge, length, rest + .degrees(open * (1 - closed))))
        return path
    }
}
