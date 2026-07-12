import Foundation

/// Discover-deck addition to `LocalSignals`, in its own file so the base
/// store stays untouched (feature tracks extend, never edit).
public extension LocalSignals {
    /// Removes one id from the Discover pass-list — the deck's undo.
    /// Rebuilt through the store's public API (reset, then re-record every
    /// kept id) so persistence stays owned by the store.
    func removeDiscoverPass(_ listingID: String) {
        guard hasPassed(listingID) else { return }
        let kept = discoverPassed.filter { $0 != listingID }
        resetDiscoverPasses()
        kept.forEach(recordDiscoverPass)
    }
}
