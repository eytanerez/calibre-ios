import SwiftUI
import UIKit

/// The grid every mark is drawn on, taken off the logo rather than chosen.
/// A mark is authored at 120 × 120 and the whole drawing is scaled to the size
/// it is asked for, so the stroke stays in proportion at every size and a mark
/// standing next to the logo still matches it.
enum MarkGrid {
    /// The square the geometry is written against.
    static let side: CGFloat = 120
    /// The one stroke weight in the system, measured off the logo's centerline.
    static let stroke: CGFloat = 4.55
    /// Center of the grid.
    static let center = CGPoint(x: 60, y: 60)

    /// Round caps, round joins, single weight — the whole stroke vocabulary.
    static var style: StrokeStyle {
        StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
    }

    /// A lighter weight for the parts of a mark that sit behind the ink: a
    /// gauge track under its needle, a tooth under its rim.
    static var hairline: StrokeStyle {
        StrokeStyle(lineWidth: stroke * 0.62, lineCap: .round, lineJoin: .round)
    }
}

extension View {
    /// Lays out a mark authored on the 120 grid at `size`, stroke and all.
    /// Scaling the drawing rather than re-deriving the numbers is what keeps
    /// §1.1's single stroke weight true at every size.
    func markCanvas(_ size: CGFloat) -> some View {
        frame(width: MarkGrid.side, height: MarkGrid.side)
            .scaleEffect(size / MarkGrid.side)
            .frame(width: size, height: size)
    }
}

extension Path {
    /// Appends an elliptical arc, emitted as cubic Béziers.
    ///
    /// SwiftUI's `Path` draws circular arcs and nothing else — there is no
    /// elliptical form on it, and the logo's arc is an ellipse. So the arc is
    /// built on a unit circle and pushed through the ellipse's own transform,
    /// which lands the drawn centerline on the fitted ellipse rather than near
    /// it. Building the curves by hand also sidesteps the flipped-y reading of
    /// `addArc`'s `clockwise` flag: the direction here is the sign of `delta`.
    mutating func addEllipticalArc(
        center: CGPoint,
        radii: CGSize,
        rotation: Angle,
        start: Angle,
        delta: Angle
    ) {
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation.radians)
            .scaledBy(x: radii.width, y: radii.height)

        // A cubic tracks a circle to well under a tenth of a grid unit while
        // each segment stays inside a quarter turn.
        let segments = max(1, Int((abs(delta.radians) / (.pi / 2)).rounded(.up)))
        let step = delta.radians / Double(segments)
        let handle = 4 / 3 * tan(step / 4)

        func onArc(_ angle: Double) -> CGPoint {
            CGPoint(x: cos(angle), y: sin(angle)).applying(transform)
        }
        func control(_ angle: Double, _ direction: Double) -> CGPoint {
            CGPoint(
                x: cos(angle) - direction * handle * sin(angle),
                y: sin(angle) + direction * handle * cos(angle)
            ).applying(transform)
        }

        let first = onArc(start.radians)
        if isEmpty { move(to: first) } else { addLine(to: first) }

        for segment in 0..<segments {
            let from = start.radians + Double(segment) * step
            let to = from + step
            addCurve(to: onArc(to), control1: control(from, 1), control2: control(to, -1))
        }
    }

    /// The circular case of the above — a gauge track, a crown's rim.
    mutating func addCircularArc(center: CGPoint, radius: CGFloat, start: Angle, delta: Angle) {
        addEllipticalArc(
            center: center,
            radii: CGSize(width: radius, height: radius),
            rotation: .zero,
            start: start,
            delta: delta
        )
    }
}

/// One answer to "should this mark hold still?", read from the SwiftUI
/// environment, from UIKit, and from the surface itself — any one of them
/// saying yes is a yes.
///
/// A still mark renders its **end state**: stamped, sealed, filled. Never a
/// blank frame, and never a frame from the middle of the animation. The point
/// of the mark is what it says once it has arrived; the motion is only how it
/// gets there, and that is the part being declined.
///
/// The third signal is `View.markStill(_:)`, which a surface uses to make a
/// mark stand as a fact this session has already been shown rather than
/// announce it again. It is ORed in rather than consulted instead, so a
/// surface can never overrule somebody's Reduce Motion setting.
struct MarkStillness: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.markStillnessRequested) private var requestedBySurface

    @MainActor
    var isRequested: Bool {
        reduceMotion || requestedBySurface || UIAccessibility.isReduceMotionEnabled
    }
}

/// Radial point on the grid, for ticks, teeth and debris.
func markPoint(_ center: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
    CGPoint(
        x: center.x + radius * cos(angle.radians),
        y: center.y + radius * sin(angle.radians)
    )
}
