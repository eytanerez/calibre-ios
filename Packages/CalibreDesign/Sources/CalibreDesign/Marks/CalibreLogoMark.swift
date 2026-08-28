import SwiftUI

/// The Calibre mark itself, as geometry.
///
/// Not one of the vocabulary marks and not a ninth one — this is the logo, and
/// it is here because it is where the vocabulary's grid, stroke weight and cap
/// style are all measured from. `CalibreWordmark` is the word set in Playfair;
/// this is the drawing.
///
/// The paths are the traced original, ported and not re-drawn: the ellipse was
/// fitted to the drawn centreline rather than eyeballed, and re-tracing it here
/// would put a second, slightly different mark into the world.
public struct CalibreLogoMark: View {
    let size: CGFloat

    public init(size: CGFloat = CalibreMark.defaultSize) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Self.strokes.stroke(Color.calibre.primary, style: MarkGrid.style)
            Self.jewelCentre.fill(Color.calibre.primary)
        }
        .markCanvas(size)
        .accessibilityHidden(true)
    }

    /// Everything but the jewel's filled centre.
    ///
    /// Source, on the `0 0 120 120` viewBox:
    ///
    ///     arc          M 94.52 85.34 A 43.36 42.55 -98.29 1 1 94.67 31.55
    ///     bridge upper M 50.57 19.9  C 45.51 28.12 51.52 42.06 56.2 46.26
    ///     bridge lower M 56.36 70.82 C 52.15 75.01 45.65 88.14 50.29 96.17
    ///     jewel ring   circle cx 60.48 cy 58.52 r 10.71
    ///
    /// The arc's centre form below is that endpoint arc converted, not a new
    /// fit: it round-trips onto 94.52 85.34 and 94.67 31.55 exactly, and the
    /// centre it derives lands within a grid unit of the jewel's. The semi-axes
    /// are about two percent apart, so the arc leaves a same-centre circle by
    /// roughly a tenth of a stroke width — small, but it is the fitted shape,
    /// and drawing the circle instead would be re-tracing the mark by eye.
    static var strokes: Path {
        var path = Path()

        path.addEllipticalArc(
            centre: CGPoint(x: 61.2149, y: 58.1656),
            radii: CGSize(width: 43.36, height: 42.55),
            rotation: .degrees(-98.29),
            start: .degrees(136.9632),
            delta: .degrees(283.29)
        )

        path.move(to: CGPoint(x: 50.57, y: 19.9))
        path.addCurve(
            to: CGPoint(x: 56.2, y: 46.26),
            control1: CGPoint(x: 45.51, y: 28.12),
            control2: CGPoint(x: 51.52, y: 42.06)
        )

        path.move(to: CGPoint(x: 56.36, y: 70.82))
        path.addCurve(
            to: CGPoint(x: 50.29, y: 96.17),
            control1: CGPoint(x: 52.15, y: 75.01),
            control2: CGPoint(x: 45.65, y: 88.14)
        )

        path.addEllipse(in: CGRect(
            x: 60.48 - 10.71, y: 58.52 - 10.71,
            width: 10.71 * 2, height: 10.71 * 2
        ))

        return path
    }

    /// `circle cx 60.48 cy 58.52 r 4.88`, filled — the only fill in the logo.
    static var jewelCentre: Path {
        Path(ellipseIn: CGRect(
            x: 60.48 - 4.88, y: 58.52 - 4.88,
            width: 4.88 * 2, height: 4.88 * 2
        ))
    }
}

#Preview("Logo mark", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.xl) {
        CalibreLogoMark(size: 120)
        CalibreLogoMark(size: 56)
        CalibreLogoMark(size: 24)
    }
    .padding(Space.xl)
    .calibrePageBackground()
}
