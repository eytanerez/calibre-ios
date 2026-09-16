import SwiftUI

/// The consumer Journal is retired — Bites replaced it.
///
/// This destination still resolves rather than going missing, because things
/// already point at it: the `calibre://journal` and `/journal` links, a push
/// notification the desk sent before the change, and a home-feed module's
/// route. It lands on the library that took the Journal's place.
///
/// The screen it used to be — an index of long-form stories with its own hero
/// imagery — is gone rather than hidden. Keeping it behind an unreachable
/// route would leave a second editorial shelf in the app that nothing puts
/// anything on.
struct JournalScreen: View {
    var body: some View {
        BitesArchiveScreen()
    }
}
