import CoreText
import SwiftUI
import UIKit
import XCTest

@testable import CalibreDesign

final class DesignSystemContractTests: XCTestCase {
    func testSpacingAndRadiusScalesStayOrdered() {
        XCTAssertLessThan(Space.xs, Space.s)
        XCTAssertLessThan(Space.s, Space.m)
        XCTAssertLessThan(Space.m, Space.l)
        XCTAssertLessThan(Space.l, Space.xl)
        XCTAssertLessThan(Space.xl, Space.xxl)

        XCTAssertGreaterThanOrEqual(Space.touchTarget, 44)
    }

    /// The ladder used to be three rungs assigned by component *type* —
    /// control 8, card 12, overlay 16 — and it was the reason the product read
    /// boxy at the corners: a 350pt panel and a 60pt chip were drawn at the
    /// same 12, so the big one looked square. It is now five rungs assigned by
    /// the *size* of the surface (CALIBRE_FINAL_PUSH_CONTRACTS.md §1), and the
    /// two names that survived changed meaning: `card` is the 20pt top of the
    /// ladder rather than the 12pt middle, and the 16pt tier is `panel`.
    ///
    /// The three small rungs then moved up again — chip 6→8, control 8→12,
    /// box 12→14 — after the round-2 review looked at the shipped result:
    /// once the cards were round, buttons and text fields were the squarest
    /// thing left on the screen, and `control` is the token every one of them
    /// takes. `panel` and `card` did not move, so the ladder still climbs with
    /// surface size; it just starts higher. These are the same five numbers
    /// the site's `--radius-*` tokens carry, which is the whole point of
    /// pinning them here: a silent drift between the two is invisible in
    /// either codebase alone.
    ///
    /// The numbers are pinned, not just their order. Ordering alone passed for
    /// the old ladder too, and passes for both of these, so it could not have
    /// caught either move.
    func testTheRadiusLadderIsFiveTiersSortedBySurfaceSize() {
        XCTAssertEqual(Radius.chip, 8)
        XCTAssertEqual(Radius.control, 12)
        XCTAssertEqual(Radius.box, 14)
        XCTAssertEqual(Radius.panel, 16)
        XCTAssertEqual(Radius.card, 20)

        XCTAssertLessThan(Radius.chip, Radius.control)
        XCTAssertLessThan(Radius.control, Radius.box)
        XCTAssertLessThan(Radius.box, Radius.panel)
        XCTAssertLessThan(Radius.panel, Radius.card)
    }

    /// The focus ring rides 3pt outside the control it surrounds. It was
    /// written longhand as `Radius.control + 3` at three call sites, which is
    /// three places to forget when `control` moves — and `control` has now
    /// moved twice. The ring followed it to 15pt without any of those sites
    /// being touched, which is the property this pins.
    func testTheFocusRingStaysThreePointsOutsideItsControl() {
        XCTAssertEqual(Radius.focusRing, Radius.control + 3)
        XCTAssertEqual(Radius.focusRing, 15)
    }

    func testMotionCascadeCapsItsTail() {
        XCTAssertEqual(Motion.cascadeDelay(index: 0), 0)
        XCTAssertEqual(Motion.cascadeDelay(index: 7), 0.21, accuracy: 0.000_001)
        XCTAssertEqual(Motion.cascadeDelay(index: 20), 0.21, accuracy: 0.000_001)
    }

    /// The hand ships as a file in the same directory the other faces ship in,
    /// and is registered by the same sweep. If it ever stops resolving, every
    /// note in the app silently falls back to the system face and looks fine.
    @MainActor
    func testTheHandRegistersFromTheBundle() {
        CalibreFonts.register()
        XCTAssertNotNil(UIFont(name: CalibreFonts.Name.hand, size: 17))
    }

    /// Caveat draws small for its point size, so the hand runs above the Geist
    /// body rather than matching it. A well-meaning normalisation is the
    /// failure this guards.
    @MainActor
    func testTheHandRunsLargerThanTheSansItSitsBeside() {
        CalibreFonts.register()
        let hand = UIFont(name: CalibreFonts.Name.hand, size: 17)
        let sans = UIFont(name: CalibreFonts.Name.sansRegular, size: 15)
        XCTAssertNotNil(hand)
        XCTAssertNotNil(sans)
        XCTAssertLessThan(hand?.xHeight ?? .infinity, sans?.xHeight ?? 0)
    }

    /// The paper tile ships as bytes, not as a catalog entry, so that the same
    /// file can be identical on web and Android. A resource declaration that
    /// stops copying it fails silently — the grain just goes away.
    func testPaperGrainShipsInTheBundle() {
        let url = Bundle.module.url(forResource: "paper-grain", withExtension: "png")
        XCTAssertNotNil(url)
        XCTAssertNotNil(url.flatMap { UIImage(contentsOfFile: $0.path) })
    }

    /// The card surface carries the warmth in light. In dark it no longer
    /// does: the dark ramp was a warm-brown one (page 0x141110, card 0x1C1815)
    /// and it read brown, so §3 replaced it with the admin console's neutral
    /// ramp — page 0x0E0D0B, card 0x151412 — leaving copper as the only warm
    /// voice in the theme. Pure white in light is still the one cold pixel in
    /// the app and it still sits under everything.
    @MainActor
    func testTheCardIsWarmInLightAndNeutralNearBlackInDark() {
        let card = UIColor(Color.calibre.card)

        var light = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        card.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&light.r, green: &light.g, blue: &light.b, alpha: &light.a)
        XCTAssertEqual(light.r, 0xFE / 255, accuracy: 0.002)
        XCTAssertEqual(light.g, 0xFC / 255, accuracy: 0.002)
        XCTAssertEqual(light.b, 0xF8 / 255, accuracy: 0.002)

        var dark = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        card.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            .getRed(&dark.r, green: &dark.g, blue: &dark.b, alpha: &dark.a)
        XCTAssertEqual(dark.r, 0x15 / 255, accuracy: 0.002)
        XCTAssertEqual(dark.g, 0x14 / 255, accuracy: 0.002)
        XCTAssertEqual(dark.b, 0x12 / 255, accuracy: 0.002)
    }

    /// What "reads brown" actually was, measured. Red-minus-blue across the
    /// four dark grounds, in 0–255 steps:
    ///
    ///     old  background 0x141110 → 4   card 0x1C1815 → 7
    ///          secondary  0x211C18 → 9   accent 0x2A231D → 13
    ///     new  background 0x0E0D0B → 3   card 0x151412 → 3
    ///          secondary  0x151412 → 3   accent 0x1B1917 → 4
    ///
    /// The old ramp warmed up as it rose, which is why the raised surfaces —
    /// the chips and callouts — were the brownest things on the page. Pinning
    /// the spread rather than the hexes is what catches a well-meaning
    /// re-warming that picks different numbers.
    @MainActor
    func testTheDarkGroundsStayNeutralRatherThanBrown() {
        let grounds: [(String, Color)] = [
            ("background", Color.calibre.background),
            ("card", Color.calibre.card),
            ("secondary", Color.calibre.secondary),
            ("accent", Color.calibre.accent),
        ]

        for (name, token) in grounds {
            var c = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
            UIColor(token).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
                .getRed(&c.r, green: &c.g, blue: &c.b, alpha: &c.a)
            XCTAssertLessThanOrEqual((c.r - c.b) * 255, 4.5, "\(name) has warmed back up")
        }
    }

    /// Copper is the one warm hue the neutral ramp keeps, and the wax seal
    /// keeps a colour of its own (CALIBRE_BY_HAND_CONTRACTS.md §17). Both were
    /// standing next to twelve tokens being swept to neutral.
    @MainActor
    func testCopperAndWaxSurvivedTheNeutralSweep() {
        for (name, token, expected) in [
            ("primary", Color.calibre.primary, (0xC7, 0x92, 0x74)),
            ("primaryDeep", Color.calibre.primaryDeep, (0xB5, 0x80, 0x63)),
            ("wax", Color.calibre.wax, (0xB4, 0x48, 0x3D)),
            ("waxHighlight", Color.calibre.waxHighlight, (0xD0, 0x65, 0x5A)),
        ] {
            var c = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
            UIColor(token).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
                .getRed(&c.r, green: &c.g, blue: &c.b, alpha: &c.a)
            XCTAssertEqual(c.r, CGFloat(expected.0) / 255, accuracy: 0.002, name)
            XCTAssertEqual(c.g, CGFloat(expected.1) / 255, accuracy: 0.002, name)
            XCTAssertEqual(c.b, CGFloat(expected.2) / 255, accuracy: 0.002, name)
        }
    }

    /// The palette had `success` and `destructive` and nothing for pending or
    /// expiring, so `StatusBadge.Tone.warning` invented its own amber as a raw
    /// sRGB literal and was the one tone in the app that ignored dark mode.
    /// This asserts the token resolves to two different colours, which the
    /// literal could not have done.
    @MainActor
    func testWarningIsARealTokenAndNotAFrozenAmber() {
        let warning = UIColor(Color.calibre.warning)

        var light = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        warning.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .getRed(&light.r, green: &light.g, blue: &light.b, alpha: &light.a)
        XCTAssertEqual(light.r, 0x8A / 255, accuracy: 0.002)
        XCTAssertEqual(light.g, 0x62 / 255, accuracy: 0.002)
        XCTAssertEqual(light.b, 0x20 / 255, accuracy: 0.002)

        var dark = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
        warning.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            .getRed(&dark.r, green: &dark.g, blue: &dark.b, alpha: &dark.a)
        XCTAssertEqual(dark.r, 0xDF / 255, accuracy: 0.002)
        XCTAssertEqual(dark.g, 0xAE / 255, accuracy: 0.002)
        XCTAssertEqual(dark.b, 0x5E / 255, accuracy: 0.002)

        XCTAssertEqual(UIColor(StatusBadge.Tone.warning.tint), warning)
    }

    /// The four tokens with an Increase Contrast pair have to clear their
    /// target on the *worst* ground they land on, and the dark grounds all
    /// moved. Text wants 4.5:1, a stroke someone has to find wants 3:1. The
    /// darkest-contrast dark ground is `accent`, so that is what these are
    /// measured against.
    @MainActor
    func testTheIncreaseContrastPairsClearTheirTargetsOnTheNewGrounds() {
        let highContrastDark = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(accessibilityContrast: .high),
        ])
        let highContrastLight = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(accessibilityContrast: .high),
        ])

        let checks: [(String, Color, Color, UITraitCollection, CGFloat)] = [
            ("mutedForeground/dark", Color.calibre.mutedForeground, Color.calibre.accent, highContrastDark, 4.5),
            ("placeholder/dark", Color.calibre.placeholder, Color.calibre.card, highContrastDark, 4.5),
            ("border/dark", Color.calibre.border, Color.calibre.accent, highContrastDark, 3),
            ("borderBright/dark", Color.calibre.borderBright, Color.calibre.accent, highContrastDark, 3),
            ("mutedForeground/light", Color.calibre.mutedForeground, Color.calibre.background, highContrastLight, 4.5),
            ("placeholder/light", Color.calibre.placeholder, Color.calibre.card, highContrastLight, 4.5),
            ("border/light", Color.calibre.border, Color.calibre.card, highContrastLight, 3),
            ("borderBright/light", Color.calibre.borderBright, Color.calibre.card, highContrastLight, 3),
        ]

        for (name, ink, ground, traits, target) in checks {
            let ratio = Self.contrast(
                UIColor(ink).resolvedColor(with: traits),
                UIColor(ground).resolvedColor(with: traits)
            )
            XCTAssertGreaterThanOrEqual(ratio, target, "\(name) resolves to \(ratio):1")
        }
    }

    /// WCAG 2.1 relative luminance.
    private static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        func luminance(_ color: UIColor) -> CGFloat {
            var c = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), a: CGFloat(0))
            color.getRed(&c.r, green: &c.g, blue: &c.b, alpha: &c.a)
            func channel(_ v: CGFloat) -> CGFloat {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
        }
        let high = max(luminance(a), luminance(b))
        let low = min(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
    }
}

/// The logo's arc is an ellipse, and the difference between it and the circle
/// it nearly is decides the shape of the opening. These check the drawn
/// centreline lands where the traced original says it does.
final class MarkGeometryTests: XCTestCase {
    func testLogoArcMeetsTheTracedEndpoints() {
        var arc = Path()
        arc.addEllipticalArc(
            centre: CGPoint(x: 61.2149, y: 58.1656),
            radii: CGSize(width: 43.36, height: 42.55),
            rotation: .degrees(-98.29),
            start: .degrees(136.9632),
            delta: .degrees(283.29)
        )

        var first: CGPoint?
        var last: CGPoint?
        arc.forEach { element in
            switch element {
            case .move(let to):
                first = first ?? to
                last = to
            case .curve(let to, _, _):
                last = to
            case .line(let to):
                last = to
            case .quadCurve(let to, _):
                last = to
            case .closeSubpath:
                break
            }
        }

        XCTAssertEqual(first?.x ?? .nan, 94.52, accuracy: 0.01)
        XCTAssertEqual(first?.y ?? .nan, 85.34, accuracy: 0.01)
        XCTAssertEqual(last?.x ?? .nan, 94.67, accuracy: 0.01)
        XCTAssertEqual(last?.y ?? .nan, 31.55, accuracy: 0.01)
    }

    /// Every point of the arc has to sit on the fitted ellipse. The ellipse is
    /// only a couple of percent off round, so the departure from a same-centre
    /// circle is a fraction of a stroke width — small, but it is the fitted
    /// shape, and a circle substituted for it would read as a re-trace by eye.
    /// Pinning the departure catches both mistakes: a circle collapses it to
    /// nothing, a re-fit moves it.
    func testLogoArcStaysOnTheEllipseAndNotOnACircle() {
        var arc = Path()
        arc.addEllipticalArc(
            centre: CGPoint(x: 61.2149, y: 58.1656),
            radii: CGSize(width: 43.36, height: 42.55),
            rotation: .degrees(-98.29),
            start: .degrees(136.9632),
            delta: .degrees(283.29)
        )

        // Into the ellipse's own frame, where it should read as a unit circle.
        let intoUnitSpace = CGAffineTransform(translationX: 61.2149, y: 58.1656)
            .rotated(by: Angle.degrees(-98.29).radians)
            .scaledBy(x: 43.36, y: 42.55)
            .inverted()

        var offEllipse: CGFloat = 0
        var offCircle: CGFloat = 0
        let meanRadius: CGFloat = (43.36 + 42.55) / 2
        arc.forEach { element in
            guard case .curve(let to, _, _) = element else { return }
            let unit = to.applying(intoUnitSpace)
            offEllipse = max(offEllipse, abs(hypot(unit.x, unit.y) - 1))
            offCircle = max(offCircle, abs(hypot(to.x - 61.2149, to.y - 58.1656) - meanRadius))
        }

        XCTAssertLessThan(offEllipse, 0.001)
        XCTAssertEqual(offCircle, 0.405, accuracy: 0.02)
    }

    /// The centre the endpoint-to-centre conversion derives has to agree with
    /// the jewel the mark is drawn around. They are independent numbers in §3,
    /// so them landing together is what says the conversion is right.
    func testDerivedArcCentreAgreesWithTheJewel() {
        let derived = CGPoint(x: 61.2149, y: 58.1656)
        let jewel = CGPoint(x: 60.48, y: 58.52)
        XCTAssertLessThan(hypot(derived.x - jewel.x, derived.y - jewel.y), 1)
    }

    /// A quarter turn of the unit circle, drawn by the same helper the marks
    /// use for their gauge tracks.
    func testCircularArcTracksItsRadius() {
        var quarter = Path()
        quarter.addCircularArc(
            centre: CGPoint(x: 60, y: 60),
            radius: 44,
            start: .degrees(180),
            delta: .degrees(90)
        )

        var worst: CGFloat = 0
        quarter.forEach { element in
            guard case .curve(let to, _, _) = element else { return }
            worst = max(worst, abs(hypot(to.x - 60, to.y - 60) - 44))
        }
        XCTAssertLessThan(worst, 0.05)
    }
}

/// The vocabulary's drawings, checked at the level the divergence happened at:
/// what each mark actually is. Every defect §11 records was invisible to a test
/// and obvious in a render, so these assert the thing a render would show —
/// that the stamp presses the mark and not a tick, that the reserve is a spring
/// and not a second gauge, that the parcel is a parcel.
final class MarkDrawingTests: XCTestCase {
    /// Endpoints of every straight and curved segment on a path, which is
    /// enough to tell one of these drawings from another.
    private func vertices(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let to), .line(let to), .curve(let to, _, _), .quadCurve(let to, _):
                points.append(to)
            case .closeSubpath:
                break
            }
        }
        return points
    }

    /// The one that matters most: what comes down on the passport is the
    /// Calibre mark. A tick, or any other borrowed glyph, has none of the
    /// logo's traced points anywhere near it.
    func testTheStampPressesTheCalibreMarkAndNotAGlyph() {
        let drawn = vertices(StampMark.head)
        // The traced arc's two ends, §3, carried through the same shrink the
        // drawing uses. Both have to land on the head.
        for tip in [CGPoint(x: 94.52, y: 85.34), CGPoint(x: 94.67, y: 31.55)] {
            let expected = tip.applying(StampMark.die)
            let nearest = drawn.map { hypot($0.x - expected.x, $0.y - expected.y) }.min() ?? .infinity
            XCTAssertLessThan(nearest, 0.05, "the logo's arc is not on the stamp")
        }

        // And it sits inside the rim rather than over it.
        let monogram = CalibreLogoMark.strokes.applying(StampMark.die).boundingRect
        XCTAssertGreaterThan(monogram.minX, 24)
        XCTAssertLessThan(monogram.maxX, 96)
    }

    /// The seal carries the monogram, which is what earned it the canon. Two
    /// concentric rings would leave the bounding box centred and the arc's ends
    /// nowhere.
    func testTheSealPressesTheSameMarkAtItsOwnScale() {
        let drawn = vertices(WaxSealMark.impression)
        let expected = CGPoint(x: 94.52, y: 85.34).applying(
            CGAffineTransform(translationX: 60, y: 60)
                .scaledBy(x: 0.62, y: 0.62)
                .translatedBy(x: -60.48, y: -58.52)
        )
        let nearest = drawn.map { hypot($0.x - expected.x, $0.y - expected.y) }.min() ?? .infinity
        XCTAssertLessThan(nearest, 0.05, "the wax is not carrying the monogram")

        // The die stays clear of the wax's edge, or the press reads as a crop.
        XCTAssertTrue(WaxSealMark.wax.boundingRect.insetBy(dx: 4, dy: 4)
            .contains(WaxSealMark.impression.boundingRect))
    }

    /// Wax spreads unevenly; a true circle here is a button. The lobes are
    /// small on purpose, so this pins them rather than eyeballing them.
    func testTheWaxEdgeIsLobedRatherThanRound() {
        let radii = vertices(WaxSealMark.wax).map { hypot($0.x - 60, $0.y - 60) }
        let low = try? XCTUnwrap(radii.min())
        let high = try? XCTUnwrap(radii.max())
        XCTAssertEqual((high ?? 0) - (low ?? 0), 3.6, accuracy: 0.05)
    }

    /// A mainspring, not a second arc gauge. A gauge's outline reaches its own
    /// horizontal twice; a spiral of half-turns reaches it once per coil plus
    /// the tail, on alternating sides and always further out.
    func testTheReserveIsASpringAndNotASecondGauge() {
        // Each coil hands the next one its own end point, so the seam between
        // them lands twice on the path and once here.
        let turningPoints = vertices(PowerReserveMark.spring(1))
            .filter { abs($0.y - 60) < 0.001 }
            .map { $0.x }
            .reduce(into: [CGFloat]()) { seam, x in
                if seam.last != x { seam.append(x) }
            }

        XCTAssertEqual(turningPoints.count, PowerReserveMark.coils.count + 1)

        for (index, x) in turningPoints.enumerated() {
            XCTAssertEqual(x < 60, index.isMultiple(of: 2), "coil \(index) turned the wrong way")
        }

        // And every turn stands further out than the one before it, which is
        // what a spiral has and a stack of rings does not.
        let reach = turningPoints.map { abs($0 - 60) }
        for (inner, outer) in zip(reach, reach.dropFirst(2)) {
            XCTAssertGreaterThan(outer, inner, "the spring stopped growing")
        }
    }

    /// The reading is a proportion of the spring's own length, and the length
    /// it is measured against comes off the same list the path is built from.
    /// So winding to half has to land where trimming the whole spring to half
    /// its ink lands — not on half the coils, which is where a spiral drawn
    /// turn by turn goes wrong.
    func testTheSpringWindsByLengthAndNotByCoil() throws {
        let wound = try XCTUnwrap(PowerReserveMark.spring(0.5).currentPoint)
        let trimmed = try XCTUnwrap(
            PowerReserveMark.spring(1).trimmedPath(from: 0, to: 0.5).currentPoint
        )
        XCTAssertEqual(hypot(wound.x - trimmed.x, wound.y - trimmed.y), 0, accuracy: 0.5)
        XCTAssertTrue(PowerReserveMark.spring(0).isEmpty)
    }

    /// Knurls, one click apart so a click lands the next one where the last one
    /// stood, and one of them proud so a turn of exactly one click is not the
    /// same picture again. A sawtooth cog fails the spacing; an even ring fails
    /// the proud one.
    func testTheCrownsKnurlsAreOneClickApartWithOneProud() {
        let ends = vertices(CrownMark.knurl)
        let reaches = stride(from: 1, to: ends.count, by: 2)
            .map { hypot(ends[$0].x - 60, ends[$0].y - 60) }
        let starts = stride(from: 0, to: ends.count, by: 2)
            .map { atan2(ends[$0].y - 60, ends[$0].x - 60) * 180 / .pi }

        XCTAssertEqual(reaches.count, Int((360 / MarkMotion.clickTurn.degrees).rounded()))
        XCTAssertEqual(reaches.filter { $0 > 41 }.count, 1, "no knurl stands proud")

        let gaps = zip(starts, starts.dropFirst()).map { ($1 - $0 + 360).truncatingRemainder(dividingBy: 360) }
        for gap in gaps {
            XCTAssertEqual(gap, MarkMotion.clickTurn.degrees, accuracy: 0.001)
        }
    }

    /// A parcel, not a book. The tape stops a long way short of the floor —
    /// a line run all the way down is exactly what made this read as a spine —
    /// and the carton's stroke leaves the top open for the flaps to close.
    func testTheBoxIsAParcelAndNotABook() {
        let tape = BoxMark.tape.boundingRect
        XCTAssertEqual(tape.minY, BoxMark.lid, accuracy: 0.001)
        XCTAssertGreaterThan(BoxMark.floorLine - tape.maxY, 25)

        let walls = vertices(BoxMark.carton)
        XCTAssertEqual(walls.first?.y ?? .nan, BoxMark.lid, accuracy: 0.001)
        XCTAssertEqual(walls.last?.y ?? .nan, BoxMark.lid, accuracy: 0.001)
        XCTAssertNotEqual(walls.first?.x ?? .nan, walls.last?.x ?? .nan)
    }

    /// A balance, not a crosshair: arms that stop at the staff instead of
    /// running through the centre, and the canonical number of them.
    func testTheBalanceWheelIsABalanceAndNotACrosshair() {
        let arms = vertices(BalanceWheelMark.rim).suffix(BalanceWheelMark.arms.count * 2)
        XCTAssertEqual(BalanceWheelMark.arms.count, 3)

        for start in stride(from: arms.startIndex, to: arms.endIndex, by: 2) {
            let inner = arms[start]
            let outer = arms[start + 1]
            XCTAssertEqual(hypot(inner.x - 60, inner.y - 60), 10, accuracy: 0.001)
            XCTAssertEqual(hypot(outer.x - 60, outer.y - 60), 44, accuracy: 0.001)
        }
    }

    /// The glass has a handle, and the handle leaves the lens. Rings inside
    /// rings — the drawing this replaced — never reach past their own outline.
    func testTheLoupeHasAHandleThatLeavesTheLens() {
        let reach = vertices(LoupeMark.glass)
            .map { hypot($0.x - 60, $0.y - 60) }
            .max() ?? 0
        XCTAssertGreaterThan(reach, LoupeMark.lens + MarkGrid.stroke * 2)
    }

    /// The resting pose has to read as examined: the glass still on the detail,
    /// and the detail worth the look but still under the lens. A jewel that
    /// grows past the glass is the mark saying the opposite thing.
    func testTheLoupeRestsOnTheJewelUnderTheLens() {
        let ring = LoupeMark.centred(10.71).boundingRect.width / 2 * LoupeMark.magnification
        XCTAssertEqual(ring, 20.03, accuracy: 0.01)
        XCTAssertLessThan(ring + MarkGrid.stroke, LoupeMark.lens)
    }
}

/// Which marks carry a fill, checked by looking rather than by declaring it.
///
/// The rule is a shape rule: single ink, arcs and circles, and a fill only
/// where the material is the point — the die's jewel, the wax, the finding
/// under the glass, the kraft. Nothing in a `View` says whether it filled
/// anything, so this renders each mark and samples a place where only a fill
/// could have put ink, and a place where only a fill could have taken it away.
///
/// Eroding the ink instead would have been the general answer and does not
/// work: round joins make the crossings in `crown` and `balanceWheel` locally
/// wider than the stroke, which reads as a blob.
@MainActor
final class MarkFillTests: XCTestCase {
    private let scale: CGFloat = 4

    /// Whether one grid point of a mark, rendered on nothing, has ink on it.
    private func ink(_ mark: some View, at point: CGPoint) throws -> Bool {
        let renderer = ImageRenderer(content: mark.frame(width: MarkGrid.side, height: MarkGrid.side))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: cgImage.width, height: cgImage.height,
            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        let x = Int(point.x * scale)
        let y = Int(point.y * scale)
        // Alpha alone: the mark is drawn on nothing, so anything the drawing
        // put down is opaque enough to see and the rest is empty.
        return pixels[(y * cgImage.width + x) * 4 + 3] > 12
    }

    /// A fill's own interior, in each of the marks allowed one. Every point is
    /// far enough from every stroke that only a fill can have inked it.
    ///
    /// The stamp's head is still in the air on the frame this renders, so its
    /// die's jewel is given at both ends of the fall — where the head has got
    /// to is a motion state, and this is asking about a shape.
    func testTheMarksAllowedAFillHaveOne() throws {
        let filled: [(String, AnyView, [CGPoint])] = [
            ("stamp", AnyView(CalibreMark.stamp()), [CGPoint(x: 60, y: 60), CGPoint(x: 60, y: 42)]),
            ("waxSeal", AnyView(CalibreMark.waxSeal()), [CGPoint(x: 60, y: 26)]),
            ("loupe", AnyView(CalibreMark.loupe()), [CGPoint(x: 60, y: 60)]),
            ("box", AnyView(CalibreMark.box()), [CGPoint(x: 40, y: 85)]),
        ]

        for (name, mark, points) in filled {
            XCTAssertTrue(try points.contains { try ink(mark, at: $0) }, "\(name) has lost its fill")
        }
    }

    /// And the interiors that have to stay empty. A fill arriving in any of
    /// these is the drawing leaving the vocabulary.
    func testTheOtherMarksStayOutlines() throws {
        let hollow: [(String, AnyView, CGPoint)] = [
            ("balanceWheel", AnyView(CalibreMark.balanceWheel()), CGPoint(x: 60, y: 60)),
            ("dialArc", AnyView(CalibreMark.dialArc(0)), CGPoint(x: 60, y: 78)),
            ("powerReserve", AnyView(CalibreMark.powerReserve(1)), CGPoint(x: 60, y: 60)),
            ("crown", AnyView(CalibreMark.crown()), CGPoint(x: 60, y: 60)),
        ]

        // Each of these sits at the centre of something that does not move, so
        // it is the same claim wherever the mark is in its own motion.
        for (name, mark, point) in hollow {
            XCTAssertFalse(try ink(mark, at: point), "\(name) has grown a fill")
        }
    }
}
