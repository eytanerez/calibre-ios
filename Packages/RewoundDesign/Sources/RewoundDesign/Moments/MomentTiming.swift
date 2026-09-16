import CoreGraphics
import Foundation

/// The timing primitives the five moments are written in.
///
/// The approved choreography for all five was authored as CSS keyframes and
/// signed off running in a browser. Porting it faithfully means porting *CSS
/// semantics*, not approximating them: a keyframe list carries stop
/// percentages, and the animation's easing is applied **inside each pair of
/// stops** rather than once across the whole run. A SwiftUI spring, or one
/// curve stretched over the whole duration, would move through different
/// positions at every frame between the stops — which is most of them.
///
/// So a film here is a pure function of elapsed seconds. Nothing about it is
/// stateful, which is also what makes a single frame of one renderable on
/// demand: the debug harness in `MomentHost` freezes a film at a chosen second
/// and gets exactly the frame the browser would have shown at that second.
struct MomentCurve {
    let x1: Double, y1: Double, x2: Double, y2: Double

    /// CSS `linear`.
    static let linear = MomentCurve(x1: 0, y1: 0, x2: 1, y2: 1)
    /// CSS `ease`, the default when a keyframe rule names no function.
    static let ease = MomentCurve(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    /// CSS `ease-out`.
    static let easeOut = MomentCurve(x1: 0, y1: 0, x2: 0.58, y2: 1)

    /// The progress the curve is at, `t` and the result both 0...1.
    ///
    /// A cubic Bézier easing is `y` as a function of `x`, and the curve is
    /// given parametrically, so `x` has to be inverted first. Newton converges
    /// in a handful of steps everywhere these curves are not flat; bisection
    /// catches the flat starts (`x1 == 0`), where the derivative is zero and
    /// Newton would step nowhere.
    func callAsFunction(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        if self == .linear { return clamped }
        return bezier(y1, y2, at: solveForX(clamped))
    }

    private func bezier(_ a: Double, _ b: Double, at t: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * a + 3 * inverse * t * t * b + t * t * t
    }

    private func slope(_ a: Double, _ b: Double, at t: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * a + 6 * inverse * t * (b - a) + 3 * t * t * (1 - b)
    }

    private func solveForX(_ x: Double) -> Double {
        var guess = x
        for _ in 0..<8 {
            let error = bezier(x1, x2, at: guess) - x
            if abs(error) < 1e-6 { return guess }
            let derivative = slope(x1, x2, at: guess)
            if abs(derivative) < 1e-6 { break }
            guess -= error / derivative
        }

        var low = 0.0, high = 1.0, mid = x
        while high - low > 1e-6 {
            mid = (low + high) / 2
            if bezier(x1, x2, at: mid) < x { low = mid } else { high = mid }
        }
        return mid
    }
}

extension MomentCurve: Equatable {}

/// One animated property, as the stop list its CSS keyframe rule carried.
///
/// Stops are `(percent through the run, value)`. Between two stops the curve
/// is applied to the interval, which is what a browser does; outside the run
/// the track holds its first or last value, which is `animation-fill-mode:
/// forwards` on a rule that also has no delay-time value of its own.
struct MomentTrack {
    var stops: [(at: Double, value: Double)]
    var curve: MomentCurve

    init(_ curve: MomentCurve, _ stops: [(at: Double, value: Double)]) {
        self.curve = curve
        self.stops = stops
    }

    func value(at progress: Double) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if progress <= first.at { return first.value }
        if progress >= last.at { return last.value }

        for (start, end) in zip(stops, stops.dropFirst()) where progress <= end.at {
            let span = end.at - start.at
            guard span > 0 else { return end.value }
            let eased = curve((progress - start.at) / span)
            return start.value + (end.value - start.value) * eased
        }
        return last.value
    }
}

/// A rule's own delay and duration, so a track reads in seconds the way the
/// stylesheet did: `MomentClip(delay: 0.78, duration: 0.34)`.
struct MomentClip {
    var delay: TimeInterval
    var duration: TimeInterval

    /// How far through this rule the film is at `time`, 0 before the delay and
    /// 1 once it has run — `forwards`, in every case here.
    func progress(_ time: TimeInterval) -> Double {
        guard duration > 0 else { return time >= delay ? 1 : 0 }
        return min(max((time - delay) / duration, 0), 1)
    }

    var end: TimeInterval { delay + duration }
}

/// Interpolates two points the way a track interpolates one number.
func momentLerp(_ from: Double, _ to: Double, _ amount: Double) -> Double {
    from + (to - from) * amount
}

func momentLerp(_ from: CGFloat, _ to: CGFloat, _ amount: Double) -> CGFloat {
    from + (to - from) * CGFloat(amount)
}
