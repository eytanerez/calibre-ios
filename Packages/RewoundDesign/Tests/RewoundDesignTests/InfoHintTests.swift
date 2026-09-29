import SwiftUI
import UIKit
import XCTest

@testable import RewoundDesign

/// The (?) is a glyph, and a glyph is what VoiceOver would say if nothing else
/// were given: "questionmark.circle, button" (measured: that is what this
/// suite reads with the label taken off). The label it is given instead
/// is the question it answers, so a screen-reader user knows what opening it
/// will explain. These read the label out of the real accessibility tree
/// SwiftUI vends, not out of a stored property.
@MainActor
final class InfoHintTests: XCTestCase {

    /// What VoiceOver can land on: its label and its traits, read while the
    /// view is still on screen.
    private struct Element {
        let accessibilityLabel: String?
        let accessibilityTraits: UIAccessibilityTraits
    }

    func testTheButtonIsNamedByTheQuestionItAnswers() throws {
        let elements = try accessibilityElements(of:
            HStack {
                Text("Reference")
                InfoHint("What is a reference number?", message: "The maker's model number.")
            }
        )

        let hint = try XCTUnwrap(
            elements.first { $0.accessibilityLabel == "What is a reference number?" },
            "No element is labelled with the question. Found: \(elements.compactMap(\.accessibilityLabel))"
        )
        XCTAssertTrue(hint.accessibilityTraits.contains(.button))
        // The symbol's own name must not be what is spoken. Without the label
        // SwiftUI reads out "questionmark.circle", its file name.
        XCTAssertFalse(elements.contains { ($0.accessibilityLabel ?? "").localizedCaseInsensitiveContains("questionmark") })
    }

    /// The label beside it stays its own element, read as it always was: the
    /// (?) is added to the row, not merged into its label.
    func testTheLabelBesideItIsReadSeparately() throws {
        let labels = try accessibilityElements(of:
            HStack {
                Text("Year")
                InfoHint("What does the year mean?", message: "The year the watch was made.")
            }
        ).compactMap(\.accessibilityLabel)

        XCTAssertEqual(labels, ["Year", "What does the year mean?"])
    }

    /// A custom explanation takes the same required question.
    func testACustomExplanationKeepsItsQuestion() throws {
        let labels = try accessibilityElements(of:
            InfoHint("How does grading work?") {
                VStack {
                    InfoHintText("Grade each part.")
                    Text("New")
                }
            }
        ).compactMap(\.accessibilityLabel)

        XCTAssertEqual(labels, ["How does grading work?"])
    }

    // MARK: - The accessibility tree

    /// SwiftUI builds its accessibility tree only for a process something
    /// assistive is reading, and a test process has no reader: without this,
    /// the hosting view vends no elements at all and every assertion below
    /// would be about an empty list. `_AXSSetAutomationEnabled` is the switch
    /// UI-automation tooling flips for the same reason; it is the simulator's
    /// own libAccessibility, reached at runtime, and only ever from a test.
    ///
    /// Returns the switch, so the caller can turn it back off: the rest of this
    /// suite measures layout and pixels, and runs as it always has.
    private func turnOnTheAccessibilityTree() throws -> (Int32) -> Void {
        let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
        guard let library = dlopen(root + "/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(library, "_AXSSetAutomationEnabled") else {
            throw XCTSkip("libAccessibility is not reachable here, so there is no tree to read.")
        }
        typealias SetEnabled = @convention(c) (Int32) -> Void
        let setEnabled = unsafeBitCast(symbol, to: SetEnabled.self)
        setEnabled(1)
        return { setEnabled($0) }
    }

    private func accessibilityElements(of view: some View) throws -> [Element] {
        let setAutomation = try turnOnTheAccessibilityTree()
        defer { setAutomation(0) }
        let host = UIHostingController(rootView: view.padding(40))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        var found: [NSObject] = []
        func visit(_ object: NSObject, depth: Int) {
            guard depth < 40 else { return }
            if object.isAccessibilityElement {
                found.append(object)
                return
            }
            if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
                elements.forEach { visit($0, depth: depth + 1) }
            } else if let view = object as? UIView {
                view.subviews.forEach { visit($0, depth: depth + 1) }
            }
        }
        visit(host.view, depth: 0)
        return found.map { Element(accessibilityLabel: $0.accessibilityLabel, accessibilityTraits: $0.accessibilityTraits) }
    }
}
