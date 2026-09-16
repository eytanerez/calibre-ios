import SwiftUI

/// **An offer is accepted.** A fist bump — not a handshake, and not a redrawn
/// fist bump: the outline is `FistBumpDrawing`, transcribed from the approved
/// artwork so the three surfaces ship the same pair of hands.
///
/// Two fists come in from opposite edges, check for an instant, bump, the
/// impact ticks off, and then checkout rises.
///
/// **What this platform does differently, and why.** The reference slid a
/// checkout card up over the dimmed fists. Here checkout is a screen rather
/// than a card, so the screen itself rises on the same clip — same delay, same
/// duration, same easing — and the fists dim behind it exactly as they did.
struct OfferAcceptedFilm: View {
    let time: TimeInterval
    let stage: CGSize
    let side: MomentLayer

    static let duration: TimeInterval = 2.08

    // MARK: - Beats

    private static let bump = MomentClip(delay: 0.1, duration: 1.15)
    private static let bumpCurve = MomentCurve(x1: 0.4, y1: 0, x2: 0.3, y2: 1)
    private static let ticks = MomentClip(delay: 0.74, duration: 0.34)
    private static let dim = MomentClip(delay: 1.5, duration: 0.4)
    private static let rise = MomentClip(delay: 1.5, duration: 0.58)
    private static let riseCurve = MomentCurve(x1: 0.25, y1: 0.9, x2: 0.3, y2: 1)

    /// In from the edge, the check just short of contact, the bump, and two
    /// diminishing rebounds. The right fist is this mirrored.
    private static let approach = MomentTrack(bumpCurve, [
        (at: 0, value: -130), (at: 0.34, value: -22), (at: 0.42, value: -26),
        (at: 0.56, value: 0), (at: 0.66, value: -6), (at: 0.80, value: -1), (at: 1, value: 0),
    ])
    private static let fistInk = MomentTrack(bumpCurve, [
        (at: 0, value: 0), (at: 0.14, value: 1), (at: 1, value: 1),
    ])
    private static let tickInk = MomentTrack(.easeOut, [
        (at: 0, value: 0), (at: 0.3, value: 0.5), (at: 1, value: 0),
    ])
    private static let tickSize = MomentTrack(.easeOut, [
        (at: 0, value: 0.7), (at: 0.3, value: 1), (at: 1, value: 1.18),
    ])

    /// Checkout rises. Before the clip opens it is a full screen below the
    /// edge, which is the reference's own resting `translateY(105%)`.
    static func contentEffect(at time: TimeInterval, stage: CGSize) -> MomentContentEffect {
        guard stage.width > 0 else { return .none }
        let risen = riseCurve(rise.progress(time))
        return MomentContentEffect(
            offset: CGSize(width: 0, height: stage.height * 1.05 * CGFloat(1 - risen))
        )
    }

    var body: some View {
        if side == .under, stage.width > 0 {
            let width = stage.width * FistBumpDrawing.field.width / 320
            let scale = width / FistBumpDrawing.field.width
            let height = FistBumpDrawing.field.height * scale
            ZStack {
                // The ground checkout rises off. Without it the screen below
                // the fists is whatever the app was showing, sitting still.
                Color.rewound.background
                    .ignoresSafeArea()
                fists
                    .frame(width: width, height: height)
                    .position(x: stage.width / 2, y: stage.height * 0.44)
                    .opacity(1 - 0.82 * MomentCurve.easeOut(Self.dim.progress(time)))
            }
            .frame(width: stage.width, height: stage.height)
        }
    }

    private var fists: some View {
        let progress = Self.bump.progress(time)
        let travel = CGFloat(Self.approach.value(at: progress)) * stage.width / 320
        let opacity = Self.fistInk.value(at: progress)
        let tickProgress = Self.ticks.progress(time)

        return Canvas { context, size in
            let scale = size.width / FistBumpDrawing.field.width
            context.scaleBy(x: scale, y: scale)
            context.opacity = opacity

            var left = context
            left.translateBy(x: travel, y: 0)
            left.stroke(FistBumpDrawing.fist, with: .color(Color.rewound.primary), style: MarkGrid.style)
            left.stroke(FistBumpDrawing.creases, with: .color(Color.rewound.primary), style: MarkGrid.style)

            var right = context
            right.translateBy(x: -travel, y: 0)
            right.stroke(
                FistBumpDrawing.fist.applying(FistBumpDrawing.mirror),
                with: .color(Color.rewound.primary),
                style: MarkGrid.style
            )
            right.stroke(
                FistBumpDrawing.creases.applying(FistBumpDrawing.mirror),
                with: .color(Color.rewound.primary),
                style: MarkGrid.style
            )

            let tickInk = Self.tickInk.value(at: tickProgress)
            guard tickInk > 0.001 else { return }
            var struck = context
            struck.opacity = tickInk
            let grown = CGFloat(Self.tickSize.value(at: tickProgress))
            let center = CGPoint(
                x: FistBumpDrawing.field.width / 2,
                y: FistBumpDrawing.field.height / 2
            )
            struck.stroke(
                FistBumpDrawing.ticks.applying(
                    CGAffineTransform(translationX: center.x, y: center.y)
                        .scaledBy(x: grown, y: grown)
                        .translatedBy(x: -center.x, y: -center.y)
                ),
                with: .color(Color.rewound.primary),
                style: StrokeStyle(
                    lineWidth: FistBumpDrawing.tickStroke,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
}
