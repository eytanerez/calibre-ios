import SwiftUI

/// A compact verification stamp. It settles where it belongs without moving
/// the page or sending a second, oversized mark across the screen.
///
/// What it presses is the wordmark: a rim, and "ReWatch" across it in the
/// stamp's own ink. The word is the only ReWatch mark there is — no initial,
/// no monogram — so the stamp says whose authentication it was in the same
/// letters as everywhere else.
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
        let landed = stillness.isRequested || arrived
        ZStack {
            Self.rim.stroke(Color.rewatch.primary, style: MarkGrid.style)
                .markCanvas(size)
            WordmarkDie(rect: Self.word, size: size, ink: Color.rewatch.primary)
        }
        .frame(width: size, height: size)
        .scaleEffect(landed ? 1 : 1.08)
        .offset(y: landed ? 0 : -6 * size / MarkGrid.side)
        .opacity(landed ? 1 : 0.3)
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

    /// The rim the word is pressed inside.
    static var rim: Path {
        Path(ellipseIn: CGRect(x: 24, y: 24, width: 72, height: 72))
    }

    /// Where the word sits on the grid: centred in the rim, 56 wide and the
    /// drawing's own proportion tall, which leaves a stroke's width of air
    /// between the word's corners and the rim's inner edge.
    static let word = WordmarkDie.centred(width: 56)
}

/// The wordmark as a die presses it: the word's own outlines (the asset, not a
/// redraw) in one ink, at a rectangle on a mark's 120 grid.
///
/// It is laid at the mark's real size rather than inside `markCanvas`: an
/// image drawn on the grid and then scaled down to a 44-point stamp is
/// rasterized at grid size first and goes soft, where the strokes around it,
/// being paths, do not.
struct WordmarkDie: View {
    /// On the 120 grid.
    let rect: CGRect
    /// The side of the mark it is pressed into.
    let size: CGFloat
    let ink: Color

    var body: some View {
        let scale = size / MarkGrid.side
        WordmarkArt.word
            .resizable()
            .interpolation(.high)
            .foregroundStyle(ink)
            .frame(width: rect.width * scale, height: rect.height * scale)
            .offset(
                x: (rect.midX - MarkGrid.center.x) * scale,
                y: (rect.midY - MarkGrid.center.y) * scale
            )
    }

    /// A word `width` grid units wide, centred on the grid.
    static func centred(width: CGFloat) -> CGRect {
        let height = width / RewatchWordmark.aspectRatio
        return CGRect(
            x: MarkGrid.center.x - width / 2,
            y: MarkGrid.center.y - height / 2,
            width: width,
            height: height
        )
    }
}

extension GraphicsContext {
    /// Presses the word into a mark being drawn in a `Canvas`, at `rect` in
    /// whatever space the context is in (the films scale it to the 120 grid).
    func pressWordmark(in rect: CGRect, ink: Color) {
        var word = resolve(WordmarkArt.word)
        word.shading = .color(ink)
        draw(word, in: rect)
    }
}

#Preview("stamp", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.xl) {
        RewatchMark.stamp()
        RewatchMark.stamp(size: 72)
        RewatchMark.stamp(size: 44)
    }
    .padding(Space.xl)
    .rewatchPageBackground()
}
