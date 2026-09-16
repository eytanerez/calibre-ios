import SwiftUI
import UIKit

/// **A watch is submitted.** The same grammar as the order, the other
/// direction: the form gathers up, the wax seal presses down onto it with a
/// settle, and the seal is sent away.
///
/// The form that gathers is the listing screen as it actually stood, so this
/// film carries that seller's own words in it.
///
/// **What this platform does differently, and why.** The reference gathered a
/// card downward toward the point the seal would land on; a full phone screen
/// converges on that point on its own once the shrink is anchored there, so
/// the drop track is expressed as the anchor rather than as a second
/// hard-coded translation that would fight it on a taller screen. Stops,
/// easing and the press-and-settle beat are the reference's.
struct ListingSubmittedFilm: View {
    let time: TimeInterval
    let stage: CGSize
    let side: MomentLayer
    let outgoing: UIImage?

    static let duration: TimeInterval = 2.4

    static func contentEffect(at _: TimeInterval, stage _: CGSize) -> MomentContentEffect { .none }

    // MARK: - Beats

    private static let gather = MomentClip(delay: 0, duration: 0.6)
    private static let gatherCurve = MomentCurve(x1: 0.5, y1: 0, x2: 0.75, y2: 0)
    private static let press = MomentClip(delay: 0.5, duration: 1.7)
    private static let reveal = MomentClip(delay: 1.9, duration: 0.5)

    private static let formScale = MomentTrack(gatherCurve, [
        (at: 0, value: 1), (at: 0.72, value: 0.3), (at: 1, value: 0.1),
    ])
    private static let formInk = MomentTrack(gatherCurve, [
        (at: 0, value: 1), (at: 0.72, value: 1), (at: 1, value: 0),
    ])

    /// The press: in from above, down onto the form, the small settle that
    /// says wax gave under it, and then away off the top of the screen.
    /// The stop list is the reference's `sealPress`, and its rule named no
    /// timing function, so these run on the CSS default.
    private static let sealRise = MomentTrack(.ease, [
        (at: 0, value: -46), (at: 0.18, value: -30), (at: 0.34, value: 0),
        (at: 0.40, value: 2), (at: 0.46, value: 0), (at: 0.72, value: 0), (at: 1, value: -320),
    ])
    private static let sealScale = MomentTrack(.ease, [
        (at: 0, value: 1.5), (at: 0.18, value: 1.34), (at: 0.34, value: 1),
        (at: 0.40, value: 0.98), (at: 0.46, value: 1), (at: 0.72, value: 1), (at: 1, value: 0.72),
    ])
    private static let sealInk = MomentTrack(.ease, [
        (at: 0, value: 0), (at: 0.18, value: 1), (at: 1, value: 1),
    ])

    /// Where the seal comes to rest, and so where the form gathers to.
    private var anvil: CGPoint {
        CGPoint(x: stage.width / 2, y: stage.height * 0.48)
    }

    private var sealSide: CGFloat { stage.width * 108 / 320 }

    var body: some View {
        if side == .over, stage.width > 0 {
            ZStack {
                Color.calibre.background
                    .opacity(1 - MomentCurve.easeOut(Self.reveal.progress(time)))
                    .ignoresSafeArea()
                form
                seal
            }
            .frame(width: stage.width, height: stage.height)
        }
    }

    @ViewBuilder
    private var form: some View {
        let progress = Self.gather.progress(time)
        if let outgoing {
            Image(uiImage: outgoing)
                .resizable()
                .scaledToFill()
                .frame(width: stage.width, height: stage.height)
                .clipped()
                .scaleEffect(
                    Self.formScale.value(at: progress),
                    anchor: UnitPoint(x: 0.5, y: anvil.y / stage.height)
                )
                .opacity(Self.formInk.value(at: progress))
        }
    }

    /// The house seal, not a second drawing of one: the lobed wax, the die and
    /// the lit edge the die catches all come from `WaxSealMark`.
    private var seal: some View {
        let progress = Self.press.progress(time)
        let scale = sealSide / MarkGrid.side
        return Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            context.fill(WaxSealMark.wax, with: .color(Color.calibre.wax))
            context.stroke(
                WaxSealMark.wax,
                with: .color(Color.calibre.waxHighlight),
                style: MarkGrid.style
            )
            context.stroke(
                WaxSealMark.impression,
                with: .color(WaxSealMark.struck),
                style: MarkGrid.style
            )
        }
        .frame(width: sealSide, height: sealSide)
        .scaleEffect(Self.sealScale.value(at: progress))
        .position(x: anvil.x, y: anvil.y)
        .offset(y: CGFloat(Self.sealRise.value(at: progress)) * stage.height / 460)
        .opacity(Self.sealInk.value(at: progress))
    }
}
