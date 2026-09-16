import RewoundDesign
import SwiftUI

// MARK: - Pushing onto the stack you are actually standing on
//
// Every tab is a `NavigationStack` bound to a path the router owns, and for a
// long time the only way to push was to append to that path. That works from a
// tab's root screen and nowhere else, because SwiftUI reconciles the stack
// against the path binding: a screen that arrived through a plain
// `NavigationLink { … }` or through one of the item-based destinations the
// browse track uses is not in the path, so the first append after it rebuilds
// the stack as root-plus-path and the screen the reader was standing on is
// gone. Back then lands on the tab root rather than where they came from —
// which is exactly the Orders → one order → Back → Account report.
//
// So a push is no longer addressed to the tab. Each level of the stack is
// hosted by a `routeStackNode()`, and everything standing at that level pushes
// through it, the same shape the browse screens already use. Back becomes an
// ordinary pop, and the system gestures — the iOS edge swipe and any
// interactive pop — agree with the button, because they are now popping the
// same stack the button pops rather than undoing a path the button rewrote.
//
// **The node is attached where a screen is presented, never inside the screen
// itself**, and that is not a style preference. A view's `@Environment` is
// resolved from the environment it was handed, so a modifier a screen applies
// inside its own `body` reaches its descendants and never the screen's own
// `routePush` property. A screen that hosted its own node therefore kept
// pushing to the tab, and Orders → one order → Back still landed on Account
// with the node in place: it compiled, it read correctly, and it did nothing.
// `RouteDestinationView` attaches it for every routed push; a plain
// `NavigationLink { … }` and an item destination have to attach it themselves.

extension EnvironmentValues {
    /// Pushes a `Route` onto the navigation stack the caller is standing on.
    ///
    /// The tab shell seeds this with the router's own push, so a call from a
    /// tab's root screen still appends to that tab's path. Whoever presents a
    /// screen above that root overrides it with `routeStackNode()`, so a call
    /// from deeper in the stack lands above the caller instead of replacing it.
    @Entry var routePush: (Route) -> Void = { _ in }
}

/// Attach to a screen **at the point it is presented** — the destination
/// builder of a `NavigationLink`, a `navigationDestination`, a cover's root.
/// It hosts that screen's level, so the screen and everything inside it pushes
/// above itself instead of rewriting the tab's path.
///
/// Attaching it inside the screen's own `body` does not work and is the shape
/// to watch for: the modifier lands on the screen's content, so its own
/// `@Environment(\.routePush)` — resolved from the environment it was handed —
/// still holds whatever the presenter passed down.
///
/// Nesting is harmless. A screen reached through `RouteDestinationView` already
/// sits inside a node, and a second one around it simply means the inner one —
/// the one standing at the reader's actual position — is the one in force.
private struct RouteStackNode: ViewModifier {
    @State private var pushed: Route?

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: $pushed) { route in
                RouteDestinationView(route: route)
            }
            .environment(\.routePush) { pushed = $0 }
    }
}

extension View {
    func routeStackNode() -> some View {
        modifier(RouteStackNode())
    }
}

// MARK: - Coming back from a jump between tabs

/// The way back out of a tab the reader was sent to rather than chose.
///
/// A tab switch has no stack to pop, so there is no system back button and the
/// edge swipe does nothing — without this the reader's only route home is the
/// tab bar, which drops them at a root instead of at the card they tapped.
/// Attach to a tab's root screen; it draws nothing at all when the reader
/// picked the tab themselves.
private struct TabJumpBack: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.toolbar {
            if let origin = router.tabOrigin {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.shared.play(.press)
                        router.returnFromJump()
                    } label: {
                        // Spelled out rather than a `Label`: a labeled toolbar
                        // item collapses to its icon here, and a bare chevron
                        // on a tab root reads as an ordinary back button
                        // instead of naming the place it returns to — which is
                        // the entire reason this button exists.
                        HStack(spacing: Space.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text(origin.title)
                        }
                    }
                    .tint(Color.rewound.primary)
                    .accessibilityLabel("Back to \(origin.title)")
                }
            }
        }
    }
}

extension View {
    func tabJumpBack() -> some View {
        modifier(TabJumpBack())
    }
}
