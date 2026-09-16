import SwiftUI

/// **A report is opened.** The envelope is shut, and a shut envelope shows its
/// flap on top with the wax seal on the flap's point. The seal cracks off, the
/// flap drops behind as it swings open, the report slides out — and then it
/// grows to fill the whole screen while the envelope fades. The stamp presses
/// on last.
///
/// The report is the **page**, not a prop: what is inside the envelope is the
/// top of the authentication report itself, cropped to a letter-shaped window,
/// and what fills the screen at the end is that same page at full size. The
/// rows are that watch's real findings for the same reason the order sequence
/// collapses the real order page.
///
/// **What this platform does differently, and why.** The reference grew the
/// report by animating its width and height, which re-flows text at every
/// frame — a browser can, and a phone re-laying-out a whole screen sixty times
/// a second cannot. Here the window and the page's scale grow together, so the
/// crop and the size do exactly what they did while the type inside stays
/// laid out once. Every stop percentage, easing and delay is the reference's.
struct ReportOpenedFilm: View {
    let time: TimeInterval
    let stage: CGSize
    let side: MomentLayer

    static let duration: TimeInterval = 2.55

    // MARK: - Beats

    private static let crack = MomentClip(delay: 0.1, duration: 0.5)
    private static let crackCurve = MomentCurve(x1: 0.35, y1: 0, x2: 0.3, y2: 1)
    private static let openFlap = MomentClip(delay: 0.5, duration: 0.38)
    private static let flapCurve = MomentCurve(x1: 0.4, y1: 0, x2: 0.3, y2: 1)
    private static let slideOut = MomentClip(delay: 0.8, duration: 1.45)
    private static let slideCurve = MomentCurve(x1: 0.3, y1: 0.85, x2: 0.35, y2: 1)
    private static let envelopeGone = MomentClip(delay: 1.62, duration: 0.3)
    private static let stampDown = MomentClip(delay: 2.1, duration: 0.45)
    private static let stampCurve = MomentCurve(x1: 0.45, y1: 0, x2: 0.35, y2: 1)

    /// The frame at which the report passes in front of the envelope it came
    /// out of. Before it, the envelope is drawn over the page; after it, under.
    private static let reportRisesAbove = 0.37

    private static let reportInk = MomentTrack(slideCurve, [
        (at: 0, value: 0), (at: 0.08, value: 1), (at: 1, value: 1),
    ])
    /// Out of the envelope, then back down as it becomes the screen.
    private static let reportLift = MomentTrack(slideCurve, [
        (at: 0, value: 14), (at: 0.38, value: -150), (at: 0.55, value: -150), (at: 1, value: 0),
    ])
    private static let reportGrows = MomentTrack(slideCurve, [
        (at: 0, value: 0), (at: 0.38, value: 0), (at: 0.55, value: 0), (at: 1, value: 1),
    ])

    private static let sealAcross = MomentTrack(crackCurve, [
        (at: 0, value: 0), (at: 0.22, value: 0), (at: 0.32, value: 2), (at: 1, value: 150),
    ])
    private static let sealUp = MomentTrack(crackCurve, [
        (at: 0, value: 0), (at: 0.22, value: -3), (at: 0.32, value: 1), (at: 1, value: -180),
    ])
    private static let sealTurn = MomentTrack(crackCurve, [
        (at: 0, value: 0), (at: 0.22, value: -4), (at: 0.32, value: 3), (at: 1, value: 130),
    ])
    private static let sealSize = MomentTrack(crackCurve, [
        (at: 0, value: 1), (at: 0.22, value: 1.06), (at: 0.32, value: 1), (at: 1, value: 0.6),
    ])
    private static let sealInk = MomentTrack(crackCurve, [
        (at: 0, value: 1), (at: 0.32, value: 1), (at: 1, value: 0),
    ])

    private static let stampAcross = MomentTrack(stampCurve, [
        (at: 0, value: 26), (at: 0.55, value: 4), (at: 0.78, value: 0), (at: 1, value: 0),
    ])
    private static let stampDrop = MomentTrack(stampCurve, [
        (at: 0, value: -46), (at: 0.55, value: -6), (at: 0.78, value: 0), (at: 1, value: 0),
    ])
    private static let stampTurn = MomentTrack(stampCurve, [
        (at: 0, value: -24), (at: 0.55, value: -9), (at: 0.78, value: -7), (at: 1, value: -7),
    ])
    private static let stampSize = MomentTrack(stampCurve, [
        (at: 0, value: 2.2), (at: 0.55, value: 1.16), (at: 0.78, value: 0.97), (at: 1, value: 1),
    ])
    private static let stampInk = MomentTrack(stampCurve, [
        (at: 0, value: 0), (at: 0.55, value: 1), (at: 1, value: 1),
    ])

    // MARK: - Geometry

    /// The envelope, and the letter-shaped window cut in the page inside it.
    private struct Envelope {
        let rect: CGRect
        let scale: CGFloat
        let window: CGRect

        init(_ stage: CGSize) {
            let width = stage.width * 200 / 320
            scale = width / 200
            let height = 132 * scale
            rect = CGRect(
                x: (stage.width - width) / 2,
                y: stage.height * 0.60 - height / 2,
                width: width,
                height: height
            )
            window = CGRect(
                x: rect.minX + 16 * scale,
                y: rect.minY - 2 * scale,
                width: 168 * scale,
                height: 130 * scale
            )
        }
    }

    /// Where the report is at `time`: the window it shows through, and how far
    /// along it is toward being the whole screen.
    private static func report(at time: TimeInterval, stage: CGSize) -> (window: CGRect, grown: Double) {
        let progress = slideOut.progress(time)
        let envelope = Envelope(stage)
        let grown = reportGrows.value(at: progress)
        let lift = CGFloat(reportLift.value(at: progress)) * stage.height / 460
        let full = CGRect(origin: .zero, size: stage)
        let window = CGRect(
            x: momentLerp(envelope.window.minX, full.minX, grown),
            y: momentLerp(envelope.window.minY, full.minY, grown) + lift * CGFloat(1 - grown),
            width: momentLerp(envelope.window.width, full.width, grown),
            height: momentLerp(envelope.window.height, full.height, grown)
        )
        return (window, grown)
    }

    /// The page is scaled about its own top edge and then dropped to the
    /// window, so the crop and the type inside it move together. Everything
    /// here is in the app screen's coordinates, which is the space the clip is
    /// read in.
    static func contentEffect(at time: TimeInterval, stage: CGSize) -> MomentContentEffect {
        guard stage.width > 0 else { return .none }
        let (window, grown) = report(at: time, stage: stage)
        let scale = Envelope(stage).scale
        return MomentContentEffect(
            scale: Double(window.width / stage.width),
            anchor: .top,
            offset: CGSize(width: 0, height: window.minY),
            opacity: reportInk.value(at: slideOut.progress(time)),
            window: window,
            windowCorner: 6 * scale * CGFloat(1 - grown)
        )
    }

    // MARK: - Layers

    var body: some View {
        if stage.width > 0 {
            let progress = Self.slideOut.progress(time)
            let above = progress >= Self.reportRisesAbove
            ZStack {
                if side == .under {
                    // The ground the report is cut out of. Outside its window
                    // the page is clipped away, and this is what is there.
                    Color.rewound.background
                        .ignoresSafeArea()
                }
                // The envelope crosses behind the report as it rises: over the
                // page while it is still inside, under it once it is out.
                if side == (above ? .under : .over) {
                    envelope
                }
                if side == .over {
                    reportEdge
                    stamp
                }
            }
            .frame(width: stage.width, height: stage.height)
        }
    }

    /// The hairline and the lift-off shadow that make the report read as a
    /// sheet standing off the envelope rather than as a hole in the film.
    private var reportEdge: some View {
        let (window, grown) = Self.report(at: time, stage: stage)
        let scale = Envelope(stage).scale
        return MomentFixedPath(
            path: Path(
                roundedRect: window,
                cornerRadius: 6 * scale * CGFloat(1 - grown),
                style: .continuous
            )
        )
        .stroke(Color.rewound.borderBright, lineWidth: 1)
        .opacity((1 - grown) * Self.reportInk.value(at: Self.slideOut.progress(time)))
    }

    private var envelope: some View {
        let shape = Envelope(stage)
        let opened = Self.flapCurve(Self.openFlap.progress(time))
        return ZStack {
            pocket(shape)
            // Past the halfway point of the swing the flap is behind the
            // envelope, which is what "shut envelope, flap on top" means once
            // it is no longer shut.
            if opened < 0.5 { flap(shape) }
            waxSeal(shape)
        }
        .background {
            if opened >= 0.5 { flap(shape) }
        }
        .opacity(1 - MomentCurve.easeOut(Self.envelopeGone.progress(time)))
    }

    private func pocket(_ shape: Envelope) -> some View {
        RoundedRectangle(cornerRadius: 8 * shape.scale, style: .continuous)
            .fill(Color.rewound.secondary)
            .overlay {
                RoundedRectangle(cornerRadius: 8 * shape.scale, style: .continuous)
                    .stroke(Color.rewound.borderBright, lineWidth: 1)
            }
            .frame(width: shape.rect.width, height: shape.rect.height)
            .position(x: shape.rect.midX, y: shape.rect.midY)
    }

    private func flap(_ shape: Envelope) -> some View {
        let height = 66 * shape.scale
        return Canvas { context, size in
            var triangle = Path()
            triangle.move(to: .zero)
            triangle.addLine(to: CGPoint(x: size.width / 2, y: size.height * 60 / 66))
            triangle.addLine(to: CGPoint(x: size.width, y: 0))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(Color.rewound.accent))
            context.stroke(triangle, with: .color(Color.rewound.borderBright), lineWidth: 2 * shape.scale)
        }
        .frame(width: shape.rect.width, height: height)
        .rotation3DEffect(
            .degrees(168 * Self.flapCurve(Self.openFlap.progress(time))),
            axis: (x: 1, y: 0, z: 0),
            anchor: .top,
            // Flat, the way an untransformed CSS `rotateX` is: with a
            // perspective the flap would swing toward the eye and read as a
            // lid rather than as paper folding back.
            perspective: 0
        )
        .position(x: shape.rect.midX, y: shape.rect.minY + height / 2)
    }

    /// The seal on the flap's point, and the crack that takes it off.
    private func waxSeal(_ shape: Envelope) -> some View {
        let progress = Self.crack.progress(time)
        let side = 54 * shape.scale
        return Canvas { context, _ in
            context.scaleBy(x: side / MarkGrid.side, y: side / MarkGrid.side)
            context.fill(WaxSealMark.wax, with: .color(Color.rewound.wax))
            context.stroke(
                WaxSealMark.wax,
                with: .color(Color.rewound.waxHighlight),
                style: MarkGrid.style
            )
        }
        .frame(width: side, height: side)
        .scaleEffect(Self.sealSize.value(at: progress))
        .rotationEffect(.degrees(Self.sealTurn.value(at: progress)))
        .position(x: shape.rect.midX, y: shape.rect.minY + 71 * shape.scale)
        .offset(
            x: CGFloat(Self.sealAcross.value(at: progress)) * stage.width / 320,
            y: CGFloat(Self.sealUp.value(at: progress)) * stage.height / 460
        )
        .opacity(Self.sealInk.value(at: progress))
    }

    /// The house stamp, pressed onto the report once it is the screen.
    private var stamp: some View {
        let progress = Self.stampDown.progress(time)
        let side = stage.width * 92 / 320
        let scale = side / MarkGrid.side
        return Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            context.stroke(StampMark.head, with: .color(Color.rewound.primary), style: MarkGrid.style)
            context.fill(
                RewoundLogoMark.jewelCentre.applying(StampMark.die),
                with: .color(Color.rewound.primary)
            )
        }
        .frame(width: side, height: side)
        .scaleEffect(Self.stampSize.value(at: progress))
        .rotationEffect(.degrees(Self.stampTurn.value(at: progress)))
        .position(
            x: stage.width * 0.93 - side / 2,
            y: stage.height * 0.94 - side / 2
        )
        .offset(
            x: CGFloat(Self.stampAcross.value(at: progress)) * stage.width / 320,
            y: CGFloat(Self.stampDrop.value(at: progress)) * stage.width / 320
        )
        .opacity(Self.stampInk.value(at: progress))
    }
}
