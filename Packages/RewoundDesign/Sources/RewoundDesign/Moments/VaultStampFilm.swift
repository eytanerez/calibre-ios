import SwiftUI

/// **A watch is opened in the Vault.** The stamp that already sits on the card
/// stops being decoration and *stamps*: it flies in, lands with weight, the
/// card jolts under it and flecks kick off the impact.
///
/// It lands **where the small verification mark already sits** — clear of the
/// photograph and clear of the watch's name. That placement is read off the
/// screen rather than guessed at, which is what `rewoundMomentAnchor` on the
/// small mark is for; the reference's own corner placement is the fallback for
/// a screen that never registered one.
///
/// **What this platform does differently, and why.** The reference jolted the
/// one card on its stage. Here the card is the screen, so the screen takes the
/// hit — same stops, same easing, same frame of contact. The mark itself stays
/// rigid throughout, which is §5's rule and the difference between an impact
/// and a bounce.
struct VaultStampFilm: View {
    let time: TimeInterval
    let stage: CGSize
    let side: MomentLayer

    static let duration: TimeInterval = 1.12

    // MARK: - Beats

    private static let fly = MomentClip(delay: 0.18, duration: 0.68)
    private static let flyCurve = MomentCurve(x1: 0.4, y1: 0, x2: 0.28, y2: 1)
    private static let jolt = MomentClip(delay: 0.62, duration: 0.34)
    private static let joltCurve = MomentCurve(x1: 0.3, y1: 0, x2: 0.2, y2: 1)
    private static let kickOff = MomentClip(delay: 0.62, duration: 0.5)

    private static let across = MomentTrack(flyCurve, [
        (at: 0, value: 58), (at: 0.62, value: 4), (at: 0.82, value: 0), (at: 1, value: 0),
    ])
    private static let drop = MomentTrack(flyCurve, [
        (at: 0, value: -96), (at: 0.62, value: -6), (at: 0.82, value: 0), (at: 1, value: 0),
    ])
    private static let turn = MomentTrack(flyCurve, [
        (at: 0, value: -34), (at: 0.62, value: -7), (at: 0.82, value: -4), (at: 1, value: -4),
    ])
    private static let size = MomentTrack(flyCurve, [
        (at: 0, value: 2.6), (at: 0.62, value: 1.14), (at: 0.82, value: 0.97), (at: 1, value: 1),
    ])
    private static let ink = MomentTrack(flyCurve, [
        (at: 0, value: 0), (at: 0.4, value: 1), (at: 1, value: 1),
    ])

    private static let shove = MomentTrack(joltCurve, [
        (at: 0, value: 0), (at: 0.26, value: 5), (at: 0.62, value: -1), (at: 1, value: 0),
    ])
    private static let give = MomentTrack(joltCurve, [
        (at: 0, value: 1), (at: 0.26, value: 0.986), (at: 0.62, value: 1.003), (at: 1, value: 1),
    ])

    private static let fleckInk = MomentTrack(.easeOut, [
        (at: 0, value: 0), (at: 0.3, value: 0.8), (at: 1, value: 0),
    ])
    private static let fleckThrow = MomentTrack(.easeOut, [
        (at: 0, value: 0), (at: 1, value: 1),
    ])
    private static let fleckSize = MomentTrack(.easeOut, [
        (at: 0, value: 0.6), (at: 1, value: 1.25),
    ])

    /// The card takes the hit, and the card here is the screen.
    static func contentEffect(at time: TimeInterval, stage: CGSize) -> MomentContentEffect {
        guard stage.width > 0 else { return .none }
        let progress = jolt.progress(time)
        return MomentContentEffect(
            scale: give.value(at: progress),
            offset: CGSize(
                width: 0,
                height: CGFloat(shove.value(at: progress)) * stage.width / 320
            )
        )
    }

    // MARK: - The stamp

    private var side78: CGFloat { stage.width * 78 / 320 }

    /// Where it lands: the small verification mark if the Vault screen said
    /// where that ended up, otherwise the reference's own placement.
    private var target: CGPoint {
        if let frame = RewoundMoments.shared.anchors[.vaultVerification], frame.width > 0 {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return CGPoint(x: stage.width * 0.81 - side78 / 2, y: stage.height * 0.78 - side78 / 2)
    }

    var body: some View {
        if side == .over, stage.width > 0 {
            let progress = Self.fly.progress(time)
            let scale = side78 / MarkGrid.side
            Canvas { context, _ in
                context.scaleBy(x: scale, y: scale)
                context.stroke(
                    StampMark.head,
                    with: .color(Color.rewound.primary),
                    style: MarkGrid.style
                )
                context.fill(
                    RewoundLogoMark.jewelCentre.applying(StampMark.die),
                    with: .color(Color.rewound.primary)
                )
                drawFlecks(into: &context)
            }
            .frame(width: side78, height: side78)
            .scaleEffect(Self.size.value(at: progress))
            .rotationEffect(.degrees(Self.turn.value(at: progress)))
            .position(target)
            .offset(
                x: CGFloat(Self.across.value(at: progress)) * stage.width / 320,
                y: CGFloat(Self.drop.value(at: progress)) * stage.width / 320
            )
            .opacity(Self.ink.value(at: progress))
        }
    }

    /// Four short arcs thrown off the rim along the line the force went, then
    /// gone. Debris from something that happened, which is what separates it
    /// from confetti.
    private func drawFlecks(into context: inout GraphicsContext) {
        let progress = Self.kickOff.progress(time)
        let opacity = Self.fleckInk.value(at: progress)
        guard opacity > 0.001 else { return }
        let thrown = Self.fleckThrow.value(at: progress)
        let grown = Self.fleckSize.value(at: progress)

        let flecks: [(from: CGPoint, to: CGPoint, radius: CGFloat, sweep: Bool, away: CGSize)] = [
            (CGPoint(x: 24, y: 76), CGPoint(x: 31, y: 80), 9, true, CGSize(width: -16, height: -8)),
            (CGPoint(x: 96, y: 76), CGPoint(x: 89, y: 80), 9, false, CGSize(width: 16, height: -8)),
            (CGPoint(x: 42, y: 94), CGPoint(x: 49, y: 97), 8, true, CGSize(width: -9, height: 10)),
            (CGPoint(x: 78, y: 94), CGPoint(x: 71, y: 97), 8, false, CGSize(width: 9, height: 10)),
        ]

        context.opacity = opacity
        for fleck in flecks {
            let arc = Self.arc(from: fleck.from, to: fleck.to, radius: fleck.radius, sweep: fleck.sweep)
            let center = CGPoint(x: (fleck.from.x + fleck.to.x) / 2, y: (fleck.from.y + fleck.to.y) / 2)
            let moved = arc.applying(
                CGAffineTransform(
                    translationX: center.x + fleck.away.width * CGFloat(thrown),
                    y: center.y + fleck.away.height * CGFloat(thrown)
                )
                .scaledBy(x: CGFloat(grown), y: CGFloat(grown))
                .translatedBy(x: -center.x, y: -center.y)
            )
            context.stroke(moved, with: .color(Color.rewound.primary), style: MarkGrid.style)
        }
    }

    /// The reference draws each fleck as an SVG endpoint arc — two points, a
    /// radius and a sweep flag. This is the standard conversion of that form
    /// to the center-and-sweep one `Path.addCircularArc` takes, for the case
    /// the drawing uses: equal radii, no rotation, short way round.
    private static func arc(from: CGPoint, to: CGPoint, radius: CGFloat, sweep: Bool) -> Path {
        let span = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let chord = hypot(span.x, span.y)
        guard chord > 0, radius >= chord / 2 else {
            var line = Path()
            line.move(to: from)
            line.addLine(to: to)
            return line
        }
        let half = chord / 2
        let offset = (radius * radius - half * half).squareRoot()
        let perpendicular = CGPoint(x: -span.y / chord, y: span.x / chord)
        let direction: CGFloat = sweep ? 1 : -1
        let center = CGPoint(
            x: (from.x + to.x) / 2 + direction * offset * perpendicular.x,
            y: (from.y + to.y) / 2 + direction * offset * perpendicular.y
        )
        let start = atan2(from.y - center.y, from.x - center.x)
        let end = atan2(to.y - center.y, to.x - center.x)
        var delta = end - start
        if sweep, delta < 0 { delta += 2 * .pi }
        if !sweep, delta > 0 { delta -= 2 * .pi }

        var path = Path()
        path.addCircularArc(
            center: center,
            radius: radius,
            start: .radians(start),
            delta: .radians(delta)
        )
        return path
    }
}
