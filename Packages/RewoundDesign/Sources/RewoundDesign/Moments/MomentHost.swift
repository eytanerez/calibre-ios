import SwiftUI
import UIKit

/// Which side of the app's own screen a film's layer is drawn on.
///
/// Two of the five put something *behind* the screen — the report grows out of
/// an envelope that has to be behind it, checkout rises over a ground that has
/// to be behind it — so a film is not simply an overlay.
enum MomentLayer {
    case under, over
}

/// What a film does to the app's screen while it runs.
///
/// This is the half of the choreography that cannot be drawn: the page itself
/// collapses, or is clipped down to a crop of its own top, or rides up from
/// under the edge. It is the reason a moment is different for every order
/// without anybody illustrating one.
struct MomentContentEffect {
    var scale: Double = 1
    var anchor: UnitPoint = .center
    var offset: CGSize = .zero
    var opacity: Double = 1
    /// A window on the screen, in screen coordinates. Everything outside it is
    /// cut away; nil leaves the screen whole.
    var window: CGRect?
    var windowCorner: CGFloat = 0

    static let none = MomentContentEffect()
}

/// A path already in the coordinates it is wanted in, as a `Shape` — for the
/// clips and outlines a film computes against the screen rather than against
/// whatever rectangle a shape happens to be handed.
struct MomentFixedPath: Shape {
    var path: Path
    func path(in _: CGRect) -> Path { path }
}

/// The window a film cuts in the app's own screen.
///
/// A nil window is a window bigger than anything that could be drawn through
/// it, rather than no clip at all. The clip has to be applied on every frame
/// of the app's life, film or no film: a `clipShape` that comes and goes is an
/// `if` around the whole app, and SwiftUI reads that as a different view —
/// see `MomentPlayer`.
private struct MomentWindow: Shape {
    var rect: CGRect?
    var corner: CGFloat

    func path(in bounds: CGRect) -> Path {
        guard let rect else {
            return Path(bounds.insetBy(dx: -100_000, dy: -100_000))
        }
        return Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
    }
}

extension View {
    func momentContentEffect(_ effect: MomentContentEffect) -> some View {
        scaleEffect(effect.scale, anchor: effect.anchor)
            .offset(effect.offset)
            .opacity(effect.opacity)
            // Outside the transform, so the rectangle is read in screen
            // coordinates rather than in the scaled screen's.
            .clipShape(MomentWindow(rect: effect.window, corner: effect.windowCorner))
    }
}

public extension View {
    /// Mounts the five moments over the whole app.
    ///
    /// It goes on the root and nowhere else: a film takes the entire window,
    /// outlives the navigation that happens underneath it, and — for two of
    /// the five — moves the app's own screen, which nothing below the root can
    /// do.
    func calibreMomentHost() -> some View {
        modifier(MomentHost())
    }
}

struct MomentHost: ViewModifier {
    private var moments = CalibreMoments.shared
    /// The screen a frozen film collapses, grabbed once before the freeze is
    /// allowed to draw anything — a capture taken with the film already on
    /// screen would photograph the film's own ground.
    @State private var frozenOutgoing: UIImage?

    /// The film on screen: whatever is running, or — when the launch arguments
    /// below ask for one — a single frozen frame of one, which is how a still
    /// of any beat gets looked at. A screenshot taken while a film runs
    /// catches whichever frame the shutter fell on, and a screenshot taken
    /// after it catches only the end.
    private var showing: (moment: CalibreMoment, time: TimeInterval, outgoing: UIImage?)? {
        if let frozen = Self.frozenByLaunchArgument {
            if frozen.moment.collapsesTheOutgoingScreen, frozenOutgoing == nil { return nil }
            return (frozen.moment, frozen.time, frozenOutgoing)
        }
        guard let running = moments.running else { return nil }
        return (running.moment, 0, running.outgoing)
    }

    func body(content: Content) -> some View {
        content
            .modifier(MomentPlayer(showing: showing))
            .task {
                guard let frozen = Self.frozenByLaunchArgument,
                      frozen.moment.collapsesTheOutgoingScreen else { return }
                try? await Task.sleep(for: .seconds(3))
                frozenOutgoing = CalibreMoments.screenAsItStands()
            }
    }

    /// `-calibreMoment orderPlaced -calibreMomentAt 1.3` freezes that film at
    /// that second, over whatever the app is showing, so a still of any beat
    /// can be captured and looked at — a screenshot of a film that is running
    /// catches whichever frame the shutter fell on.
    ///
    /// Gated on two launch arguments rather than on a build configuration: an
    /// installed iOS app has no way of being handed either of them, so the
    /// hook is unreachable off a developer's machine.
    static var frozenByLaunchArgument: (moment: CalibreMoment, time: TimeInterval)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let nameIndex = arguments.firstIndex(of: "-calibreMoment"),
              nameIndex + 1 < arguments.count,
              let moment = CalibreMoment(rawValue: arguments[nameIndex + 1]),
              let timeIndex = arguments.firstIndex(of: "-calibreMomentAt"),
              timeIndex + 1 < arguments.count,
              let time = TimeInterval(arguments[timeIndex + 1])
        else { return nil }
        return (moment, time)
    }
}

/// Runs the clock and lays the three layers up.
///
/// **The app's own screen is in one place, always.** This modifier used to
/// return `content` when nothing was playing and a staged copy of it when
/// something was — an `if` around the entire app. SwiftUI reads the two
/// branches as two different views, so starting a film destroyed the app's
/// whole view tree and built it again, and ending one did it a second time.
/// Everything that lives in that tree rather than in a store went with it: a
/// `NavigationStack`'s pushes, every screen's `@State`.
///
/// It surfaced in the Vault. Opening a watch Calibre authenticated plays a
/// film on arrival, the film re-parented the app, the pushed screen was gone
/// before it had drawn — and the Passport, which is a button on that screen,
/// could not be reached at all. It read as the tap doing nothing.
///
/// So there is no branch here. `content` takes the same modifiers on every
/// frame of the app's life; the layers, the ground and the clock are what come
/// and go, and each of them lives in a `background`, an `overlay` or a value,
/// none of which moves `content`.
private struct MomentPlayer: ViewModifier {
    let showing: (moment: CalibreMoment, time: TimeInterval, outgoing: UIImage?)?

    private var moments = CalibreMoments.shared

    /// The screen's own size, read from the view the transform is applied to
    /// so the layers and that transform cannot be given different answers. It
    /// is the same rectangle a `background`/`overlay` is handed, which is why
    /// those can measure it for themselves.
    @State private var stage: CGSize = .zero
    /// Seconds into the film that is running. Driven below.
    @State private var elapsed: TimeInterval = 0

    init(showing: (moment: CalibreMoment, time: TimeInterval, outgoing: UIImage?)?) {
        self.showing = showing
    }

    /// A frozen frame states its own second; a running film reads the clock.
    private var time: TimeInterval {
        MomentHost.frozenByLaunchArgument == nil ? elapsed : (showing?.time ?? 0)
    }

    func body(content: Content) -> some View {
        content
            .momentContentEffect(contentEffect)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { stage = $0 }
            .background { ground }
            .overlay { above }
            // The films are pure functions of elapsed seconds — see
            // MomentTiming — so this clock is the whole animation driver.
            // Keyed on the running film, so it starts with one, stops with it,
            // and does nothing at all the rest of the time.
            .task(id: moments.running?.id) { await runClock() }
    }

    /// Everything behind the app's screen: the page's own colour in the
    /// safe-area strips the layers do not reach, and the films that put
    /// something under the screen rather than over it.
    @ViewBuilder
    private var ground: some View {
        if let showing {
            ZStack {
                Color.calibre.background.ignoresSafeArea()
                GeometryReader { proxy in
                    layer(showing.moment, .under, at: time, stage: proxy.size, outgoing: showing.outgoing)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Everything over it, and the tap that cuts a film short.
    @ViewBuilder
    private var above: some View {
        if let showing {
            ZStack {
                GeometryReader { proxy in
                    layer(showing.moment, .over, at: time, stage: proxy.size, outgoing: showing.outgoing)
                }
                .allowsHitTesting(false)
                // A tap anywhere cuts straight to the destination, so nobody
                // is ever trapped watching a film.
                Color.clear.contentShape(Rectangle())
            }
            .accessibilityHidden(true)
            .onTapGesture { CalibreMoments.cut() }
        }
    }

    private var contentEffect: MomentContentEffect {
        guard let showing, stage.width > 0 else { return .none }
        return effect(showing.moment, at: time, stage: stage)
    }

    /// Walks `elapsed` forward for as long as a film is on screen.
    ///
    /// A frozen frame has no clock — it states the second it wants and holds
    /// it — and neither does an idle app: with nothing running this returns on
    /// its first line and never wakes again.
    private func runClock() async {
        guard MomentHost.frozenByLaunchArgument == nil else { return }
        guard let running = moments.running else {
            elapsed = 0
            return
        }
        while !Task.isCancelled {
            elapsed = Date().timeIntervalSince(running.startedAt)
            if elapsed >= running.moment.duration { return }
            try? await Task.sleep(nanoseconds: 8_000_000)
        }
    }

    private func effect(
        _ moment: CalibreMoment,
        at time: TimeInterval,
        stage: CGSize
    ) -> MomentContentEffect {
        switch moment {
        case .orderPlaced: OrderPlacedFilm.contentEffect(at: time, stage: stage)
        case .listingSubmitted: ListingSubmittedFilm.contentEffect(at: time, stage: stage)
        case .reportOpened: ReportOpenedFilm.contentEffect(at: time, stage: stage)
        case .vaultWatchOpened: VaultStampFilm.contentEffect(at: time, stage: stage)
        case .offerAccepted: OfferAcceptedFilm.contentEffect(at: time, stage: stage)
        }
    }

    @ViewBuilder
    private func layer(
        _ moment: CalibreMoment,
        _ side: MomentLayer,
        at time: TimeInterval,
        stage: CGSize,
        outgoing: UIImage?
    ) -> some View {
        switch moment {
        case .orderPlaced:
            OrderPlacedFilm(time: time, stage: stage, side: side, outgoing: outgoing)
        case .listingSubmitted:
            ListingSubmittedFilm(time: time, stage: stage, side: side, outgoing: outgoing)
        case .reportOpened:
            ReportOpenedFilm(time: time, stage: stage, side: side)
        case .vaultWatchOpened:
            VaultStampFilm(time: time, stage: stage, side: side)
        case .offerAccepted:
            OfferAcceptedFilm(time: time, stage: stage, side: side)
        }
    }
}
