import SwiftUI
import UIKit
import XCTest

@testable import RewoundDesign

/// `WrapLayout` starts a new line rather than squeezing or clipping, and never
/// lets one child run wider than the line.
final class WrapLayoutTests: XCTestCase {

    @MainActor
    private func size(width: CGFloat, @ViewBuilder content: () -> some View) -> CGSize {
        let host = UIHostingController(rootView: WrapLayout(spacing: 10, lineSpacing: 5) { content() })
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    @MainActor
    func testItemsThatFitShareOneLine() {
        let fitted = size(width: 200) {
            Color.red.frame(width: 60, height: 20)
            Color.red.frame(width: 60, height: 20)
        }
        XCTAssertEqual(fitted.height, 20, accuracy: 0.5)
    }

    @MainActor
    func testTheNextItemStartsANewLineWhenItWouldNotFit() {
        let wrapped = size(width: 150) {
            Color.red.frame(width: 60, height: 20)
            Color.red.frame(width: 60, height: 20)
            Color.red.frame(width: 60, height: 20)
        }
        // 60 + 10 + 60 = 130 fits; the third goes to a second line.
        XCTAssertEqual(wrapped.height, 20 + 5 + 20, accuracy: 0.5)
        XCTAssertLessThanOrEqual(wrapped.width, 150)
    }

    /// A phrase wider than the line gets the line to itself and wraps inside
    /// it, rather than running off the edge.
    @MainActor
    func testAnItemWiderThanTheLineWrapsWithinIt() {
        let long = size(width: 120) {
            Text("Some parts replaced, and a good deal more besides")
                .font(.system(size: 13))
        }
        XCTAssertLessThanOrEqual(long.width, 120)
        XCTAssertGreaterThan(long.height, 20, "the phrase should have wrapped onto more than one line")
    }
}
