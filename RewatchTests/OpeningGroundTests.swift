import RewatchDesign
import SwiftUI
import UIKit
import XCTest

/// The opening's hand-off from the system launch screen is seamless only if
/// the boot screen's ground is the launch screen's colour exactly. The launch
/// screen paints the `LaunchBackground` colour set (project.yml
/// `UILaunchScreen.UIColorName`); the boot screen paints `Color.rewatch
/// .background`. Two copies of one colour, in two places, so this holds them
/// to each other in both appearances.
final class OpeningGroundTests: XCTestCase {
    private func components(_ color: UIColor, _ style: UIUserInterfaceStyle) -> [Int] {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha].map { Int(($0 * 255).rounded()) }
    }

    func testTheBootGroundIsTheLaunchScreensColour() throws {
        let launch = try XCTUnwrap(UIColor(named: "LaunchBackground", in: .main, compatibleWith: nil))
        let ground = UIColor(Color.rewatch.background)

        XCTAssertEqual(components(launch, .light), [0xFB, 0xFA, 0xF7, 255])
        XCTAssertEqual(components(launch, .dark), [0x0E, 0x0D, 0x0B, 255])
        XCTAssertEqual(components(ground, .light), components(launch, .light))
        XCTAssertEqual(components(ground, .dark), components(launch, .dark))
    }
}
