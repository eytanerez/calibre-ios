import XCTest

@testable import CalibreDesign

/// The logo turns while a sign-in is in flight, and when the answer lands it
/// comes to rest upright — not wherever its speed happened to run out.
final class LogoTurnTests: XCTestCase {
    private let frame: TimeInterval = 1 / 60

    /// Drive a turn for `seconds` with the request in flight.
    private func turning(_ turn: inout LogoTurn, for seconds: TimeInterval) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            turn.advance(by: frame, turning: true)
            elapsed += frame
        }
    }

    /// Let a turn settle after the answer has landed, returning how long it
    /// took and every velocity it passed through on the way. Gives up well
    /// past the longest run-down the arithmetic allows, so a turn that never
    /// rests fails rather than hangs.
    private func settle(_ turn: inout LogoTurn) -> (seconds: TimeInterval, velocities: [Double]) {
        var elapsed: TimeInterval = 0
        var velocities: [Double] = []
        var lastAngle = turn.angle
        while !turn.isAtRest, elapsed < 10 {
            turn.advance(by: frame, turning: false)
            elapsed += frame
            velocities.append(turn.velocity)
            if turn.isAtRest {
                // Coming to rest folds the turns away to 0. That is honest
                // only if the turn was standing on an upright when it did.
                let upright = (lastAngle / 360).rounded() * 360
                XCTAssertEqual(lastAngle, upright, accuracy: 0.1, "folded away from \(lastAngle)°, not an upright")
            } else {
                XCTAssertGreaterThanOrEqual(turn.angle, lastAngle - 1e-9, "the turn ran backwards")
            }
            XCTAssertLessThanOrEqual(turn.velocity, LogoTurn.cruise + 1e-9, "the turn sped up past cruise")
            XCTAssertGreaterThanOrEqual(turn.velocity, 0, "the turn reversed")
            lastAngle = turn.angle
        }
        return (elapsed, velocities)
    }

    func testAnIdleTurnStandsUprightAndNeedsNoTick() {
        var turn = LogoTurn()
        XCTAssertTrue(turn.isAtRest)
        turn.advance(by: frame, turning: false)
        XCTAssertTrue(turn.isAtRest)
        XCTAssertEqual(turn.angle, 0)
    }

    /// The claim this type exists for. Whenever the answer lands — during
    /// the wind-up, at cruise, deep into a slow round trip — the mark ends
    /// upright, within one more turn plus the run-down.
    func testTheRunDownEndsUprightFromAnyPointOfTheTurn() {
        let longestTail = 360 / LogoTurn.cruise + LogoTurn.runDown
        var roundTrip: TimeInterval = 0.05
        while roundTrip < 7 {
            var turn = LogoTurn()
            turning(&turn, for: roundTrip)
            let (seconds, _) = settle(&turn)
            XCTAssertTrue(turn.isAtRest, "still turning after a \(roundTrip)s round trip")
            XCTAssertEqual(turn.angle, 0, "rested at \(turn.angle)° after a \(roundTrip)s round trip")
            XCTAssertEqual(turn.velocity, 0)
            XCTAssertLessThanOrEqual(seconds, longestTail + 2 * frame, "a \(roundTrip)s round trip took \(seconds)s to rest")
            roundTrip += 0.05
        }
    }

    /// A wrong password comes back in well under half a second, while the
    /// mark is still winding up. That is the failure the user then sits and
    /// looks at.
    func testAWrongPasswordLeavesTheMarkUpright() {
        var turn = LogoTurn()
        turning(&turn, for: 0.4)
        XCTAssertGreaterThan(turn.angle, 0, "the mark had visibly turned")
        _ = settle(&turn)
        XCTAssertEqual(turn.angle, 0)
        XCTAssertTrue(turn.isAtRest)
    }

    /// The run-down is an ease, not a brake: from one frame to the next the
    /// speed never falls by more than the steepest run-down allows.
    func testTheRunDownNeverStopsDead() {
        var turn = LogoTurn()
        turning(&turn, for: 1.2)
        let steepest = 2 * LogoTurn.cruise / LogoTurn.quickestRunDown * frame
        var last = turn.velocity
        let (_, velocities) = settle(&turn)
        for velocity in velocities {
            XCTAssertLessThanOrEqual(last - velocity, steepest + 1e-6)
            last = velocity
        }
    }

    /// An answer that lands before the turn has visibly begun — a request
    /// that fails at once — stops it there rather than winding a whole turn
    /// to bring back a fraction of a degree.
    func testAnAnswerBeforeTheTurnHasBegunStopsItThere() {
        var turn = LogoTurn()
        turn.advance(by: frame, turning: true)
        XCTAssertLessThan(turn.angle, LogoTurn.standingTolerance)
        turn.advance(by: frame, turning: false)
        XCTAssertTrue(turn.isAtRest)
        XCTAssertEqual(turn.angle, 0)
    }

    /// A retry tapped while the mark is still running down picks the turn up
    /// from the speed it had, and the next answer still ends upright.
    func testARetryMidRunDownCarriesOnAndStillEndsUpright() {
        var turn = LogoTurn()
        turning(&turn, for: 1)
        var elapsed: TimeInterval = 0
        while turn.velocity >= LogoTurn.cruise - 1e-9, elapsed < 10 {
            turn.advance(by: frame, turning: false)
            elapsed += frame
        }
        XCTAssertLessThan(turn.velocity, LogoTurn.cruise, "the run-down had begun")
        let before = turn.velocity
        turn.advance(by: frame, turning: true)
        XCTAssertFalse(turn.isAtRest)
        XCTAssertGreaterThan(turn.velocity, before - 1e-9, "the retry restarted the wind-up from rest")
        turning(&turn, for: 0.5)
        _ = settle(&turn)
        XCTAssertEqual(turn.angle, 0)
        XCTAssertTrue(turn.isAtRest)
    }

    /// Reduce Motion arriving mid-turn shows the end state: upright, still.
    func testStoppingForReduceMotionStandsTheMarkUpright() {
        var turn = LogoTurn()
        turning(&turn, for: 0.8)
        XCTAssertNotEqual(turn.angle, 0)
        turn.stop()
        XCTAssertEqual(turn.angle, 0)
        XCTAssertEqual(turn.velocity, 0)
        XCTAssertTrue(turn.isAtRest)
    }
}
