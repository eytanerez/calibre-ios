import SwiftUI

/// Brand motion. Ease-out only — motion confirms state change, never performs.
/// No springs, no bounce, transform + opacity only.
public enum Motion {
    /// Hover/press feedback.
    public static let fast: TimeInterval = 0.16
    /// Menus, sheets, toasts.
    public static let medium: TimeInterval = 0.22
    /// Entrances and hero moments.
    public static let slow: TimeInterval = 0.42

    /// The brand curve: cubic-bezier(0.22, 1, 0.36, 1).
    public static func ease(_ duration: TimeInterval) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    public static var easeFast: Animation { ease(fast) }
    public static var easeMedium: Animation { ease(medium) }
    public static var easeSlow: Animation { ease(slow) }

    /// Pressed-control scale — global press affordance.
    public static let pressScale: CGFloat = 0.97

    /// Staggered grid cascade: 30ms per item, tail capped at item 7.
    public static func cascadeDelay(index: Int) -> TimeInterval {
        Double(min(index, 7)) * 0.03
    }
}

/// Fade-up entrance used by feed rows and grids. Respects Reduce Motion
/// (falls back to a plain crossfade — content is never hidden behind motion).
public struct FadeUpEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    let index: Int

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                withAnimation(Motion.ease(0.36).delay(Motion.cascadeDelay(index: index))) {
                    shown = true
                }
            }
    }
}

public extension View {
    func fadeUpEntrance(index: Int = 0) -> some View {
        modifier(FadeUpEntrance(index: index))
    }
}
