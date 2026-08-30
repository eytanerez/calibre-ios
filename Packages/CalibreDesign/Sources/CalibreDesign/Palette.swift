import SwiftUI
import UIKit

/// Semantic color tokens. Every color adapts to light (warm cream/chocolate)
/// and dark (neutral near-black, with copper as the only warm voice)
/// automatically via the system appearance. Views must use these tokens —
/// never raw hex values.
///
/// The dark ramp is the admin console's, ported value for value by
/// CALIBRE_FINAL_PUSH_CONTRACTS.md §3. It used to be a warm-brown ramp
/// mirroring this file, and it read brown: at near-black luminance a warm
/// tint has nothing to be warm *against*, so the whole page took the hue
/// instead of the copper doing it alone. Copper, wax and waxHighlight keep
/// their own colour and are not swept into the neutral ramp.
public extension Color {
    static let calibre = CalibrePalette()
}

public struct CalibrePalette: Sendable {
    /// Page background — warm cream / neutral near-black (`--bg`).
    public let background = dynamic(light: 0xFBFAF7, dark: 0x0E0D0B)
    /// Primary text — warm ink / off-white (`--ink`). 14.96:1 on the dark card.
    public let foreground = dynamic(light: 0x26211C, dark: 0xEDE7DC)
    /// Card and sheet surfaces — warm off-white, never pure white. Pure white
    /// sits under every card on every page and is the one cold pixel in a warm app.
    public let card = dynamic(light: 0xFEFCF8, dark: 0x151412)
    /// Brand action color — chocolate / copper. CTAs, links, focus.
    public let primary = dynamic(light: 0x7D5440, dark: 0xC79274)
    /// Pressed/darkened state of `primary`.
    public let primaryDeep = dynamic(light: 0x6A4636, dark: 0xB58063)
    /// Text/icons on `primary` fills.
    public let primaryForeground = dynamic(light: 0xFAF8F4, dark: 0x1B1512)
    /// Subtle fills, image wells, row hover. Dark is the same `--surface` the
    /// card is: the admin separates those two with a hairline, not a step.
    public let secondary = dynamic(light: 0xF3F1ED, dark: 0x151412)
    /// Text on `secondary` (`--ink-2`). 8.02:1 on the dark card.
    public let secondaryForeground = dynamic(light: 0x4A4036, dark: 0xB3AA9C)
    /// De-emphasized text (`--ink-3`). 4.48:1 on the cream page — a hair under
    /// AA, which is why Increase Contrast has somewhere to go. Dark is 5.12:1
    /// on the page and 4.62:1 on `accent`, the darkest ground it lands on; the
    /// HC pair takes both arms to ~7:1.
    public let mutedForeground = dynamic(light: 0x7A736A, dark: 0x8A8275, lightHC: 0x5C554E, darkHC: 0xAAA396)
    /// Chips, icon tiles, callouts — the raised surface (`--raise`).
    public let accent = dynamic(light: 0xECE7E0, dark: 0x1B1917)
    /// Text on `accent`. Deliberately left on its old value: §3's table names
    /// twelve dark tokens to move and this is not one of them, and collapsing
    /// it into `--ink-2` would erase the step between text-on-accent and
    /// text-on-secondary. It reads 11.13:1 on the new raise — brighter than it
    /// was, and the one dark token still carrying a beige cast.
    public let accentForeground = dynamic(light: 0x574A3E, dark: 0xD9CCBE)
    /// Hairline borders and input strokes. The resting hairline is 1.25:1 —
    /// it is the card's edge, not a shape anyone has to find, until the reader
    /// says otherwise.
    /// (`--line`.) The dark hairline is 1.21:1 on the card; HC takes it to
    /// 3.02:1 on `accent`, the darkest ground it is drawn against.
    public let border = dynamic(light: 0xE7E3DD, dark: 0x282521, lightHC: 0x95918B, darkHC: 0x69655E)
    /// Brighter borders — focused inputs, hovered cards (`--line-strong`).
    /// HC: 4.00:1 on `accent`, 4.20:1 on the card it usually rings.
    public let borderBright = dynamic(light: 0xD8D2C9, dark: 0x332F2A, lightHC: 0x817B74, darkHC: 0x7D7870)
    /// Placeholder text. Inputs are filled with `card`, so that is the ground
    /// it is measured on: 3.75:1 base, 4.75:1 under Increase Contrast — and
    /// 4.52:1 on `accent`, the worst ground in the app, so it clears AA there
    /// too. Unchanged by the ramp move: the recomputation against the new,
    /// darker grounds landed on the value it already had.
    public let placeholder = dynamic(light: 0x968F85, dark: 0x7A6F63, lightHC: 0x79726A, darkHC: 0x8A8074)
    /// Errors and destructive actions (`--down`). 5.64:1 on the dark card.
    public let destructive = dynamic(light: 0xB91C1C, dark: 0xE06B5F)
    /// Success states (`--up`). 6.78:1 on the dark card.
    public let success = dynamic(light: 0x2C764F, dark: 0x4CAF7D)

    /// Pending, expiring, waiting-on-you — the state that is neither good news
    /// nor bad. Without it every surface that needed one invented its own amber
    /// inline, which is how `StatusBadge.Tone.warning` ended up the only tone in
    /// the app that ignored dark mode. 5.23:1 on the cream page and 5.33:1 on
    /// the light card; 9.58:1 on the dark page and 9.08:1 on the dark card. It
    /// clears AA on every ground in both themes at its base value, so — like
    /// `success` and `destructive` — it is given no Increase Contrast pair.
    public let warning = dynamic(light: 0x8A6220, dark: 0xDFAE5E)
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
