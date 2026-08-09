import SwiftUI
import UIKit

/// Tap anywhere outside the focused input to dismiss the keyboard.
///
/// SwiftUI has no first-class "tap off to resign" hook, so this installs a
/// single recogniser on the window. `cancelsTouchesInView = false` means the
/// tap is *observed*, never consumed — every button, row and gesture beneath
/// keeps behaving exactly as before.
///
/// The tricky part is not stealing focus from the field the user just tapped.
/// Two guards handle that: the tap is ignored when it lands inside the current
/// first responder, and when it hit-tests to any other text input.
public extension View {
    /// Install once, at the root of the app.
    func dismissesKeyboardOnBackgroundTap() -> some View {
        background(KeyboardDismissInstaller().allowsHitTesting(false))
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // The window is nil on the first layout pass; retry on the next runloop.
        DispatchQueue.main.async {
            guard let window = uiView.window else { return }
            context.coordinator.attach(to: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var attached: UIWindow?

        func attach(to window: UIWindow) {
            guard attached !== window else { return }
            attached = window
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let window = attached else { return }
            // Nothing focused — nothing to dismiss.
            guard let responder = window.firstResponderInHierarchy else { return }

            let point = recognizer.location(in: window)

            // Tapped the field that already has focus: leave it alone.
            let responderFrame = responder.convert(responder.bounds, to: window)
            if responderFrame.insetBy(dx: -8, dy: -8).contains(point) { return }

            // Tapped a different input: let it take focus rather than closing
            // the keyboard out from under it.
            if let hit = window.hitTest(point, with: nil), hit.isTextInputLike { return }

            window.endEditing(true)
        }

        func gestureRecognizer(
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
        ) -> Bool { true }
    }
}

private extension UIView {
    var firstResponderInHierarchy: UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let found = subview.firstResponderInHierarchy { return found }
        }
        return nil
    }

    /// True for the view itself or any ancestor being a text input. Covers
    /// SwiftUI's private backing views by name as well as plain UIKit ones.
    var isTextInputLike: Bool {
        var node: UIView? = self
        while let current = node {
            if current is UITextInput { return true }
            let name = String(describing: type(of: current))
            if name.contains("TextField") || name.contains("TextView")
                || name.contains("TextEditor") || name.contains("TextInput") {
                return true
            }
            node = current.superview
        }
        return false
    }
}
