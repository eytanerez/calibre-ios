import SwiftUI

/// The fist bump — the one genuinely new drawing in the five moments, and the
/// only one that is not already in the mark vocabulary.
///
/// The path data is the approved drawing's, transcribed point for point from
/// `SHIPPED_fist_bump.svg` rather than traced again here. Three surfaces ship
/// this pair of fists and a second trace is a second, slightly different pair;
/// the coordinates below are the contract between them.
///
/// One outline per fist on a 200 × 140 field: the wrist runs in from the
/// field's own edge, three knuckle arcs scallop the leading edge, two short
/// creases sit in the knuckle valleys and one curve is the thumb. The right
/// fist is the same outline mirrored about the field's centre, which is why
/// there is one path here and not two.
enum FistBumpDrawing {
    /// The field the drawing is authored on.
    static let field = CGSize(width: 200, height: 140)

    /// The left fist: wrist at x = 0, knuckles at x = 90.
    static var fist: Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 58))
            path.addLine(to: CGPoint(x: 34, y: 58))
            path.addCurve(
                to: CGPoint(x: 56, y: 40),
                control1: CGPoint(x: 44, y: 58),
                control2: CGPoint(x: 44, y: 40)
            )
            path.addLine(to: CGPoint(x: 76, y: 40))
            path.addCurve(
                to: CGPoint(x: 90, y: 52),
                control1: CGPoint(x: 84, y: 40),
                control2: CGPoint(x: 90, y: 45)
            )
            // The three knuckles. Each is a half-circle of radius 7 bulging
            // forward off a chord of exactly its own diameter — which is what
            // the SVG's `A 7 7 0 0 1` arcs are, written in the form this
            // codebase's arc helper takes.
            for knuckle in 0..<3 {
                path.addCircularArc(
                    centre: CGPoint(x: 90, y: 59 + 14 * CGFloat(knuckle)),
                    radius: 7,
                    start: .degrees(-90),
                    delta: .degrees(180)
                )
            }
            path.addCurve(
                to: CGPoint(x: 76, y: 100),
                control1: CGPoint(x: 90, y: 99),
                control2: CGPoint(x: 84, y: 100)
            )
            path.addLine(to: CGPoint(x: 56, y: 100))
            path.addCurve(
                to: CGPoint(x: 34, y: 82),
                control1: CGPoint(x: 44, y: 100),
                control2: CGPoint(x: 44, y: 82)
            )
            path.addLine(to: CGPoint(x: 0, y: 82))
        }
    }

    /// The two short creases in the knuckle valleys and the thumb curve.
    static var creases: Path {
        Path { path in
            path.move(to: CGPoint(x: 72, y: 66))
            path.addLine(to: CGPoint(x: 86, y: 66))
            path.move(to: CGPoint(x: 72, y: 80))
            path.addLine(to: CGPoint(x: 86, y: 80))
            path.move(to: CGPoint(x: 50, y: 86))
            path.addCurve(
                to: CGPoint(x: 74, y: 88),
                control1: CGPoint(x: 58, y: 93),
                control2: CGPoint(x: 68, y: 93)
            )
        }
    }

    /// Mirrors the left fist onto the right of the field.
    static let mirror = CGAffineTransform(translationX: field.width, y: 0)
        .scaledBy(x: -1, y: 1)

    /// The impact, thrown off the seam where the two meet. Six short lines,
    /// and they are struck at a lighter weight than the fists so the contact
    /// reads as force rather than as a third drawing arriving.
    static var ticks: Path {
        Path { path in
            let strokes: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 100, y: 34), CGPoint(x: 100, y: 24)),
                (CGPoint(x: 100, y: 106), CGPoint(x: 100, y: 116)),
                (CGPoint(x: 112, y: 44), CGPoint(x: 119, y: 36)),
                (CGPoint(x: 112, y: 96), CGPoint(x: 119, y: 104)),
                (CGPoint(x: 88, y: 44), CGPoint(x: 81, y: 36)),
                (CGPoint(x: 88, y: 96), CGPoint(x: 81, y: 104)),
            ]
            for (from, to) in strokes {
                path.move(to: from)
                path.addLine(to: to)
            }
        }
    }

    /// The tick weight, as the reference struck it.
    static let tickStroke: CGFloat = 4.2
}
