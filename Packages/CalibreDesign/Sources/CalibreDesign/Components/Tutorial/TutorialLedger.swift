import Foundation

/// Remembers which first-run tutorials the user has finished so they never
/// return. Backed by `UserDefaults`, which lives in the app container and
/// survives every app **update** — the requirement is that a completed
/// lesson stays completed forever. Keys are stable per screen and contain
/// **no app/marketing version**, so shipping a new build never re-shows a
/// tutorial. (A fresh install or a brand-new device starts empty, by design.)
/// `UserDefaults` is internally thread-safe and the only stored state is an
/// immutable reference, so the ledger is safe to touch from any actor
/// (including `App.init`, before the main actor is established).
public final class TutorialLedger: @unchecked Sendable {
    public static let shared = TutorialLedger()

    private let defaults: UserDefaults
    /// Schema version of the ledger itself — bump only if the tutorial
    /// *format* changes and every lesson must genuinely be re-taught. This is
    /// deliberately independent of the app version.
    private static let keyPrefix = "tutorial.seen.v1."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Launch-argument override so UI tests and screenshot runs are never
    /// blocked by a coach overlay. When present, every lesson reports as
    /// already completed and nothing draws.
    public static var isDisabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-disableTutorials")
    }

    private func key(_ id: String) -> String { Self.keyPrefix + id }

    /// True once the lesson has been finished or skipped (or globally
    /// disabled for testing).
    public func hasCompleted(_ id: String) -> Bool {
        if Self.isDisabled { return true }
        return defaults.bool(forKey: key(id))
    }

    /// Marks a lesson done. Idempotent.
    public func markCompleted(_ id: String) {
        defaults.set(true, forKey: key(id))
    }

    /// Clears a single lesson so it shows again on next appearance.
    public func reset(_ id: String) {
        defaults.removeObject(forKey: key(id))
    }

    /// Clears every remembered lesson — used by the QA "Replay tips" control
    /// and the `-resetTutorials` launch hook.
    public func resetAll() {
        for storedKey in defaults.dictionaryRepresentation().keys
        where storedKey.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: storedKey)
        }
    }
}
