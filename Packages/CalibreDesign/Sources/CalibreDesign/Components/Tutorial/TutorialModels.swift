import SwiftUI

/// A first-run, hands-on tutorial: a short sequence of coach steps drawn
/// directly on the real screen. Each step spotlights a real control and,
/// where the action is safe to rehearse, waits for the user to actually
/// perform it before advancing. Lessons show once per screen and never
/// return — completion is remembered across app updates by ``TutorialLedger``.
///
/// A screen owns a ``TutorialController`` built from `[TutorialStep]`, tags
/// its controls with ``SwiftUI/View/tutorialAnchor(_:)``, hosts the layer with
/// ``SwiftUI/View/tutorialOverlay(_:)``, and calls `controller.fire(_:)` from
/// its existing gesture handlers so a real swipe/tap moves the lesson forward.

/// How a step advances.
public enum TutorialAdvance: Equatable, Sendable {
    /// Explanatory only. The target is spotlit; the user taps "Got it"
    /// (or anywhere on the dimmed area) to continue. Use for concepts and
    /// for committal actions we must not perform during a lesson
    /// (send offer, place order, submit listing).
    case tapToContinue

    /// Hands-on. The user must actually perform the action on the real
    /// control; the host screen calls `controller.fire(event)` the moment it
    /// happens. Use only for safe / reversible actions (a swipe with Undo,
    /// opening a sheet, tapping a filter, taking a photo).
    case perform(event: String)
}

/// The looping hint drawn over the spotlit control to show what to do.
public enum TutorialHint: Equatable, Sendable {
    case none
    case tap
    case swipe(TutorialEdge)
    case drag(TutorialEdge)
    case longPress
    case type
}

/// Direction for swipe / drag hints.
public enum TutorialEdge: Sendable, Equatable {
    case left, right, up, down

    var unit: CGSize {
        switch self {
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        case .up: CGSize(width: 0, height: -1)
        case .down: CGSize(width: 0, height: 1)
        }
    }

    var arrowSymbol: String {
        switch self {
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .up: "arrow.up"
        case .down: "arrow.down"
        }
    }
}

/// The silhouette cut out of the dim so the real control shows through.
public enum TutorialCutout: Equatable, Sendable {
    case roundedRect(CGFloat)
    case capsule
    case circle
    case rect
}

/// One coaching step.
public struct TutorialStep: Identifiable, Sendable {
    public let id: String
    /// Matches a `.tutorialAnchor(_:)` id on the target control. `nil`
    /// centers the coach card with no spotlight — a plain concept beat.
    public let anchor: String?
    public let title: String
    public let message: String
    public let advance: TutorialAdvance
    public let hint: TutorialHint
    public let cutout: TutorialCutout
    /// Extra breathing room added around the target rect before cutting.
    public let cutoutPadding: CGFloat
    /// Short imperative shown under the copy on a `.perform` step,
    /// e.g. "Swipe right to save". Ignored for `.tapToContinue`.
    public let actionPrompt: String?

    public init(
        id: String,
        anchor: String? = nil,
        title: String,
        message: String,
        advance: TutorialAdvance = .tapToContinue,
        hint: TutorialHint = .none,
        cutout: TutorialCutout = .roundedRect(Radius.card),
        cutoutPadding: CGFloat = Space.s,
        actionPrompt: String? = nil
    ) {
        self.id = id
        self.anchor = anchor
        self.title = title
        self.message = message
        self.advance = advance
        self.hint = hint
        self.cutout = cutout
        self.cutoutPadding = cutoutPadding
        self.actionPrompt = actionPrompt
    }
}
