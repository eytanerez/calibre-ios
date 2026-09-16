import CoreGraphics
import Foundation

/// One mark a seller drew on one of their own listing photos, plus the line
/// they wrote about it.
///
/// The coordinates are normalised against the image's intrinsic size rather
/// than stored in pixels: a mark measured on the phone that drew it would land
/// somewhere else on every other viewport, and a line across the wrong part of
/// the watch is worse than no line at all.
public struct ListingAnnotation: Sendable, Identifiable, Equatable {
    /// The coordinate system these numbers are written in. A payload the app
    /// cannot read is refused rather than drawn at a guess.
    public static let schemaVersion = 1
    /// What the server stores and what a renderer can draw smoothly.
    public static let maxPoints = 64
    /// Below this the gesture is a tap, not a mark, and the server says so.
    public static let minPoints = 8
    /// The caption, in the hand.
    public static let noteLimit = 120
    /// Marks per listing. A photo essay is a different feature.
    public static let maxPerListing = 3

    public let v: Int
    /// Which listing photo this sits on, by position.
    public let imageIndex: Int
    /// An open polyline in the unit square, in the order it was drawn.
    public let path: [CGPoint]
    public let note: String?
    public let createdAt: Date?
    public let updatedAt: Date?

    /// Keyed on the photo it marks — one mark per photo, which is also the
    /// server's primary key.
    public var id: Int { imageIndex }

    public init(
        v: Int = ListingAnnotation.schemaVersion,
        imageIndex: Int,
        path: [CGPoint],
        note: String?,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.v = v
        self.imageIndex = imageIndex
        self.path = path
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ListingAnnotation: Codable {
    private enum CodingKeys: String, CodingKey {
        case v, imageIndex, path, note, createdAt, updatedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(v, forKey: .v)
        try container.encode(imageIndex, forKey: .imageIndex)
        try container.encode(path.map { [$0.x, $0.y] }, forKey: .path)
        try container.encodeIfPresent(note, forKey: .note)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = try container.decode(Int.self, forKey: .v)
        imageIndex = try container.decode(Int.self, forKey: .imageIndex)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)

        // A pair that is not a pair is a broken contract, not a point to skip:
        // dropping it would shift every following vertex of the line.
        let pairs = try container.decode([[Double]].self, forKey: .path)
        path = try pairs.map { pair in
            guard pair.count == 2 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .path,
                    in: container,
                    debugDescription: "Every point on an annotation path is an [x, y] pair."
                )
            }
            return CGPoint(x: pair[0], y: pair[1])
        }
    }
}

/// Turning a finger's worth of samples into something worth storing.
public enum AnnotationPath {
    /// Ramer–Douglas–Peucker, run to fit inside the stored cap.
    ///
    /// The gesture is what carries the meaning — a fitted ellipse reads as a
    /// UI affordance, the drawn line reads as a person — so the simplification
    /// keeps the vertices the drawing actually turned on and throws away the
    /// hand's tremor between them. The tolerance is grown rather than chosen
    /// so that a slow careful circle and a fast scribble both land under the
    /// cap without either being resampled into evenness.
    ///
    /// Returns nothing when the gesture was too short to be a mark; the caller
    /// tells the seller rather than uploading something the server refuses.
    public static func simplify(
        _ points: [CGPoint],
        limit: Int = ListingAnnotation.maxPoints,
        minimum: Int = ListingAnnotation.minPoints
    ) -> [CGPoint] {
        let clamped = points.map {
            CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1))
        }
        guard clamped.count >= minimum else { return [] }
        guard clamped.count > limit else { return clamped }

        // A whole unit is the width of the photo, so this starts well below
        // anything an eye would notice and doubles from there.
        var tolerance = 0.001
        var reduced = douglasPeucker(clamped, tolerance: tolerance)
        while reduced.count > limit, tolerance < 1 {
            tolerance *= 2
            reduced = douglasPeucker(clamped, tolerance: tolerance)
        }

        // A path long enough to need cutting can still collapse past the
        // floor — a near-straight drag has almost no vertices to keep. Even
        // spacing along the original is the honest answer there: it is the
        // same line, sampled, rather than a different shape.
        guard reduced.count >= minimum, reduced.count <= limit else {
            return evenlySpaced(clamped, count: limit)
        }
        return reduced
    }

    private static func douglasPeucker(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }

        var farthest = 0
        var maxDistance = 0.0
        for index in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[index], from: first, to: last)
            if distance > maxDistance {
                maxDistance = distance
                farthest = index
            }
        }

        guard maxDistance > tolerance else { return [first, last] }
        let head = douglasPeucker(Array(points[0...farthest]), tolerance: tolerance)
        let tail = douglasPeucker(Array(points[farthest...]), tolerance: tolerance)
        return head.dropLast() + tail
    }

    private static func perpendicularDistance(_ point: CGPoint, from start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let span = (dx * dx + dy * dy).squareRoot()
        // A closed loop hands the recursion a zero-length segment; the
        // distance to it is the distance to the point it collapsed to.
        guard span > 0 else {
            return ((point.x - start.x) * (point.x - start.x) + (point.y - start.y) * (point.y - start.y)).squareRoot()
        }
        return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x) / span
    }

    /// Keeps both ends and spreads the rest evenly by index.
    private static func evenlySpaced(_ points: [CGPoint], count: Int) -> [CGPoint] {
        guard points.count > count, count > 1 else { return points }
        let step = Double(points.count - 1) / Double(count - 1)
        return (0..<count).map { points[Int((Double($0) * step).rounded())] }
    }
}
