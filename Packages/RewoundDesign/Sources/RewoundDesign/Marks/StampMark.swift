import SwiftUI

/// A compact verification stamp. It settles where it belongs without moving
/// the page or sending a second, oversized mark across the screen.
struct StampMark: View {
    private var stillness = MarkStillness()
    @State private var arrived = false
    let size: CGFloat
    let trigger: AnyHashable

    init(size: CGFloat, trigger: AnyHashable) {
        self.size = size
        self.trigger = trigger
    }

    var body: some View {
        ZStack {
            Self.head.stroke(Color.rewound.primary, style: MarkGrid.style)
            RewoundLogoMark.jewelCentre.applying(Self.die).fill(Color.rewound.primary)
        }
        .scaleEffect(stillness.isRequested || arrived ? 1 : 1.08)
        .offset(y: stillness.isRequested || arrived ? 0 : -6)
        .opacity(stillness.isRequested || arrived ? 1 : 0.3)
        .markCanvas(size)
        .accessibilityHidden(true)
        .task(id: trigger) {
            guard !stillness.isRequested else { arrived = true; return }
            var reset = Transaction(animation: nil)
            reset.disablesAnimations = true
            withTransaction(reset) { arrived = false }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(Motion.ease(0.22)) { arrived = true }
        }
    }

    /// Rim, and the mark itself cut into it.
    static var head: Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 24, y: 24, width: 72, height: 72))
        path.addPath(RewoundLogoMark.strokes, transform: die)
        return path
    }

    /// The logo shrunk about its own jewel until it sits inside the rim. The
    /// paths come from `RewoundLogoMark` rather than being drawn again at this
    /// size — a second trace is a second, slightly different mark.
    ///
    /// Transforming the path leaves the stroke alone, so the weight stays the
    /// system's rather than shrinking with the drawing.
    static let die = CGAffineTransform(translationX: 60, y: 60)
        .scaledBy(x: 0.58, y: 0.58)
        .translatedBy(x: -60.48, y: -58.52)


}

#Preview("stamp", traits: .sizeThatFitsLayout) {
    RewoundMark.stamp()
        .padding(Space.xl)
        .rewoundPageBackground()
}
