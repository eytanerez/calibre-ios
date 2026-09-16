import CalibreKit
import SwiftUI

/// Live input formatting, applied at the field rather than inside
/// `CalibreTextField`.
///
/// CALIBRE_FINAL_PUSH_CONTRACTS.md §6 asks that money and US phone numbers
/// format *as the user types*, on the site, the admin and both apps. The
/// formatters themselves live in `CalibreKit` (`MoneyInputFormatter`,
/// `PhoneFormatter`) so the rules are stated once; these two modifiers are the
/// only thing a screen has to remember.
///
/// They deliberately do not live on `CalibreFieldKind`: that enum is in
/// `CalibreDesign`, which is a UI-only package with no dependency on
/// `CalibreKit`, and giving the design system an opinion about how a number is
/// punctuated would put the rule in two places. `SSNStepSheet` already
/// formatted at the call site the same way, and this is that pattern named.
///
/// Each writes back only when the formatted string differs from what is there,
/// so a `.onChange` cannot loop.
extension View {
    /// `12400` → `12,400` under the caret. Grouping only; the currency symbol
    /// stays in the field's label or accessory, where it does not have to be
    /// typed around.
    func moneyFormatted(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let formatted = MoneyInputFormatter.format(newValue)
            if formatted != newValue {
                text.wrappedValue = formatted
            }
        }
    }

    /// `4155550134` → `(415) 555-0134` under the caret. US only (§7).
    func phoneFormatted(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let formatted = PhoneFormatter.format(newValue)
            if formatted != newValue {
                text.wrappedValue = formatted
            }
        }
    }
}
