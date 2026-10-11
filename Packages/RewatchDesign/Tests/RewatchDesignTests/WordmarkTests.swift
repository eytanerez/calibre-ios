import SwiftUI
import UIKit
import XCTest

@testable import RewatchDesign

/// The wordmark's three drawings as the package ships them, read from the
/// asset catalog's own SVG files so a stale copy of the old word cannot sit
/// behind a green suite.
private enum WordmarkSource {
    /// `Sources/RewatchDesign/Assets.xcassets`, from this file's place in the tree.
    static var catalog: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // RewatchDesignTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // RewatchDesign
            .appendingPathComponent("Sources/RewatchDesign/Assets.xcassets")
    }

    static func svg(_ imageset: String, _ file: String) throws -> String {
        try String(contentsOf: catalog.appendingPathComponent("\(imageset).imageset/\(file)"), encoding: .utf8)
    }

    static func pathData(_ svg: String) throws -> String {
        let start = try XCTUnwrap(svg.range(of: " d=\""))
        let end = try XCTUnwrap(svg.range(of: "\"", range: start.upperBound..<svg.endIndex))
        return String(svg[start.upperBound..<end.lowerBound])
    }

    /// Every on-curve and control point of an absolute `M L H V Q Z` path —
    /// the only commands the generator emits. A quadratic lies inside the hull
    /// of its points, so a claim true of every point is true of the curve.
    static func points(_ data: String) -> [CGPoint] {
        var tokens: [String] = []
        var number = ""
        for character in data {
            if character.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(character))
            } else if character == " " || character == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if character == "-", !number.isEmpty {
                tokens.append(number); number = "-"
            } else {
                number.append(character)
            }
        }
        if !number.isEmpty { tokens.append(number) }

        var points: [CGPoint] = []
        var current = CGPoint.zero
        var command = ""
        var index = 0
        func value() -> CGFloat {
            defer { index += 1 }
            return CGFloat(Double(tokens[index]) ?? .nan)
        }
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index]
                index += 1
                if command == "Z" { continue }
            }
            switch command {
            case "M", "L":
                current = CGPoint(x: value(), y: value())
                points.append(current)
            case "Q":
                points.append(CGPoint(x: value(), y: value()))
                current = CGPoint(x: value(), y: value())
                points.append(current)
            case "H":
                current.x = value()
                points.append(current)
            case "V":
                current.y = value()
                points.append(current)
            default:
                XCTFail("unexpected path command \(command)")
                return points
            }
        }
        return points
    }
}

final class WordmarkAssetTests: XCTestCase {
    /// The word is the Playfair outline on its tight box, and the view's
    /// proportion is that box's — a stretched or squashed word is the first
    /// thing anyone would see.
    func testTheWordmarkIsThePlayfairOutlineOnItsTightBox() throws {
        let svg = try WordmarkSource.svg("RewatchWordmark", "rewatch-wordmark.svg")
        XCTAssertTrue(svg.contains("viewBox=\"0 0 3821 796\""), "the wordmark is not the 3821 × 796 drawing")
        XCTAssertEqual(RewatchWordmark.aspectRatio, 3821.0 / 796.0, accuracy: 1e-9)

        let image = try XCTUnwrap(UIImage(named: "RewatchWordmark", in: .module, with: nil))
        XCTAssertEqual(image.size.width / image.size.height, 3821.0 / 796.0, accuracy: 0.001)
    }

    /// The opening's two pieces are cut from the same drawing on the same box:
    /// their outlines, joined, are the word's, and they compile to images of
    /// the word's own size, so laid in one frame they overlay to the word.
    func testThePiecesAreTheWordCutInTwo() throws {
        let word = try WordmarkSource.pathData(WordmarkSource.svg("RewatchWordmark", "rewatch-wordmark.svg"))
        let re = try WordmarkSource.svg("RewatchWordmarkRe", "rewatch-wordmark-re.svg")
        let watch = try WordmarkSource.svg("RewatchWordmarkWatch", "rewatch-wordmark-watch.svg")
        XCTAssertTrue(re.contains("viewBox=\"0 0 3821 796\""))
        XCTAssertTrue(watch.contains("viewBox=\"0 0 3821 796\""))
        XCTAssertEqual(try WordmarkSource.pathData(re) + WordmarkSource.pathData(watch), word)

        let whole = try XCTUnwrap(UIImage(named: "RewatchWordmark", in: .module, with: nil))
        for name in ["RewatchWordmarkRe", "RewatchWordmarkWatch"] {
            let piece = try XCTUnwrap(UIImage(named: name, in: .module, with: nil), name)
            XCTAssertEqual(piece.size.width, whole.size.width, accuracy: 0.01, name)
            XCTAssertEqual(piece.size.height, whole.size.height, accuracy: 0.01, name)
            XCTAssertEqual(piece.renderingMode, .alwaysTemplate, "\(name) has to tint like the word")
        }
    }
}

/// The opening's frames, from the one function both the running opening and
/// the debug freeze draw. Numbers are §3's.
final class OpeningTests: XCTestCase {
    private func frame(_ milliseconds: Double) -> OpeningFrame {
        OpeningFrame.at(milliseconds / 1000, reduced: false)
    }

    func testWatchArrivesCentredAndAlone() {
        let first = frame(0)
        XCTAssertEqual(first.watchOpacity, 0)
        XCTAssertEqual(first.watchRise, 0.02, accuracy: 1e-9)
        XCTAssertEqual(first.groupShift, -0.13753, accuracy: 1e-9)
        XCTAssertEqual(first.reShift, 0.34284, accuracy: 1e-9)

        let arrived = frame(420)
        XCTAssertEqual(arrived.watchOpacity, 1, accuracy: 1e-6)
        XCTAssertEqual(arrived.watchRise, 0, accuracy: 1e-6)
    }

    /// The hold is a hold: nothing slides before 442 ms, however the move is
    /// eased. One curve stretched over the whole timeline would already have
    /// moved the word here — the first draft's bug.
    func testTheHoldDoesNotMove() {
        for milliseconds in [0.0, 200, 420, 430, 442] {
            XCTAssertEqual(frame(milliseconds).groupShift, -0.13753, accuracy: 1e-9, "\(milliseconds) ms")
            XCTAssertEqual(frame(milliseconds).reShift, 0.34284, accuracy: 1e-9, "\(milliseconds) ms")
        }
        XCTAssertGreaterThan(frame(460).groupShift, -0.13753)
    }

    /// One eased move, 442 → 1300 ms, on `cubic-bezier(0.22, 1, 0.36, 1)`
    /// applied to that segment alone; both layers ride the same progress.
    func testTheSlideIsOneEasedMoveOnItsOwnSegment() {
        let midway = frame(442 + 858 / 2)
        let eased = OpeningFrame.curve(0.5)
        XCTAssertEqual(midway.groupShift, -0.13753 * (1 - eased), accuracy: 1e-6)
        XCTAssertEqual(midway.reShift, 0.34284 * (1 - eased), accuracy: 1e-6)
        // An ease-out this strong is most of the way there by halfway.
        XCTAssertGreaterThan(eased, 0.85)

        var previous = frame(442)
        for milliseconds in stride(from: 450.0, through: 1300, by: 10) {
            let next = frame(milliseconds)
            XCTAssertGreaterThanOrEqual(next.groupShift, previous.groupShift - 1e-12)
            XCTAssertLessThanOrEqual(next.reShift, previous.reShift + 1e-12)
            previous = next
        }
    }

    func testTheWordIsFormedAt1300AndStays() {
        for milliseconds in [1300.0, 1450, 5000] {
            let rest = frame(milliseconds)
            XCTAssertEqual(rest.groupShift, 0, accuracy: 1e-9)
            XCTAssertEqual(rest.reShift, 0, accuracy: 1e-9)
            XCTAssertEqual(rest.watchRise, 0, accuracy: 1e-9)
            XCTAssertEqual(rest.watchOpacity, 1, accuracy: 1e-9)
            XCTAssertEqual(rest.wordOpacity, 1)
        }
    }

    /// The boot screen holds for the opening plus a 150 ms rest before it
    /// hands over, so the slide is never cut off.
    func testTheBootScreenHoldsForTheOpening() {
        XCTAssertEqual(OpeningTimeline(reduced: false).duration, 1.30, accuracy: 1e-9)
        XCTAssertEqual(OpeningTimeline(reduced: false).hold, 1.45, accuracy: 1e-9)
        XCTAssertEqual(OpeningTimeline(reduced: true).duration, 0.20, accuracy: 1e-9)
        XCTAssertEqual(OpeningTimeline(reduced: true).hold, 0.35, accuracy: 1e-9)
    }

    /// Reduce Motion: the formed word fades in over 200 ms, and nothing slides.
    func testReducedMotionFadesTheFormedWordIn() {
        for milliseconds in [0.0, 100, 200, 1300] {
            let reduced = OpeningFrame.at(milliseconds / 1000, reduced: true)
            XCTAssertEqual(reduced.groupShift, 0)
            XCTAssertEqual(reduced.reShift, 0)
            XCTAssertEqual(reduced.watchRise, 0)
            XCTAssertEqual(reduced.watchOpacity, 1)
        }
        XCTAssertEqual(OpeningFrame.at(0, reduced: true).wordOpacity, 0)
        XCTAssertEqual(OpeningFrame.at(0.2, reduced: true).wordOpacity, 1, accuracy: 1e-6)
    }

    /// The cut, against the actual outlines: "Re" at rest is wholly left of the
    /// line (the finished word is never clipped), "Re" at its start is wholly
    /// right of it (invisible until it slides), and "Watch" never crosses it
    /// (the line is just clear of the W's left edge, so "Re" comes out from
    /// behind the W rather than through it).
    func testTheCutHidesReAtTheStartAndNeverCutsTheWord() throws {
        let re = WordmarkSource.points(try WordmarkSource.pathData(
            WordmarkSource.svg("RewatchWordmarkRe", "rewatch-wordmark-re.svg")
        ))
        let watch = WordmarkSource.points(try WordmarkSource.pathData(
            WordmarkSource.svg("RewatchWordmarkWatch", "rewatch-wordmark-watch.svg")
        ))
        XCTAssertGreaterThan(re.count, 50)
        XCTAssertGreaterThan(watch.count, 100)

        let width: CGFloat = 3821, height: CGFloat = 796
        func cut(at y: CGFloat) -> CGFloat {
            width * (OpeningFrame.cutTop + (OpeningFrame.cutBottom - OpeningFrame.cutTop) * Double(y / height))
        }
        for point in re {
            XCTAssertLessThan(point.x, cut(at: point.y), "Re is clipped at rest at \(point)")
            XCTAssertGreaterThan(point.x + width * OpeningFrame.reStart, cut(at: point.y), "Re shows at the start at \(point)")
        }
        for point in watch {
            XCTAssertGreaterThan(point.x, cut(at: point.y), "the cut crosses Watch at \(point)")
        }

        // And the clip the view uses is that line.
        let clip = OpeningCut().path(in: CGRect(x: 0, y: 0, width: width, height: height))
        XCTAssertTrue(clip.contains(CGPoint(x: cut(at: 0) - 1, y: 0)))
        XCTAssertFalse(clip.contains(CGPoint(x: cut(at: 0) + 1, y: 0)))
        XCTAssertTrue(clip.contains(CGPoint(x: cut(at: height) - 1, y: height)))
        XCTAssertFalse(clip.contains(CGPoint(x: cut(at: height) + 1, y: height)))
    }

    /// "Watch" alone is centred: the group's shift is the distance from the
    /// word's centre to Watch's own, as a fraction of the word.
    func testWatchAloneSitsOnTheCentre() throws {
        let watch = WordmarkSource.points(try WordmarkSource.pathData(
            WordmarkSource.svg("RewatchWordmarkWatch", "rewatch-wordmark-watch.svg")
        ))
        let left = try XCTUnwrap(watch.map(\.x).min())
        let right = try XCTUnwrap(watch.map(\.x).max())
        let shift = (3821 / 2 - (left + right) / 2) / 3821
        XCTAssertEqual(Double(shift), OpeningFrame.watchAloneShift, accuracy: 0.0005)
    }
}
