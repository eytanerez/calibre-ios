import SwiftUI
import UIKit

/// The five moments. Not marks — marks are 44pt drawings tucked beside a line
/// of text and over in half a second. These take the whole screen for one to
/// two and a half seconds and are the reason somebody screenshots the app.
///
/// The choreography, beat order, timings and easings are the approved
/// reference page's, ported rather than reinvented. Where this platform cannot
/// express a beat the same way it matches what happens and when; each film
/// says where it departed and why.
///
/// **They play every time.** These are not a tutorial somebody graduates from:
/// buying a watch is rare and expensive, and the moment should land on the
/// fifth order as much as on the first. There is no ledger here on purpose.
public enum RewoundMoment: String, Sendable, CaseIterable {
    /// After paying, on both order landings.
    case orderPlaced
    /// When a listing is sent for review.
    case listingSubmitted
    /// When the authentication report is opened.
    case reportOpened
    /// On opening a watch you own.
    case vaultWatchOpened
    /// When a seller accepts, before checkout.
    case offerAccepted

    /// The full run, in seconds — the last beat's end, taken from the film.
    /// Public because a surface that holds a screen open across a film has to
    /// hold it open for exactly as long as the film runs, and a second copy of
    /// that number in the caller is a number that goes stale.
    public var duration: TimeInterval {
        switch self {
        case .orderPlaced: OrderPlacedFilm.duration
        case .listingSubmitted: ListingSubmittedFilm.duration
        case .reportOpened: ReportOpenedFilm.duration
        case .vaultWatchOpened: VaultStampFilm.duration
        case .offerAccepted: OfferAcceptedFilm.duration
        }
    }

    /// Whether the film collapses the screen you were on into itself, which is
    /// the part of this that cannot be drawn in advance: the page that folds
    /// into the box is that order's real page, so the moment is different for
    /// every order without anybody illustrating one.
    var collapsesTheOutgoingScreen: Bool {
        self == .orderPlaced || self == .listingSubmitted
    }
}

/// Where a film needs to land on something the screen underneath already
/// draws, rather than on a coordinate.
public enum MomentAnchor: String, Sendable {
    /// The small verification stamp on a Vault watch. The big stamp lands
    /// exactly there — clear of the photograph and clear of the watch's name,
    /// which is the whole reason it is anchored and not placed.
    case vaultVerification
}

/// Starts a moment and holds the one that is running.
///
/// A film is started from the surface that caused it, immediately before the
/// navigation it introduces: `RewoundMoments.play(.orderPlaced)` grabs the
/// screen as it stands, and the app then routes underneath the film so the
/// destination is already there when the film clears.
@MainActor
@Observable
public final class RewoundMoments {
    public static let shared = RewoundMoments()

    /// The running film, or nil.
    private(set) var running: Running?

    /// Global frames of the things a film has to land on.
    private(set) var anchors: [MomentAnchor: CGRect] = [:]

    struct Running: Identifiable {
        let id = UUID()
        let moment: RewoundMoment
        /// The screen as it stood when the film started — the page that
        /// collapses. Nil for the films that do not collapse one.
        let outgoing: UIImage?
        let startedAt: Date
    }

    private var endTask: Task<Void, Never>?

    private init() {}

    /// Plays a moment over everything, once, now.
    ///
    /// Under Reduce Motion this does nothing at all, and doing nothing is the
    /// end state: every one of the five ends on the destination screen with
    /// the film gone, so declining the motion means arriving there directly.
    /// Never a blank frame and never a frozen middle.
    public static func play(_ moment: RewoundMoment) {
        shared.start(moment)
    }

    /// Cuts straight to the destination. A tap anywhere on a running film calls
    /// this, so nobody is ever trapped watching one.
    public static func cut() {
        shared.finish()
    }

    /// Records where something a film lands on ended up on screen.
    public static func setAnchor(_ anchor: MomentAnchor, frame: CGRect) {
        shared.anchors[anchor] = frame
    }

    func start(_ moment: RewoundMoment) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        endTask?.cancel()
        running = Running(
            moment: moment,
            outgoing: moment.collapsesTheOutgoingScreen ? Self.screenAsItStands() : nil,
            startedAt: Date()
        )
        let nanoseconds = UInt64(moment.duration * 1_000_000_000)
        endTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.running = nil
        }
    }

    func finish() {
        endTask?.cancel()
        endTask = nil
        running = nil
    }

    /// The window as the eye currently has it, as an image the film can shrink.
    ///
    /// `afterScreenUpdates: false` is deliberate: the caller is about to
    /// navigate, and rendering after the next update would capture the screen
    /// it is leaving *for* rather than the one it is leaving.
    static func screenAsItStands() -> UIImage? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window, window.bounds.width > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}

public extension View {
    /// Marks this view as the thing a film lands on.
    func rewoundMomentAnchor(_ anchor: MomentAnchor) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            RewoundMoments.setAnchor(anchor, frame: frame)
        }
    }
}
