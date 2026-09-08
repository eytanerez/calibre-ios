import CalibreKit
import SwiftUI

/// A layer that can present the guest sign-in gate.
///
/// SwiftUI will not present a `.sheet` from a view that sits *underneath* a
/// `fullScreenCover`: UIKit refuses a second presentation from a controller
/// that already has one, and SwiftUI quietly defers the sheet instead of
/// dropping it. The gate therefore cannot live only on `RootView` — a guest
/// who tapped Save inside the deck got no sheet at all, and then met it
/// attached to nothing seconds later, the moment they closed the deck.
///
/// So the gate is presented by whichever layer is actually on screen, and
/// `AppRouter.gateLayer` names it.
enum ModalLayer {
    /// The tab shell, with no cover over it — `RootView` presents here.
    case root
    /// The swipe deck's full-screen cover, and anything pushed inside it.
    case deck
}

extension AppRouter {
    /// The layer the guest gate must be presented from right now.
    ///
    /// Checkout is deliberately absent. Its own guest gate calls `dismiss()`
    /// *before* `session.require` (see `CheckoutFlow.guestGate`), so by the
    /// time an intent exists that cover is already on its way out and the
    /// root is the layer that will be on screen.
    var gateLayer: ModalLayer {
        deckPresented ? .deck : .root
    }
}

extension View {
    /// Presents `AuthGateSheet` while a pending intent is waiting **and** this
    /// is the layer on screen.
    ///
    /// Install it on every modal layer that can raise a gate. Exactly one host
    /// is ever armed — two live hierarchies bound to the same intent would
    /// fight over the presentation.
    func authGate(for layer: ModalLayer) -> some View {
        modifier(AuthGateHost(layer: layer))
    }
}

private struct AuthGateHost: ViewModifier {
    let layer: ModalLayer

    @Environment(AuthSession.self) private var session
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        // Read the observable state HERE so `body` tracks it. Reads buried
        // inside a Binding's getter don't register with @Observable, and the
        // sheet would never present — the same trap `RootView` documents.
        let isArmed = router.gateLayer == layer && session.pendingIntent != nil

        content.sheet(isPresented: Binding(
            get: { isArmed },
            set: { presented in
                // A swipe-down means the guest declined; drop the intent so
                // the gate doesn't reappear the next time this layer is armed.
                guard !presented, isArmed else { return }
                session.pendingIntent = nil
            }
        )) {
            AuthGateSheet()
        }
    }
}
