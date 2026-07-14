import SwiftUI

/// Drives one screen's hands-on lesson: which step is showing, when to
/// advance, and when the whole thing is done for good.
///
/// A screen creates one as `@State` from its step list, hosts it with
/// ``SwiftUI/View/tutorialOverlay(_:)``, kicks it off in `.onAppear` with
/// ``startIfNeeded()``, and calls ``fire(_:)`` from its real gesture handlers
/// so performing the action advances the lesson.
@MainActor
@Observable
public final class TutorialController {
    public let id: String
    private let steps: [TutorialStep]
    private let ledger: TutorialLedger

    /// Index of the visible step; `nil` when the lesson isn't showing.
    public private(set) var activeIndex: Int?

    public init(id: String, steps: [TutorialStep], ledger: TutorialLedger = .shared) {
        self.id = id
        self.steps = steps
        self.ledger = ledger
    }

    public var isActive: Bool { activeIndex != nil }

    public var currentStep: TutorialStep? {
        guard let index = activeIndex, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    /// 1-based position and total, for the "Tip 2 of 4" eyebrow.
    public var position: (step: Int, total: Int)? {
        guard let index = activeIndex else { return nil }
        return (index + 1, steps.count)
    }

    /// Starts the lesson unless it has already been completed. Safe to call
    /// from `.onAppear` on every appearance — it no-ops once seen.
    public func startIfNeeded() {
        guard activeIndex == nil, !steps.isEmpty, !ledger.hasCompleted(id) else { return }
        withAnimation(Motion.easeMedium) { activeIndex = 0 }
        Haptics.shared.play(.selection)
    }

    /// The host reports that a real, hands-on action just completed. Advances
    /// only if the current step is waiting for exactly this event, so screens
    /// can fire freely from handlers that also run outside the lesson.
    public func fire(_ event: String) {
        guard case .perform(let expected)? = currentStep?.advance, expected == event else { return }
        goForward()
    }

    /// Advances a `.tapToContinue` step (the "Got it" / "Next" button, or a
    /// tap on the dimmed area).
    public func advance() {
        guard currentStep?.advance == .tapToContinue else { return }
        goForward()
    }

    /// Ends the lesson now and remembers it, so it never returns.
    public func skip() {
        finish()
    }

    private func goForward() {
        guard let index = activeIndex else { return }
        let next = index + 1
        if steps.indices.contains(next) {
            Haptics.shared.play(.selection)
            withAnimation(Motion.easeMedium) { activeIndex = next }
        } else {
            Haptics.shared.play(.success)
            finish()
        }
    }

    private func finish() {
        ledger.markCompleted(id)
        withAnimation(Motion.easeMedium) { activeIndex = nil }
    }

    #if DEBUG
    /// Forgets this lesson and immediately replays it — for previews and QA.
    public func restart() {
        ledger.reset(id)
        activeIndex = nil
        startIfNeeded()
    }
    #endif
}
