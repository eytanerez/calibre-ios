import SwiftUI

/// Kept — a watch in its place. One recess of a tray, and the watch head that
/// lives in it, coming up out of the slot: the Vault has just been opened and
/// there is something in it.
///
/// The ninth mark, and the one place the "eight marks, no more" rule has been
/// spent. It is ported from the vault study (`a-vault.svg`) into the
/// vocabulary rather than copied from it: the study's tray, three recesses,
/// hands, crown and hairlines do not carry. What carries is the idea — a
/// recess that stays put and a head that lifts — drawn as one ink at the one
/// stroke weight. The head is the logo's own jewel at its own ring-to-centre
/// proportion, which is why its centre is filled: it is the same jewel the
/// loupe magnifies, and that fill is the logo's, not a new one.
///
/// It lifts rather than opens: the recess never moves, because the reaction
/// happens around the object. The head sinks a breath, rises past its rest
/// with a tilt, and settles — and the end state is the lifted, tilted head
/// over its slot, which is also the only frame reduced motion shows.
struct VaultMark: View {
    private var stillness = MarkStillness()

    let size: CGFloat
    let trigger: AnyHashable

    private struct Frame {
        /// Grid units above where the head lay in its slot. Negative is the
        /// wind-up sink.
        var rise: CGFloat = 0
        var tilt: Double = 0
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
                    KeyframeTrack(\.rise) {
                        // Settle first, then up and past, then back onto rest.
                        LinearKeyframe(-MarkMotion.sinkDepth, duration: MarkMotion.sink, timingCurve: MarkMotion.settling)
                        LinearKeyframe(
                            MarkMotion.liftHeight + MarkMotion.liftFollowThrough,
                            duration: MarkMotion.rise,
                            timingCurve: MarkMotion.falling
                        )
                        LinearKeyframe(
                            MarkMotion.liftHeight,
                            duration: MarkMotion.liftSettle,
                            timingCurve: MarkMotion.settling
                        )
                    }
                    KeyframeTrack(\.tilt) {
                        LinearKeyframe(0, duration: MarkMotion.sink)
                        LinearKeyframe(
                            MarkMotion.liftTilt.degrees * 1.15,
                            duration: MarkMotion.rise,
                            timingCurve: MarkMotion.falling
                        )
                        LinearKeyframe(
                            MarkMotion.liftTilt.degrees,
                            duration: MarkMotion.liftSettle,
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
            Self.slot.stroke(Color.calibre.primary, style: MarkGrid.style)
            head
                .rotationEffect(
                    .degrees(frame.tilt),
                    anchor: UnitPoint(
                        x: Self.headCentre.x / MarkGrid.side,
                        y: Self.headCentre.y / MarkGrid.side
                    )
                )
                .offset(y: -frame.rise)
        }
    }

    /// The watch: ring, filled centre, and the two lug shoulders.
    private var head: some View {
        ZStack {
            Self.ring.stroke(Color.calibre.primary, style: MarkGrid.style)
            Self.lugs.stroke(Color.calibre.primary, style: MarkGrid.style)
            Self.jewelCentre.fill(Color.calibre.primary)
        }
    }

    /// The recess: an arc-ended slot, a tray's shape for one watch. Fully
    /// rounded on its short sides so it reads as a place something was cut
    /// for, rather than as a card.
    static var slot: Path {
        Path(
            roundedRect: CGRect(
                x: slotCentre.x - slotWidth / 2,
                y: slotCentre.y - slotHeight / 2,
                width: slotWidth,
                height: slotHeight
            ),
            cornerRadius: slotWidth / 2
        )
    }

    /// The logo's jewel ring, grown to a watch head.
    static var ring: Path {
        Path(ellipseIn: CGRect(
            x: headCentre.x - ringRadius, y: headCentre.y - ringRadius,
            width: ringRadius * 2, height: ringRadius * 2
        ))
    }

    /// And its centre, at the logo's own ratio to the ring (§3: r 4.88 inside
    /// r 10.71). The one fill in this mark, and it is the logo's.
    static var jewelCentre: Path {
        let radius = ringRadius * centreRatio
        return Path(ellipseIn: CGRect(
            x: headCentre.x - radius, y: headCentre.y - radius,
            width: radius * 2, height: radius * 2
        ))
    }

    /// Two short arcs, one above the head and one below, where the strap
    /// would leave it. Short, so they read as shoulders and not as a second
    /// ring; concentric, so they turn with the head when it tilts.
    static var lugs: Path {
        var path = Path()
        for shoulder in lugAngles {
            // Each shoulder is its own subpath: appended to one path in turn,
            // the arc helper would join the second to the first with a line
            // straight across the head.
            var arc = Path()
            arc.addCircularArc(
                centre: headCentre,
                radius: lugRadius,
                start: .degrees(shoulder.degrees - lugSpan.degrees / 2),
                delta: lugSpan
            )
            path.addPath(arc)
        }
        return path
    }

    /// Where the head lies before it is lifted — low in its slot, the way a
    /// watch sits in a tray.
    static let headCentre = CGPoint(x: 60, y: 72)
    static let ringRadius: CGFloat = 16
    /// `4.88 / 10.71`, straight off the logo.
    static let centreRatio: CGFloat = 4.88 / 10.71
    static let lugRadius: CGFloat = 24
    static let lugAngles: [Angle] = [.degrees(270), .degrees(90)]
    static var lugSpan: Angle { .degrees(40) }

    static let slotCentre = CGPoint(x: 60, y: 60)
    static let slotWidth: CGFloat = 48
    static let slotHeight: CGFloat = 96

    /// Where the lift comes to rest — and, being the same value rather than
    /// a matching one, exactly what reduced motion renders.
    private static let rested = Frame(rise: MarkMotion.liftHeight, tilt: MarkMotion.liftTilt.degrees)

    /// The rested frame's numbers, for a test to hold against the motion.
    static var restedLift: (rise: CGFloat, tilt: Double) { (rested.rise, rested.tilt) }
}

#Preview("vault", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.xl) {
        CalibreMark.vault()
        CalibreMark.vault(size: 48)
    }
    .padding(Space.xl)
    .calibrePageBackground()
}
