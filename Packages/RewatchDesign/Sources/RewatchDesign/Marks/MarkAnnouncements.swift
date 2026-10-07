import SwiftUI

/// What this app session has already been told.
///
/// `trigger:` stops a mark replaying on a re-render, which is most of the
/// problem: the buyer's order screen refetches every sixty seconds and the
/// parcel must not set off again each time. It does not stop the other half —
/// a screen pushed twice in one session is two mounts, and a buyer who opens
/// their order four times in an afternoon should not watch the parcel fly off
/// four times.
///
/// So a mark on a transactional surface announces the **first** time this
/// session is shown a fact, and stands as that fact on every appearance after.
/// The key is the event, never the surface: an order that reaches `to_buyer` is
/// one announcement whether it is read from the order screen or from a push
/// notification that opened it.
///
/// Session-scoped and in memory, deliberately. It should survive a push and a
/// refetch; it should not need a migration, a cleanup sweep, or a decision
/// about what happens when somebody reinstalls.
@MainActor
public final class MarkAnnouncements {
    public static let shared = MarkAnnouncements()

    private var announced: Set<String> = []

    private init() {}

    /// True the first time this session is shown `key`, false afterwards.
    /// A nil key is a gate that is not met, and nothing is recorded for one.
    public func claim(_ key: String?) -> Bool {
        guard let key else { return false }
        return announced.insert(key).inserted
    }

}

public extension View {
    /// Hold this mark at its end state — stamped, sealed, packed, filled —
    /// instead of playing its timeline.
    ///
    /// It reaches the drawing through `MarkStillness`, which ORs it with the
    /// two Reduce Motion signals — so this can only ever add a reason to hold
    /// still. Passing `false` cannot start motion for somebody who has Reduce
    /// Motion switched on.
    ///
    /// Apply it to the mark and to nothing else — every other view under it
    /// would be told motion is unwelcome when nobody said so.
    @MainActor
    func markStill(_ still: Bool) -> some View {
        environment(\.markStillnessRequested, still)
    }

    /// This mark announces `key` the first time this session is shown it, and
    /// stands as that fact on every appearance after. Pass nil while the gate
    /// is not met.
    ///
    /// Use it beside `trigger:`, not instead of it: `trigger:` is what stops a
    /// re-render replaying the mark, and this is what stops a second push of
    /// the same screen replaying it.
    @MainActor
    func markAnnounces(_ key: String?) -> some View {
        modifier(MarkAnnouncement(key: key))
    }
}

private struct MarkAnnouncement: ViewModifier {
    let key: String?
    /// Starts still, so the first frame is the fact rather than an empty one.
    /// The claim lands a frame later and, if this session has not been shown
    /// the fact, flips the mark into its timeline.
    @State private var announces = false

    func body(content: Content) -> some View {
        content
            .markStill(!announces)
            .onAppear { announces = MarkAnnouncements.shared.claim(key) }
            .onChange(of: key) { _, next in announces = MarkAnnouncements.shared.claim(next) }
    }
}

/// A surface asking one mark to stand as its fact rather than announce it.
///
/// Kept separate from `accessibilityReduceMotion`, which SwiftUI does not let
/// anybody write: that value is the person's own setting and it is not this
/// app's to spoof. `MarkStillness` reads both and either one is a yes.
/// Public only because `markStill(_:)` is: set it through that modifier, which
/// is where the rule about where a mark may be held still is written down.
public struct MarkStillnessRequestedKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var markStillnessRequested: Bool {
        get { self[MarkStillnessRequestedKey.self] }
        set { self[MarkStillnessRequestedKey.self] = newValue }
    }
}
