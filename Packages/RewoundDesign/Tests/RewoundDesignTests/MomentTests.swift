import CoreGraphics
import XCTest
@testable import RewoundDesign

/// The five moments were approved running in a browser, as CSS keyframes. What
/// is portable about that is arithmetic — where a curve is at a given fraction,
/// and where a stop list is between its stops — so that is what is pinned here.
/// A film that drifts off the approved choreography drifts through these first.
final class MomentTests: XCTestCase {
    // MARK: - The easing

    /// The curve has to be `y` as a function of `x`, not of the Bézier's own
    /// parameter. The two agree only at the ends, and every stop in every film
    /// sits between them: reading the parameter instead lands a curve like
    /// `ease` a fifth of its travel out at the halfway mark.
    func testTheCurvesMatchTheBrowsersAtTheirHalfway() {
        XCTAssertEqual(MomentCurve.ease(0.5), 0.8024, accuracy: 0.001)
        XCTAssertEqual(MomentCurve.easeOut(0.5), 0.6846, accuracy: 0.001)
        XCTAssertEqual(MomentCurve.easeOut(0.25), 0.3781, accuracy: 0.001)
        // The order film's fall, which is the flattest start in the set — the
        // one a parameter-space reading would flatter most.
        let fall = MomentCurve(x1: 0.45, y1: 0, x2: 0.8, y2: 0.25)
        XCTAssertEqual(fall(0.5), 0.1436, accuracy: 0.001)
    }

    /// A flat start is where Newton's method stalls, because the derivative
    /// there is zero. Every curve in the set has one.
    func testACurveWithAFlatStartStillSolves() {
        let flat = MomentCurve(x1: 0, y1: 0, x2: 0.58, y2: 1)
        for step in 0...20 {
            let t = Double(step) / 20
            let value = flat(t)
            XCTAssertFalse(value.isNaN, "the solver gave up at \(t)")
            XCTAssertGreaterThanOrEqual(value, -0.001)
            XCTAssertLessThanOrEqual(value, 1.001)
        }
        XCTAssertEqual(flat(0), 0, accuracy: 0.0001)
        XCTAssertEqual(flat(1), 1, accuracy: 0.0001)
    }

    // MARK: - The stop lists

    /// A browser applies the animation's easing **inside each pair of
    /// keyframes**, not once across the whole run. Every film here is a stop
    /// list, so getting this backwards would move every one of them through
    /// different positions at every frame between its stops.
    ///
    /// The test: a two-segment track has to be exactly on its middle stop at
    /// that stop's own fraction. Stretched across the run it would not be.
    func testEachSegmentGetsItsOwnEasing() {
        let steep = MomentCurve(x1: 0.9, y1: 0, x2: 1, y2: 0.1)
        let track = MomentTrack(steep, [
            (at: 0, value: 0), (at: 0.25, value: 100), (at: 1, value: 200),
        ])
        XCTAssertEqual(track.value(at: 0.25), 100, accuracy: 0.0001)
        // Half way through the first segment the steep curve has barely left
        // the first stop — a curve stretched over the run would be far ahead.
        XCTAssertLessThan(track.value(at: 0.125), 20)
        // And half way through the second it is still low against that stop's
        // own span, for the same reason.
        XCTAssertLessThan(track.value(at: 0.625), 120)
    }

    /// Every rule in the set is `forwards` and none rewinds: before a track
    /// starts it holds its first value, and after it ends it holds its last.
    func testATrackHoldsItsEndsRatherThanRunningPast() {
        let track = MomentTrack(.linear, [(at: 0.2, value: 5), (at: 0.8, value: 9)])
        XCTAssertEqual(track.value(at: 0), 5)
        XCTAssertEqual(track.value(at: -3), 5)
        XCTAssertEqual(track.value(at: 0.5), 7, accuracy: 0.0001)
        XCTAssertEqual(track.value(at: 1), 9)
        XCTAssertEqual(track.value(at: 40), 9)
    }

    func testAClipIsDormantBeforeItsDelayAndFinishedAfterIt() {
        let clip = MomentClip(delay: 0.78, duration: 0.34)
        XCTAssertEqual(clip.progress(0), 0)
        XCTAssertEqual(clip.progress(0.78), 0)
        XCTAssertEqual(clip.progress(0.95), 0.5, accuracy: 0.0001)
        XCTAssertEqual(clip.progress(1.12), 1)
        XCTAssertEqual(clip.progress(9), 1)
        XCTAssertEqual(clip.end, 1.12, accuracy: 0.0001)
    }

    // MARK: - The films

    /// A film is taken off screen when its clock runs out, so a duration
    /// shorter than the last beat cuts that beat off mid-air. These are the
    /// approved run lengths.
    func testEachFilmRunsAsLongAsItWasApproved() {
        XCTAssertEqual(RewoundMoment.orderPlaced.duration, 2.45, accuracy: 0.0001)
        XCTAssertEqual(RewoundMoment.listingSubmitted.duration, 2.4, accuracy: 0.0001)
        XCTAssertEqual(RewoundMoment.reportOpened.duration, 2.55, accuracy: 0.0001)
        XCTAssertEqual(RewoundMoment.vaultWatchOpened.duration, 1.12, accuracy: 0.0001)
        XCTAssertEqual(RewoundMoment.offerAccepted.duration, 2.08, accuracy: 0.0001)
    }

    /// Only the two films that swallow the screen you were on ask for a
    /// picture of it. Asking for one anywhere else costs a full-screen render
    /// on the main thread for an image nothing draws.
    func testOnlyTheFilmsThatSwallowAScreenAskForOne() {
        for moment in RewoundMoment.allCases {
            let swallows = moment == .orderPlaced || moment == .listingSubmitted
            XCTAssertEqual(moment.collapsesTheOutgoingScreen, swallows, "\(moment.rawValue)")
        }
    }

    /// The report ends as the whole screen and starts as a crop of its own top
    /// inside the envelope, and the two have to be the same page: same width
    /// scale as the window it shows through, same left edge, and no corner left
    /// rounded once it is the screen.
    func testTheReportEndsAsTheWholeScreen() {
        let stage = CGSize(width: 393, height: 759)
        let opening = ReportOpenedFilm.contentEffect(at: 0.9, stage: stage)
        let landed = ReportOpenedFilm.contentEffect(at: RewoundMoment.reportOpened.duration, stage: stage)

        let crop = try? XCTUnwrap(opening.window)
        XCTAssertNotNil(crop)
        if let crop {
            XCTAssertLessThan(crop.width, stage.width, "inside the envelope it is a crop")
            XCTAssertEqual(opening.scale, Double(crop.width / stage.width), accuracy: 0.0001)
            XCTAssertGreaterThan(opening.windowCorner, 0)
        }

        XCTAssertEqual(landed.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(landed.window?.width, stage.width)
        XCTAssertEqual(landed.window?.height, stage.height)
        XCTAssertEqual(landed.window?.minY, 0)
        XCTAssertEqual(landed.offset.height, 0, accuracy: 0.0001)
        XCTAssertEqual(landed.windowCorner, 0, accuracy: 0.0001)
    }

    /// §12.9 — *"the collapse goes into the box."*
    ///
    /// The landing is the whole of that ruling, and it is one number: where
    /// the shrinking page's top edge finishes. On the mouth, everything of the
    /// page is under the flaps and behind the carton's opaque front panel.
    /// Short of it, the page ends its fall sitting in front of the carton and
    /// fades out there, which is the version that was rejected. Past it, the
    /// page has gone through the mouth into the wall.
    ///
    /// The anchored shrink this replaced is not a different number at the
    /// start — both leave the top edge at zero — so a test that only reads t=0
    /// passes on the rejected film. The end is where the two part.
    func testTheOrderPageFallsOntoTheBoxsMouth() {
        let stage = CGSize(width: 402, height: 874)
        let box = OrderPlacedFilm.Carton(stage)
        XCTAssertGreaterThan(box.mouthY, 0, "a mouth at the origin would make every assertion below vacuous")

        XCTAssertEqual(OrderPlacedFilm.pageTop(box, at: 0), 0, accuracy: 0.001, "at rest the page is the screen")
        XCTAssertEqual(
            OrderPlacedFilm.pageTop(box, at: 1),
            box.mouthY,
            accuracy: 0.001,
            "the fall ends with the page's top edge on the mouth"
        )

        // Everywhere in between it is descending towards the mouth and has not
        // reached it — a page that arrives early is resting on an open box for
        // the rest of the fall, and one that goes past is inside the wall.
        var previous = OrderPlacedFilm.pageTop(box, at: 0)
        for step in 1..<20 {
            let progress = Double(step) / 20
            let top = OrderPlacedFilm.pageTop(box, at: progress)
            XCTAssertGreaterThan(top, previous, "the page stalled at \(progress)")
            XCTAssertLessThan(top, box.mouthY, "the page reached the mouth early, at \(progress)")
            previous = top
        }
    }

    /// The offset that carries it there, read the way SwiftUI reads it: a
    /// center-anchored `scaleEffect` has already moved the page half of what
    /// it shrank by, and the offset makes up the rest.
    func testTheOrderPagesOffsetPutsItsTopEdgeWhereItBelongs() {
        let stage = CGSize(width: 402, height: 874)
        let box = OrderPlacedFilm.Carton(stage)

        for step in 0...10 {
            let progress = Double(step) / 10
            let scale = OrderPlacedFilm.pageScale.value(at: progress)
            let drawnTop = stage.height * CGFloat(1 - scale) / 2
                + OrderPlacedFilm.drop(box, at: progress, stage: stage)
            XCTAssertEqual(
                drawnTop,
                OrderPlacedFilm.pageTop(box, at: progress),
                accuracy: 0.001,
                "at \(progress)"
            )
        }
    }

    /// The page is clipped along the carton's own floor from the moment it is
    /// small enough to be inside it. Without that a full-screen page trails a
    /// tail below the box, where there is no opaque panel to hide it — the one
    /// thing a whole screen does that the reference's small card never did.
    func testTheOrderPageIsCutOffAtTheCartonsFloor() {
        let stage = CGSize(width: 402, height: 874)
        let box = OrderPlacedFilm.Carton(stage)
        XCTAssertGreaterThan(box.floorY, box.mouthY, "the floor is below the mouth")

        XCTAssertEqual(
            OrderPlacedFilm.swallowed(box, at: 0, stage: stage).maxY,
            stage.height,
            accuracy: 0.001,
            "before it falls the page is the whole screen and nothing is cut"
        )
        XCTAssertEqual(
            OrderPlacedFilm.swallowed(box, at: 1, stage: stage).maxY,
            box.floorY,
            accuracy: 0.001
        )
        XCTAssertEqual(OrderPlacedFilm.swallowed(box, at: 1, stage: stage).width, stage.width)
    }

    /// Checkout starts a whole screen below the edge and arrives flush.
    func testCheckoutRisesFromBelowTheEdgeOntoIt() {
        let stage = CGSize(width: 393, height: 759)
        let waiting = OfferAcceptedFilm.contentEffect(at: 0, stage: stage)
        XCTAssertGreaterThanOrEqual(waiting.offset.height, stage.height)

        let arrived = OfferAcceptedFilm.contentEffect(at: RewoundMoment.offerAccepted.duration, stage: stage)
        XCTAssertEqual(arrived.offset.height, 0, accuracy: 0.0001)
    }

    /// The card takes the hit and comes back to where it was. A jolt that does
    /// not return leaves the screen sitting off its own edge.
    func testTheVaultJoltReturnsToRest() {
        let stage = CGSize(width: 393, height: 759)
        let atRest = VaultStampFilm.contentEffect(at: 0, stage: stage)
        XCTAssertEqual(atRest.offset.height, 0, accuracy: 0.0001)
        XCTAssertEqual(atRest.scale, 1, accuracy: 0.0001)

        let struck = VaultStampFilm.contentEffect(at: 0.71, stage: stage)
        XCTAssertGreaterThan(struck.offset.height, 0, "the screen gives under the stamp")

        let settled = VaultStampFilm.contentEffect(at: RewoundMoment.vaultWatchOpened.duration, stage: stage)
        XCTAssertEqual(settled.offset.height, 0, accuracy: 0.0001)
        XCTAssertEqual(settled.scale, 1, accuracy: 0.0001)
    }

    // MARK: - The one new drawing

    /// The fist bump is the only drawing in the set that is not already in the
    /// mark vocabulary, and three surfaces ship it. These are the shipped
    /// artwork's own extents: the wrist runs in from the field's edge and the
    /// knuckles scallop a radius past the leading edge.
    func testTheFistIsTheShippedDrawing() {
        let outline = FistBumpDrawing.fist.boundingRect
        XCTAssertEqual(outline.minX, 0, accuracy: 0.01, "the wrist starts at the field's edge")
        XCTAssertEqual(outline.maxX, 97, accuracy: 0.2, "the knuckles bulge a radius past the leading edge")
        XCTAssertEqual(outline.minY, 40, accuracy: 0.01)
        XCTAssertEqual(outline.maxY, 100, accuracy: 0.01)

        // Mirrored, it is the same hand on the other side of the field, so the
        // two meet on the centerline rather than overlapping or missing.
        let mirrored = FistBumpDrawing.fist.applying(FistBumpDrawing.mirror).boundingRect
        XCTAssertEqual(mirrored.maxX, FistBumpDrawing.field.width, accuracy: 0.01)
        XCTAssertEqual(mirrored.minX, FistBumpDrawing.field.width - outline.maxX, accuracy: 0.2)
        XCTAssertEqual(mirrored.minY, outline.minY, accuracy: 0.01)
        XCTAssertEqual(mirrored.maxY, outline.maxY, accuracy: 0.01)

        // The creases sit inside the fist they belong to.
        XCTAssertTrue(outline.insetBy(dx: -1, dy: -1).contains(FistBumpDrawing.creases.boundingRect))
    }

    /// The impact is thrown off the seam the two fists meet on, and it clears
    /// them: a tick drawn inside a fist reads as a crease rather than a strike.
    func testTheImpactIsThrownOffTheSeam() {
        let struck = FistBumpDrawing.ticks.boundingRect
        XCTAssertEqual(struck.midX, FistBumpDrawing.field.width / 2, accuracy: 0.01)
        XCTAssertEqual(struck.midY, FistBumpDrawing.field.height / 2, accuracy: 1)
        XCTAssertLessThan(struck.minY, FistBumpDrawing.fist.boundingRect.minY)
        XCTAssertGreaterThan(struck.maxY, FistBumpDrawing.fist.boundingRect.maxY)
        XCTAssertLessThan(FistBumpDrawing.tickStroke, MarkGrid.stroke)
    }
}
