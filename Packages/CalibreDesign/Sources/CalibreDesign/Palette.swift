import SwiftUI
import UIKit

/// Semantic color tokens. Every color adapts to light (warm cream/chocolate)
/// and dark (warm near-black/copper) automatically via the system appearance.
/// Views must use these tokens — never raw hex values.
public extension Color {
    static let calibre = CalibrePalette()
}

public struct CalibrePalette: Sendable {
    /// Page background — warm cream / warm near-black.
    public let background = dynamic(light: 0xFBFAF7, dark: 0x141110)
    /// Primary text — warm ink / warm off-white.
    public let foreground = dynamic(light: 0x26211C, dark: 0xF3EFE9)
    /// Card and sheet surfaces — warm off-white, never pure white. Pure white
    /// sits under every card on every page and is the one cold pixel in a warm app.
    public let card = dynamic(light: 0xFEFCF8, dark: 0x1C1815)
    /// Brand action color — chocolate / copper. CTAs, links, focus.
    public let primary = dynamic(light: 0x7D5440, dark: 0xC79274)
    /// Pressed/darkened state of `primary`.
    public let primaryDeep = dynamic(light: 0x6A4636, dark: 0xB58063)
    /// Text/icons on `primary` fills.
    public let primaryForeground = dynamic(light: 0xFAF8F4, dark: 0x1B1512)
    /// Subtle fills, image wells, row hover.
    public let secondary = dynamic(light: 0xF3F1ED, dark: 0x211C18)
    /// Text on `secondary`.
    public let secondaryForeground = dynamic(light: 0x4A4036, dark: 0xD8CFC5)
    /// De-emphasized text. 4.48:1 on the cream page — a hair under AA, which
    /// is why Increase Contrast has somewhere to go.
    public let mutedForeground = dynamic(light: 0x7A736A, dark: 0xA79C8F, lightHC: 0x5C554E, darkHC: 0xACA295)
    /// Warm beige chips, icon tiles, callouts.
    public let accent = dynamic(light: 0xECE7E0, dark: 0x2A231D)
    /// Text on `accent`.
    public let accentForeground = dynamic(light: 0x574A3E, dark: 0xD9CCBE)
    /// Hairline borders and input strokes. The resting hairline is 1.25:1 —
    /// it is the card's edge, not a shape anyone has to find, until the reader
    /// says otherwise.
    public let border = dynamic(light: 0xE7E3DD, dark: 0x2C2620, lightHC: 0x95918B, darkHC: 0x69645E)
    /// Brighter borders — focused inputs, hovered cards.
    public let borderBright = dynamic(light: 0xD8D2C9, dark: 0x3A322A, lightHC: 0x817B74, darkHC: 0x7E7870)
    /// Placeholder text.
    public let placeholder = dynamic(light: 0x968F85, dark: 0x7A6F63, lightHC: 0x79726A, darkHC: 0x8A8074)
    /// Errors and destructive actions.
    public let destructive = dynamic(light: 0xB91C1C, dark: 0xD96B65)
    /// Success states.
    public let success = dynamic(light: 0x2C764F, dark: 0x58A87E)
    /// Shadow tint — warm ink, never cold black.
    public let shadowTint = dynamic(light: 0x26211C, dark: 0x000000)

    /// Sealing wax, and the lit edge where it stands proud of the paper. The
    /// wax seal is the one mark that does not take the page's ink, because wax
    /// arrives with a colour of its own — struck in chocolate it reads as a
    /// coin. Nothing outside that mark may use these: see
    /// CALIBRE_BY_HAND_CONTRACTS.md §17.
    public let wax = dynamic(light: 0x9E3B32, dark: 0xB4483D)
    public let waxHighlight = dynamic(light: 0xC0554A, dark: 0xD0655A)

    /// Light and dark, plus the pair Increase Contrast asks for.
    ///
    /// `lightHC`/`darkHC` fall back to the shipped values, so a token that
    /// omits them is the same color it has always been and a device with the
    /// setting off never reaches a new branch. The high-contrast pair is not
    /// a second palette either: each one is its own warm neutral blended
    /// toward the page's ink until it clears its target — 4.5:1 for text,
    /// 3:1 for a stroke someone has to find — so the app stays the same app,
    /// only firmer.
    private static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) -> Color {
        Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let wantsContrast = traits.accessibilityContrast == .high
            let value = switch (isDark, wantsContrast) {
            case (false, false): light
            case (false, true): lightHC ?? light
            case (true, false): dark
            case (true, true): darkHC ?? dark
            }
            return UIColor(hex: value)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
