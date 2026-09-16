import SwiftUI
import UIKit

public extension View {
    /// Switch sibling pages with a direction-locked swipe. Horizontal rails,
    /// text selection, native row actions and the leading back edge keep their
    /// own gestures. A selection haptic fires only when the page changes.
    func rewoundPageSwipe<Selection: Hashable>(
        selection: Binding<Selection>, values: [Selection]
    ) -> some View {
        modifier(PageSwipeModifier(selection: selection, values: values))
    }
}

private struct PageSwipeModifier<Selection: Hashable>: ViewModifier {
    @Binding var selection: Selection
    let values: [Selection]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    func body(content: Content) -> some View {
        content.gesture(PageSwipeGesture { translation, velocity in
            guard let index = values.firstIndex(of: selection),
                  let next = PageSwipeDecision.destination(
                    index: index, count: values.count,
                    translation: layoutDirection == .rightToLeft ? -translation : translation,
                    velocity: layoutDirection == .rightToLeft ? -velocity : velocity
                  ) else { return }
            Haptics.shared.play(.selection)
            withAnimation(reduceMotion ? nil : Motion.ease(0.18)) {
                selection = values[next]
            }
        })
    }
}

enum PageSwipeDecision {
    static func isHorizontal(_ delta: CGPoint) -> Bool {
        abs(delta.x) > abs(delta.y) * 1.25
    }

    static func destination(index: Int, count: Int, translation: CGFloat, velocity: CGFloat) -> Int? {
        guard abs(translation) >= 52 || (abs(translation) >= 18 && abs(velocity) >= 450) else { return nil }
        let next = index + (translation < 0 ? 1 : -1)
        return (0..<count).contains(next) ? next : nil
    }
}

private struct PageSwipeGesture: UIGestureRecognizerRepresentable {
    let change: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> AxisLockedPagePan {
        let pan = AxisLockedPagePan()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: AxisLockedPagePan, context: Context) {
        guard pan.state == .ended else { return }
        change(pan.translation(in: pan.view).x, pan.velocity(in: pan.view).x)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window = recognizer.view?.window else { return false }
            let point = touch.location(in: window)
            guard point.x >= 24, point.x <= window.bounds.width - 24 else { return false }
            var view = touch.view
            while let current = view, current !== recognizer.view {
                if current is UITextInput || current is UISlider || current is UISwitch { return false }
                if let scroll = current as? UIScrollView,
                   scroll.isScrollEnabled,
                   scroll.contentSize.width > scroll.bounds.width + 2 { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool {
            String(describing: type(of: other)).contains("SwipeAction")
        }
    }
}

private final class AxisLockedPagePan: UIPanGestureRecognizer {
    private var origin: CGPoint?
    private var judged = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        origin = touches.first?.location(in: view)
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !judged, let origin, let point = touches.first?.location(in: view) {
            let delta = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
            if hypot(delta.x, delta.y) >= 8 {
                judged = true
                if !PageSwipeDecision.isHorizontal(delta) {
                    state = .failed
                    return
                }
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        origin = nil
        judged = false
    }
}
