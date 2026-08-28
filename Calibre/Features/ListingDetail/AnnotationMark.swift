import CalibreDesign
import CalibreKit
import Nuke
import NukeUI
import SwiftUI

/// A seller's mark on a listing photo, drawn where they drew it.
///
/// The coordinates arrive normalised against the photograph's intrinsic size,
/// so the only job here is to put them back onto whatever rectangle the photo
/// is currently occupying. The gallery aspect-*fills* a square and crops the
/// overflow, which means the visible photo is not the whole photo — laying the
/// mark over the square would slide it off the part of the watch it was drawn
/// on. So the overlay reproduces the same fill box and lets the same clip trim
/// both together.
struct AnnotationOverlay: View {
    let annotation: ListingAnnotation
    let imageURL: URL?

    var body: some View {
        LazyImage(request: imageURL.map { ImageRequest(url: $0) }) { state in
            // Nothing is drawn until the photograph's own proportions are
            // known. A mark placed against a guessed aspect ratio is a mark
            // pointing at the wrong part of the watch, which is the one
            // failure worse than no mark at all.
            if let size = state.imageContainer?.image.size, size.width > 0, size.height > 0 {
                Color.clear
                    .aspectRatio(size.width / size.height, contentMode: .fill)
                    .overlay { AnnotationInk(points: annotation.path) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The drawn line itself, in the box the photograph occupies.
///
/// Two passes: the seller's ink, and a soft halo under it. Watch photography
/// is high-contrast by trade — a dark bezel against a white sweep — and a
/// single-colour line disappears into one or the other somewhere along its
/// length. The halo is what keeps it readable without tinting the photograph.
struct AnnotationInk: View {
    let points: [CGPoint]

    var body: some View {
        GeometryReader { geometry in
            let path = AnnotationStroke(points: points).path(in: CGRect(origin: .zero, size: geometry.size))
            let weight = strokeWidth(in: geometry.size)
            path.stroke(
                Color.black.opacity(0.25),
                style: StrokeStyle(lineWidth: weight * 2.1, lineCap: .round, lineJoin: .round)
            )
            .blur(radius: weight * 0.7)

            path.stroke(
                Color.calibre.primaryForeground,
                style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// The pen, measured against the photograph rather than the screen.
    ///
    /// The vocabulary's own weight does not survive contact with a picture.
    /// §3 states it as 4.55 on a 120 grid — near four percent of the grid
    /// edge — which is right for a mark that fills its own square and absurd
    /// across a photograph: it draws a marker stroke wide enough to hide the
    /// hairline it is pointing at. So the annotation gets its own figure, and
    /// it is the same figure on all three clients.
    ///
    /// Against the image's short edge, so it is resolution-independent and a
    /// mark drawn on a phone lands at the same weight on a desktop gallery.
    private func strokeWidth(in size: CGSize) -> CGFloat {
        min(size.width, size.height) * Self.weightAgainstShortEdge
    }

    /// Matched to the web renderer so the three platforms draw one pen.
    private static let weightAgainstShortEdge: CGFloat = 0.008
}

/// The drawn polyline, smoothed.
///
/// Smoothed rather than fitted. A fitted ellipse reads as a UI affordance —
/// the interface pointing at something — and the whole point of this mark is
/// that a person drew it. Catmull-Rom through the seller's own vertices keeps
/// the shape they made and only takes the corners off the sampling.
struct AnnotationStroke: Shape {
    /// Normalised 0..1 against the photograph, in the order they were drawn.
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let placed = points.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        var path = Path()
        guard let first = placed.first else { return path }
        path.move(to: first)
        guard placed.count > 2 else {
            for point in placed.dropFirst() { path.addLine(to: point) }
            return path
        }

        // Catmull-Rom to cubic Bézier. The ends are duplicated so the curve
        // starts and stops exactly where the finger did rather than being
        // pulled short of it.
        for index in 0..<(placed.count - 1) {
            let p0 = placed[max(index - 1, 0)]
            let p1 = placed[index]
            let p2 = placed[index + 1]
            let p3 = placed[min(index + 2, placed.count - 1)]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        return path
    }
}

/// What the seller wrote about the mark, under the photograph.
///
/// Under it rather than over it: the hand has to clear its contrast minimum
/// against a surface, and a photograph is not a surface — it is whatever the
/// watch happened to be shot against. Set over the picture the same sentence
/// is legible on one listing and gone on the next.
struct AnnotationCaption: View {
    let note: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: "hand.draw")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
                .accessibilityHidden(true)
            Text(note)
                .font(CalibreType.handSmall)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("The seller marked this photo: \(note)")
    }
}
