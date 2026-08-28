import SwiftUI

/// Discrete progress — seller setup advancing, a listing draft saving. It
/// winds: a run of clicks, each one going a few degrees past its detent and
/// catching. The overshoot is the entire mark. Turn it smoothly and it becomes
/// a spinner, which says the opposite thing.
struct CrownMark: View {
    private var stillness = MarkStillness()
    @State private var turn: Double = 0

    let size: CGFloat
    let trigger: AnyHashable

    init(size: CGFloat, trigger: AnyHashable) {
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        ZStack {
            Self.knurl.stroke(Color.calibre.primary, style: MarkGrid.style)
            rim.stroke(Color.calibre.primary, style: MarkGrid.style)
        }
        .rotationEffect(.degrees(turn))
        .markCanvas(size)
        .onAppear(perform: wind)
        .onChange(of: trigger) { _, _ in wind() }
        .accessibilityHidden(true)
    }

    /// A click at a time, each one landing past its detent and settling back
    /// onto it. Written as a sequence rather than as keyframes because the
    /// number of clicks belongs to `MarkMotion`, and unrolling them here would
    /// put a second copy of that number next to the first.
    private func wind() {
        guard !stillness.isRequested else {
            turn = Self.wound
            return
        }
        turn = 0
        click(Self.firstClick)
    }

    private func click(_ index: Int) {
        guard index <= MarkMotion.clicks else { return }
        let detent = MarkMotion.clickTurn.degrees * Double(index)
        withAnimation(MarkMotion.falling(MarkMotion.click * 0.68)) {
            turn = detent + MarkMotion.clickOvershoot.degrees
        } completion: {
            withAnimation(MarkMotion.settling(MarkMotion.click * 0.32)) {
                turn = detent
            } completion: {
                click(index + 1)
            }
        }
    }

    /// Rim and the concentric collar inside it.
    private var rim: Path {
        Path { path in
            path.addEllipse(in: CGRect(x: 28, y: 28, width: 64, height: 64))
            path.addEllipse(in: CGRect(x: 45, y: 45, width: 30, height: 30))
        }
    }

    /// The knurling. What the eye actually tracks when the crown turns — the
    /// rim alone is a circle, and a circle turning looks like nothing at all.
    /// Round-capped and at the system weight, because a sawtooth here reads as
    /// a settings gear, which is a control and says the opposite thing.
    ///
    /// Spaced one click apart, so a click lands the next knurl exactly where
    /// the last one stood and the catch has something to catch on. Which is
    /// also why one of them stands proud: with all of them alike, a turn of
    /// exactly one click redraws the same picture.
    static var knurl: Path {
        Path { path in
            let knurls = Int((360 / MarkMotion.clickTurn.degrees).rounded())
            for index in 0..<knurls {
                let angle = Angle.degrees(MarkMotion.clickTurn.degrees * Double(index))
                path.move(to: markPoint(MarkGrid.centre, 32, angle))
                path.addLine(to: markPoint(MarkGrid.centre, index == 0 ? 45 : 40, angle))
            }
        }
    }

    private static let firstClick = 1
    /// Where a full wind leaves it.
    private static var wound: Double { MarkMotion.clickTurn.degrees * Double(MarkMotion.clicks) }
}

#Preview("crown", traits: .sizeThatFitsLayout) {
    CalibreMark.crown()
        .padding(Space.xl)
        .calibrePageBackground()
}
