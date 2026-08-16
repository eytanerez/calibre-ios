import CalibreDesign
import StripePaymentsUI
import SwiftUI
import UIKit

/// Stripe's own card control, wearing Calibre's type and colours.
///
/// Buyer checkout collects the card here rather than in PaymentSheet because
/// the card's funding has to be known *before* we take money: prepaid is
/// refused everywhere, debit only clears where the discount presentation
/// applies. Owning the field is what lets us create the PaymentMethod, ask
/// the server about it, and show a refusal inline while wire is still one tap
/// away. PaymentSheet is untouched everywhere else.
struct CardEntryField: UIViewRepresentable {
    /// The card as Stripe models it — nil until every field validates, so a
    /// caller can never build a PaymentMethod from a half-typed card.
    @Binding var cardParams: STPPaymentMethodCardParams?
    @Binding var isValid: Bool
    /// Fired the moment a *new* complete card is in the field. This is what
    /// lets the funding check run while wire is still one tap away, rather
    /// than after the buyer has committed to paying.
    var onComplete: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(field: self)
    }

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField()
        field.delegate = context.coordinator
        field.postalCodeEntryEnabled = true
        field.countryCode = "US"
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        style(field)
        return field
    }

    func updateUIView(_ field: STPPaymentCardTextField, context: Context) {
        // SwiftUI hands the coordinator a fresh struct on every update; the
        // bindings inside it are what the delegate writes through.
        context.coordinator.field = self
        style(field)
    }

    /// The control exposes a handful of knobs. Every one it does expose is
    /// pinned to the same tokens `CalibreStripe.appearance()` gives
    /// PaymentSheet, so the two never read as different products. The font
    /// goes through `UIFontMetrics` because this field is the one place in
    /// checkout where UIKit, not SwiftUI, owns the type.
    private func style(_ field: STPPaymentCardTextField) {
        field.backgroundColor = UIColor(Color.calibre.card)
        field.textColor = UIColor(Color.calibre.foreground)
        field.textErrorColor = UIColor(Color.calibre.destructive)
        field.placeholderColor = UIColor(Color.calibre.placeholder)
        field.cursorColor = UIColor(Color.calibre.primary)
        field.borderColor = UIColor(Color.calibre.border)
        field.borderWidth = 1
        field.cornerRadius = Radius.control
        if let geist = UIFont(name: "Geist-Regular", size: 17) {
            field.font = UIFontMetrics.default.scaledFont(for: geist)
        }
    }

    @MainActor
    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        var field: CardEntryField

        /// The card the bindings were last written from. The delegate fires on
        /// every keystroke, including ones that leave a complete card
        /// complete; comparing against this is what keeps `cardParams` (and
        /// therefore any validation hanging off it) from churning, and what
        /// makes `onComplete` fire once per distinct card rather than per
        /// character.
        private var lastSignature: String?

        init(field: CardEntryField) {
            self.field = field
        }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            let valid = textField.isValid
            if self.field.isValid != valid {
                self.field.isValid = valid
            }

            let params = valid ? textField.cardParams : nil
            let signature = params.map(Self.signature)
            guard signature != lastSignature else { return }
            lastSignature = signature

            self.field.cardParams = params
            if params != nil {
                self.field.onComplete()
            }
        }

        /// Identifies a card without keeping one around: the four values that
        /// make the PaymentMethod, and nothing that outlives this callback.
        private static func signature(_ params: STPPaymentMethodCardParams) -> String {
            [
                params.number ?? "",
                params.expMonth.map(String.init(describing:)) ?? "",
                params.expYear.map(String.init(describing:)) ?? "",
                params.cvc ?? "",
            ].joined(separator: "|")
        }
    }
}
