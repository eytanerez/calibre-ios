import SwiftUI
import UIKit

/// The opening: the first thing drawn after the system launch screen, once
/// per cold launch. "Watch" arrives centred on its own, then "Re" slides out
/// from behind the W's slanted left edge while the word re-centres, and the
/// finished word rests until the app is ready to take over.
///
/// Eytan, 2026-10-11: *"for the app opening animation can we have it say Watch
/// and then the Re slides out of it … just keep it super smooth."* The numbers
/// are REWATCH_PLAYFAIR_WORDMARK_CONTRACTS.md §3's, which were verified frame by
/// frame in a browser; they are fractions of the word's drawn width, so the
/// opening is the same shape at any size.
///
/// **One source of truth for every frame.** `OpeningFrame.at(_:reduced:)` is a
/// pure function of elapsed seconds, and the view is a pure function of that.
/// What moves is a single `time` value, animated linearly from 0 to the end by
/// SwiftUI's own animation clock, so the frames land on the display's refresh
/// (no `TimelineView`, which redraws whatever holds it, and no sleep loop,
/// which drifts off it). The easing lives inside the function, on the moving
/// segments only and never on the hold between them — §3's note on the first
/// draft, where one easing stretched over the whole timeline started the slide
/// early. The same function is what a test reads and what the debug freeze
/// renders, so a captured still is exactly the frame the running opening drew.
///
/// **Reduce Motion** is the whole word, already formed, fading in over 200 ms.
/// No slide.
///
/// **It never plays twice in one process.** The first run sets a flag for the
/// life of the process, so a scene the system tears down and builds again on a
/// warm resume shows the finished word at rest instead of replaying.
public struct RewatchOpening: View {
    /// The word's drawn width, `Wd` in the contract.
    let width: CGFloat
    /// Called once, on the main actor, when the opening has played and rested:
    /// the moment the caller may hand over to the app.
    let onPlayed: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var time: TimeInterval = 0
    /// Read once, when the opening starts, so a setting changed mid-opening
    /// cannot reinterpret a `time` that was started under the other timeline.
    @State private var reduced: Bool?
    @State private var started = false

    public init(width: CGFloat, onPlayed: @escaping @MainActor () -> Void) {
        self.width = width
        self.onPlayed = onPlayed
    }

    private var motionIsUnwelcome: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    public var body: some View {
        OpeningWord(time: time, width: width, reduced: reduced ?? motionIsUnwelcome)
            .accessibilityElement()
            .accessibilityLabel("ReWatch")
            .accessibilityAddTraits(.isImage)
            // The clock starts the first time the scene is active with this on
            // screen, not merely when it is built: a scene brought up in the
            // background would otherwise play the whole opening to nobody.
            // Once started it runs to the end whatever the scene does next —
            // pulling down Notification Center mid-slide must not cancel the
            // hand-off.
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active, !started else { return }
                started = true
                start()
            }
    }

    private func start() {
        #if DEBUG
        if let frozen = Self.frozenByLaunchArgument {
            reduced = frozen.reduced
            time = frozen.time
            return
        }
        #endif
        let reduce = motionIsUnwelcome
        reduced = reduce
        let timeline = OpeningTimeline(reduced: reduce)

        guard !Self.hasPlayed else {
            time = timeline.duration
            onPlayed()
            return
        }

        withAnimation(.linear(duration: timeline.duration)) { time = timeline.duration }
        let onPlayed = onPlayed
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeline.hold))
            Self.hasPlayed = true
            onPlayed()
        }
    }

    /// Set once the opening has played in this process.
    @MainActor private static var hasPlayed = false

    #if DEBUG
    /// `-rewatchOpeningAt 560` freezes the opening at 560 ms, and holds the
    /// boot screen there, so any beat can be captured and looked at — a
    /// screenshot of a running opening catches whichever frame the shutter fell
    /// on. Add `-rewatchOpeningReduced` for the Reduce Motion timeline.
    static var frozenByLaunchArgument: (time: TimeInterval, reduced: Bool)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-rewatchOpeningAt"),
              index + 1 < arguments.count,
              let milliseconds = Double(arguments[index + 1])
        else { return nil }
        return (milliseconds / 1000, arguments.contains("-rewatchOpeningReduced"))
    }
    #endif
}

/// How long each opening runs, and how long the boot screen holds for it.
struct OpeningTimeline: Equatable {
    /// The last moment anything moves.
    let duration: TimeInterval
    /// The earliest hand-off: the end plus a 150 ms rest, so the finished word
    /// is seen standing before the app takes over and is never cut mid-slide.
    let hold: TimeInterval

    init(reduced: Bool) {
        duration = reduced ? OpeningFrame.reducedFade : OpeningFrame.moveEnd
        hold = duration + OpeningFrame.rest
    }
}

/// One frame of the opening. Offsets are fractions of the word's drawn width
/// (`groupShift`, `reShift`) or height (`watchRise`), in the word's own space.
struct OpeningFrame: Equatable {
    /// The whole word, sideways. Negative is left of its rest.
    var groupShift: Double
    /// "Re" inside its clip, sideways. Positive is right of its rest.
    var reShift: Double
    /// "Watch", downward. It arrives from a little below.
    var watchRise: Double
    var watchOpacity: Double
    /// The whole word. Only Reduce Motion moves it.
    var wordOpacity: Double

    // MARK: §3's numbers

    /// "Watch" alone sits centred: the group is this far left of its rest.
    static let watchAloneShift = -0.13753
    /// "Re" starts this far right of its rest, wholly behind the cut.
    static let reStart = 0.34284
    /// "Watch" rises from this far below, a fraction of the word's height.
    static let watchStartRise = 0.02
    /// The cut line, in the word's own coordinates: x at the top of the word
    /// and at the bottom, as fractions of its width.
    static let cutTop = 0.25674
    static let cutBottom = 0.34180

    /// "Watch" fades and rises over the first 420 ms.
    static let fadeEnd: TimeInterval = 0.420
    /// It holds, centred, until 442 ms…
    static let moveStart: TimeInterval = 0.442
    /// …and the one eased move runs to 1300 ms.
    static let moveEnd: TimeInterval = 1.300
    /// The rest before the hand-off.
    static let rest: TimeInterval = 0.150
    /// Reduce Motion's fade.
    static let reducedFade: TimeInterval = 0.200

    /// `cubic-bezier(0.22, 1, 0.36, 1)`, on each moving segment.
    static let curve = MomentCurve(x1: 0.22, y1: 1, x2: 0.36, y2: 1)

    static func at(_ time: TimeInterval, reduced: Bool) -> OpeningFrame {
        if reduced {
            let fade = MomentCurve.easeOut(min(max(time / reducedFade, 0), 1))
            return OpeningFrame(groupShift: 0, reShift: 0, watchRise: 0, watchOpacity: 1, wordOpacity: fade)
        }
        let arrival = curve(min(max(time / fadeEnd, 0), 1))
        let move = curve(min(max((time - moveStart) / (moveEnd - moveStart), 0), 1))
        return OpeningFrame(
            groupShift: watchAloneShift * (1 - move),
            reShift: reStart * (1 - move),
            watchRise: watchStartRise * (1 - arrival),
            watchOpacity: arrival,
            wordOpacity: 1
        )
    }
}

/// The opening drawn at one `time`. `Animatable` on `time`, so animating that
/// one number is what plays it.
struct OpeningWord: View, Animatable {
    var time: TimeInterval
    let width: CGFloat
    let reduced: Bool

    nonisolated var animatableData: TimeInterval {
        get { time }
        set { time = newValue }
    }

    var body: some View {
        let frame = OpeningFrame.at(time, reduced: reduced)
        let height = width / RewatchWordmark.aspectRatio
        // Both pieces share the word's viewBox, so laid in the same frame they
        // overlay to the whole word.
        ZStack {
            WordmarkArt.re
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .offset(x: frame.reShift * width)
                // The clip is applied after the offset, so it stays put in the
                // word's frame while "Re" slides through it — and the frame
                // moves with the group below, not with "Re".
                .clipShape(OpeningCut())
            WordmarkArt.watch
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .offset(y: frame.watchRise * height)
                .opacity(frame.watchOpacity)
        }
        .foregroundStyle(Color.rewatch.wordmark)
        .frame(width: width, height: height)
        .offset(x: frame.groupShift * width)
        .opacity(frame.wordOpacity)
    }
}

/// Everything left of the slanted line just clear of the W's left edge. At
/// rest "Re" is wholly left of it, so the finished word is never cut; at the
/// start it is wholly right of it, so it is not there at all.
struct OpeningCut: Shape {
    func path(in rect: CGRect) -> Path {
        // The line, extended a quarter of the word's height past the top and
        // the bottom so the clip's own edge never lands on ink.
        func x(atHeightFraction fraction: Double) -> CGFloat {
            rect.minX + rect.width * (OpeningFrame.cutTop + (OpeningFrame.cutBottom - OpeningFrame.cutTop) * fraction)
        }
        let above = rect.minY - rect.height * 0.25
        let below = rect.maxY + rect.height * 0.25
        let farLeft = rect.minX - rect.width * 2
        var path = Path()
        path.move(to: CGPoint(x: farLeft, y: above))
        path.addLine(to: CGPoint(x: x(atHeightFraction: -0.25), y: above))
        path.addLine(to: CGPoint(x: x(atHeightFraction: 1.25), y: below))
        path.addLine(to: CGPoint(x: farLeft, y: below))
        path.closeSubpath()
        return path
    }
}

#Preview("Opening") {
    RewatchOpening(width: 176) {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .rewatchPageBackground()
}
