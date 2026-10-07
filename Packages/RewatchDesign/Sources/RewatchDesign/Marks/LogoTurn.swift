import Foundation

/// The arithmetic of the logo's turn while a request is in flight: it winds
/// up to a slow cruise, holds there, and once the answer lands runs down onto
/// an upright rest — never onto whatever angle it happened to reach.
///
/// Pure state, ticked by `advance(by:turning:)` from a clock loop the view
/// owns. It is out here rather than inside that view so the one thing that
/// matters about the run-down — that it ends upright — is a thing a test can
/// hold. The logo is oriented (the C-arc opens right, the bridges sit top and
/// bottom), so a mark left standing at fifty degrees over the wordmark reads
/// as wrong, not as motion, and a failed sign-in leaves the screen up.
///
/// The run-down is where the arithmetic earns its keep. The turn cannot stop
/// dead, cannot reverse, and reads wrong if it speeds up after the answer has
/// landed; so the only way onto an upright is to carry on at pace to the last
/// upright the turn can still ease onto, and run down there. That can cost up
/// to one more turn — and a turn is the pace the mark had already set.
public struct LogoTurn: Equatable, Sendable {
    /// Degrees clockwise from upright.
    public private(set) var angle: Double = 0
    /// Degrees per second.
    public private(set) var velocity: Double = 0
    /// True when the mark stands upright and still, and nothing needs a tick.
    public private(set) var isAtRest = true

    /// One turn every three seconds — slow enough to read as patience.
    public static let cruise: Double = 120
    /// The run up to cruising speed.
    public static let windUp: TimeInterval = 0.45
    /// The run down from cruise onto rest.
    public static let runDown: TimeInterval = 0.6
    /// The shortest run-down the turn will accept. An upright closer than
    /// that run-down's travel is passed for the next one, rather than braked
    /// onto.
    static let quickestRunDown: TimeInterval = 0.3

    /// An answer that lands before the turn has visibly begun stops it where
    /// it is: within this of upright, moving at under a degree a frame, there
    /// is no motion anyone can see end.
    static let standingTolerance: Double = 1
    static let standingVelocity: Double = 60

    /// Seconds into the wind-up curve. Authoritative for `velocity` whenever
    /// the turn is not in its run-down.
    private var windUpElapsed: TimeInterval = 0
    private var landing: Landing?

    /// The run-down, as a curve in position: `travel` degrees over `duration`
    /// on a cubic ease-out, whose velocity is the same quadratic decay the
    /// turn always ran down on — and which lands exactly, where an integrated
    /// velocity would land somewhere near.
    private struct Landing: Equatable {
        var start: Double
        var travel: Double
        var duration: TimeInterval
        var elapsed: TimeInterval = 0
    }

    public init() {}

    /// Move the turn on by `dt` seconds. `turning` is whether the request is
    /// still in flight.
    public mutating func advance(by dt: TimeInterval, turning: Bool) {
        if turning {
            if landing != nil || isAtRest {
                // Picking the wind-up back up from the speed the run-down
                // had got to, not from rest: a retry mid run-down carries on
                // rather than jolting.
                windUpElapsed = Self.windUpTime(at: velocity)
                landing = nil
            }
            isAtRest = false
            wind(by: dt)
            return
        }

        if var landing {
            landing.elapsed += dt
            let progress = min(landing.elapsed / landing.duration, 1)
            angle = landing.start + landing.travel * (1 - pow(1 - progress, 3))
            velocity = 3 * landing.travel / landing.duration * pow(1 - progress, 2)
            if progress >= 1 {
                rest()
            } else {
                self.landing = landing
            }
            return
        }

        if isAtRest { return }

        let nearest = (angle / 360).rounded() * 360
        if abs(angle - nearest) < Self.standingTolerance, velocity <= Self.standingVelocity {
            rest()
            return
        }

        // The answer has landed, and the turn goes on — up to cruise if it
        // was not there yet, so a run-down that comes early is not a crawl —
        // until the next upright is within a run-down's reach.
        wind(by: dt)
        let upright = (angle / 360).rounded(.down) * 360 + 360
        let remaining = upright - angle
        let longest = velocity * Self.runDown / 3
        let shortest = velocity * Self.quickestRunDown / 3
        if remaining <= longest, remaining >= shortest {
            landing = Landing(start: angle, travel: remaining, duration: 3 * remaining / velocity)
        }
    }

    /// Stand the mark upright and still, now. Reduce Motion's frame is the
    /// end state, never a mid one.
    public mutating func stop() {
        rest()
    }

    private mutating func rest() {
        angle = 0
        velocity = 0
        windUpElapsed = 0
        landing = nil
        isAtRest = true
    }

    /// Ease in to cruise and hold there: the turn starts from rest, not at
    /// speed.
    private mutating func wind(by dt: TimeInterval) {
        windUpElapsed += dt
        velocity = Self.windUpVelocity(at: windUpElapsed)
        angle += velocity * dt
    }

    private static func windUpVelocity(at elapsed: TimeInterval) -> Double {
        let progress = min(max(elapsed / windUp, 0), 1)
        return cruise * (1 - pow(1 - progress, 3))
    }

    /// The wind-up curve, inverted: how far along it a given speed sits.
    private static func windUpTime(at velocity: Double) -> TimeInterval {
        let share = min(max(velocity / cruise, 0), 1)
        return (1 - cbrt(1 - share)) * windUp
    }
}
