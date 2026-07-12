import CalibreDesign
import PassKit
// sheetCornerRadius is SPI-gated at the pinned stripe-ios 26.2.0 — the plain
// import doesn't compile. (Cross-track note: P6 added the @_spi form to
// unblock the shared build; remove when stripe-ios makes it public.)
@_spi(AppearanceAPIAdditionsPreview) import StripePaymentSheet
import SwiftUI
import UIKit

/// One place that shapes Stripe PaymentSheet like Calibre: warm cream/ink
/// (or their dark equivalents), Radius.control corners, Geist type. Both the
/// checkout total sheet and the offer-hold sheet use this.
enum CalibreStripe {
    static let merchantDisplayName = "Calibre"
    static let returnURL = "calibre://stripe-redirect"
    static let applePayMerchantID = "merchant.com.buycalibre.calibre"

    /// Builds the shared PaymentSheet configuration. Apple Pay is attached
    /// only when the device reports payment capability — a missing Apple Pay
    /// entitlement then degrades silently to cards instead of crashing or
    /// showing a dead button on devices that can't pay anyway.
    static func configuration(
        customerID: String?,
        customerSessionClientSecret: String?
    ) -> PaymentSheet.Configuration {
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = merchantDisplayName
        configuration.returnURL = returnURL
        configuration.style = .automatic
        configuration.appearance = appearance()

        if let customerID, let customerSessionClientSecret {
            configuration.customer = PaymentSheet.CustomerConfiguration(
                id: customerID,
                customerSessionClientSecret: customerSessionClientSecret
            )
        }

        if PKPaymentAuthorizationController.canMakePayments() {
            configuration.applePay = PaymentSheet.ApplePayConfiguration(
                merchantId: applePayMerchantID,
                merchantCountryCode: "US"
            )
        }

        return configuration
    }

    /// Maps the Calibre tokens onto PaymentSheet. Colors come straight from
    /// the palette (each already adapts light/dark); type is Geist via UIFont.
    private static func appearance() -> PaymentSheet.Appearance {
        var appearance = PaymentSheet.Appearance()

        appearance.cornerRadius = Radius.control
        appearance.sheetCornerRadius = Radius.overlay
        appearance.borderWidth = 1

        appearance.colors.primary = UIColor(Color.calibre.primary)
        appearance.colors.background = UIColor(Color.calibre.background)
        appearance.colors.componentBackground = UIColor(Color.calibre.card)
        appearance.colors.componentBorder = UIColor(Color.calibre.border)
        appearance.colors.componentDivider = UIColor(Color.calibre.border)
        appearance.colors.text = UIColor(Color.calibre.foreground)
        appearance.colors.textSecondary = UIColor(Color.calibre.mutedForeground)
        appearance.colors.componentText = UIColor(Color.calibre.foreground)
        appearance.colors.componentPlaceholderText = UIColor(Color.calibre.placeholder)
        appearance.colors.icon = UIColor(Color.calibre.mutedForeground)
        appearance.colors.danger = UIColor(Color.calibre.destructive)

        if let base = UIFont(name: "Geist-Regular", size: UIFont.labelFontSize) {
            appearance.font.base = base
        }

        appearance.primaryButton.backgroundColor = UIColor(Color.calibre.primary)
        appearance.primaryButton.textColor = UIColor(Color.calibre.primaryForeground)
        appearance.primaryButton.cornerRadius = Radius.control
        appearance.primaryButton.borderColor = UIColor(Color.calibre.border)
        appearance.primaryButton.successBackgroundColor = UIColor(Color.calibre.success)
        if let buttonFont = UIFont(name: "Geist-SemiBold", size: 15) {
            appearance.primaryButton.font = buttonFont
        }

        return appearance
    }

    /// Human copy for a PaymentSheet failure — Stripe's message when it has
    /// one, a warm fallback when it doesn't.
    static func failureMessage(for error: Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Your payment didn't go through. Please try again." : text
    }
}
