import SwiftUI

/// Motion for the marks, and for nothing else.
///
/// `Motion` is the interface's rulebook — ease-out only, no springs, no bounce
/// — and it stays exactly that. A mark is not a control. It is an illustration
/// reacting to something that just happened, and an impact with no weight
/// behind it reads as a rendering glitch rather than as a deliberate strike.
/// So the marks get anticipation, acceleration into contact and follow
/// through, and that grammar does not travel past these files: no sheet, no
/// button, no card, no toast, no list transition moves this way.
///
/// The rule that keeps it from turning cheap is that the reaction happens
/// *around* the object, never in it. The stamp stays rigid and the ink splats;
/// the parcel stays square and the world it leaves through does the moving.
/// Squashing the object itself is the thing that reads as a toy.
///
/// See `CALIBRE_BY_HAND_CONTRACTS.md` §1.2 for the carve-out and §5 for the
/// grammar these numbers come from.
enum MarkMotion {
    // MARK: - Curves

    /// Accelerating into contact. Things speed up as they fall.
    static var falling: UnitCurve { .easeIn }
    /// Recovering from it — the brand's own ease-out, so a mark settles the
    /// way the interface around it settles.
    static var settling: UnitCurve {
        .bezier(
            startControlPoint: UnitPoint(x: 0.22, y: 1),
            endControlPoint: UnitPoint(x: 0.36, y: 1)
        )
    }

    /// The same two curves as `Animation`s, for the marks whose motion is a
    /// sequence rather than a set of tracks.
    static func falling(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.42, 0, 1, 1, duration: duration)
    }

    static func settling(_ duration: TimeInterval) -> Animation {
        Motion.ease(duration)
    }

    // MARK: - press · stamp, waxSeal

    /// The beat of wind-up before the strike. Short enough to read as intent
    /// rather than as a stall.
    static let windUp: TimeInterval = 0.074
    /// The strike itself.
    static let strike: TimeInterval = 0.19
    /// Debris thrown off the impact, clearing after it.
    static let debris: TimeInterval = 0.30

    // MARK: - oscillate · balanceWheel

    /// The wheel is brought up to amplitude before it starts beating.
    static let oscillateWindUp: TimeInterval = 0.30
    /// One half-swing. Autoreversed, this is a full beat at 4 Hz.
    static let beat: TimeInterval = 0.125
    /// How far the wheel swings either side of level.
    static var amplitude: Angle { .degrees(26) }

    // MARK: - sweep · loupe

    /// The run in from off to one side.
    static let swoop: TimeInterval = 0.26
    /// Coming to rest over the thing it came for.
    static let settle: TimeInterval = 0.12
    /// The finding coming up under the glass, which is where it stops. There
    /// is no beat for the glass leaving: a loupe that leaves ends on a dot in
    /// a ring, and that is the only frame reduced motion would ever show.
    static let reveal: TimeInterval = 0.14

    // MARK: - wind · crown

    /// One click of the crown.
    static let click: TimeInterval = 0.11
    /// Clicks per wind.
    static let clicks = 4
    /// How far each click turns.
    static var clickTurn: Angle { .degrees(22.5) }
    /// How far past the detent it goes before catching.
    static var clickOvershoot: Angle { .degrees(4) }

    // MARK: - fill · dialArc, powerReserve

    /// The needle's run up to value.
    static let sweepUp: TimeInterval = 0.44
    /// The damped return onto it.
    static let damp: TimeInterval = 0.18
    /// How far past value the needle goes.
    static let needleOvershoot = 0.06

    /// Where the needle swings to before it damps back. It cannot travel past
    /// the end of its own track, so a reading already at the stop just arrives.
    static func gaugePeak(_ value: Double) -> Double {
        min(value + needleOvershoot, 1)
    }

    // MARK: - travel · box

    /// One flap folding.
    static let fold: TimeInterval = 0.15
    /// The second flap waits for the first.
    static let foldStagger: TimeInterval = 0.12
    /// The parcel gathers itself before it goes.
    static let dip: TimeInterval = 0.12
    /// And then it is gone.
    static let whip: TimeInterval = 0.38
}

public extension View {
    /// The jolt a surface takes when a `press` mark lands on it.
    ///
    /// Apply it to the card the stamp or the seal comes down on — never to the
    /// mark. The mark stays rigid and the world reacts; that is the whole
    /// difference between an impact and a bounce. Timed so the surface moves at
    /// the frame the mark reaches it.
    @MainActor
    func markImpact(trigger: AnyHashable) -> some View {
        modifier(MarkImpact(trigger: trigger))
    }
}

struct MarkImpact: ViewModifier {
    private var stillness = MarkStillness()
    let trigger: AnyHashable

    init(trigger: AnyHashable) {
        self.trigger = trigger
    }

    func body(content: Content) -> some View {
        if stillness.isRequested {
            content
        } else {
            KeyframeAnimator(initialValue: 0.0, trigger: trigger) { jolt in
                content.offset(y: jolt)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: MarkMotion.windUp + MarkMotion.strike)
                    LinearKeyframe(2.5, duration: 0.05, timingCurve: MarkMotion.falling)
                    LinearKeyframe(0, duration: 0.2, timingCurve: MarkMotion.settling)
                }
            }
        }
    }
}
