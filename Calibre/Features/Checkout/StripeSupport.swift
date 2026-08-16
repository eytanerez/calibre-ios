import CalibreDesign
import PassKit
import StripePayments
// sheetCornerRadius is SPI-gated at the pinned stripe-ios 26.2.0 — the plain
// import doesn't compile. (Cross-track note: P6 added the @_spi form to
// unblock the shared build; remove when stripe-ios makes it public.)
@_spi(AppearanceAPIAdditionsPreview) import StripePaymentSheet
import SwiftUI
import UIKit

/// One place that shapes Stripe PaymentSheet like Calibre: warm cream/ink
/// (or their dark equivalents), Radius.control corners, Geist type.
///
/// PaymentSheet still drives offer holds and seller label purchases. Buyer
/// card checkout collects the card itself (see `CardEntryField`) because the
/// card's funding has to be known before any money moves — so the pieces the
/// hand-rolled path needs (the frontmost presenter, an authentication
/// context, the Apple Pay request) live here too, beside the merchant id and
/// the entitlement gate they share.
enum CalibreStripe {
    static let merchantDisplayName = "Calibre"
    static let returnURL = "calibre://stripe-redirect"
    static let applePayMerchantID = "merchant.com.buycalibre.calibre"

    /// Whether this build carries the Apple Pay entitlement, set by
    /// `APPLE_PAY_ENABLED` in the build config alongside the entitlement itself.
    ///
    /// Device capability alone isn't enough to decide. A sideloaded build signed
    /// with a free Apple ID can't carry `com.apple.developer.in-app-payments`,
    /// and offering Apple Pay there gives the buyer a button that fails the
    /// moment they authorize it. iOS has no public API to read your own
    /// entitlements, so this tracks the one place that grants them: turn it on
    /// in the same configuration that adds the entitlement and registers the
    /// merchant id. Every other build is cards only.
    static let hasApplePayEntitlement: Bool = {
        let flag = Bundle.main.object(forInfoDictionaryKey: "CalibreApplePayEnabled")
        if let enabled = flag as? Bool { return enabled }
        // xcconfig substitution lands as a string.
        guard let text = flag as? String else { return false }
        return ["YES", "true", "1"].contains(text.trimmingCharacters(in: .whitespaces))
    }()

    /// Builds the shared PaymentSheet configuration. Apple Pay is attached only
    /// when this build can actually complete one; otherwise the sheet is cards
    /// only.
    static func configuration(
        customerID: String?,
        customerSessionClientSecret: String?
    ) -> PaymentSheet.Configuration {
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = merchantDisplayName
        configuration.returnURL = returnURL
        configuration.style = .automatic
        configuration.appearance = appearance()
        // The SDK's automatic layout defaults to a vertical list that
        // pre-selects Apple Pay whenever there's no saved card yet — a
        // first-time buyer never sees an actual card form without an extra
        // tap. Horizontal puts Card and Apple Pay side by side as equally
        // prominent tabs, with the card form visible as soon as Card is
        // selected.
        configuration.paymentMethodLayout = .horizontal

        if let customerID, let customerSessionClientSecret {
            configuration.customer = PaymentSheet.CustomerConfiguration(
                id: customerID,
                customerSessionClientSecret: customerSessionClientSecret
            )
        }

        if hasApplePayEntitlement, PKPaymentAuthorizationController.canMakePayments() {
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

    /// Human copy for a Stripe failure — Stripe's message when it has one, a
    /// warm fallback when it doesn't.
    static func failureMessage(for error: Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Your payment didn't go through. Please try again." : text
    }

    // MARK: - Apple Pay

    /// Whether this build and this device can actually complete an Apple Pay
    /// payment. Both halves matter: the entitlement is a property of the
    /// build, the wallet is a property of the device.
    @MainActor
    static var canOfferApplePay: Bool {
        hasApplePayEntitlement && PKPaymentAuthorizationController.canMakePayments()
    }

    /// The request behind the Apple Pay sheet. Every line the buyer reads is
    /// passed in already priced by the server; nothing here adds to a total.
    static func applePayRequest(
        currency: String,
        summaryItems: [PKPaymentSummaryItem]
    ) -> PKPaymentRequest {
        let request = StripeAPI.paymentRequest(
            withMerchantIdentifier: applePayMerchantID,
            country: "US",
            currency: currency
        )
        request.paymentSummaryItems = summaryItems
        // Checkout already collected a shipping address of its own, and the
        // order is priced against it. Asking Apple for one again would let the
        // buyer pick a destination the tax and shipping lines don't match.
        request.requiredShippingContactFields = []
        return request
    }

    /// Presents a PaymentSheet from whatever is frontmost.
    ///
    /// We deliberately don't use the SDK's `.paymentSheet(isPresented:)`
    /// modifier. Its presenter only acts on a false→true transition its
    /// coordinator actually *observes*, and the coordinator's `didSet` can't
    /// fire during `init`. Building the sheet and flipping the flag in one
    /// update — the natural way to write "pay now" — installs the presenter
    /// already-true, so it lands on (true, true), does nothing, and the button
    /// looks dead. Presenting imperatively is the same call the modifier makes
    /// internally, minus the race.
    ///
    /// The caller must keep `sheet` alive until `completion` fires; the SDK
    /// holds it weakly.
    @MainActor
    static func present(
        _ sheet: PaymentSheet,
        completion: @escaping (PaymentSheetResult) -> Void
    ) {
        guard let presenter = frontmostViewController() else {
            completion(.failed(error: PresentationError.noPresenter))
            return
        }
        beginHidingDoneAccessory()
        sheet.present(from: presenter) { result in
            endHidingDoneAccessory()
            completion(result)
        }
    }

    // MARK: - The floating tick

    @MainActor private static let doneAccessoryStripper = DoneAccessoryStripper()

    /// Drops the "Done" bar Stripe hangs off its card fields.
    ///
    /// Stripe sets an `inputAccessoryView` on every field whose keyboard has no
    /// return key to dismiss with — the card number, expiry, CVC and postcode.
    /// It's a `UIToolbar` holding a single `.done` item tinted
    /// `appearance.colors.primary`, and iOS 26 draws a one-item toolbar as a
    /// floating circular glass button. The result is an unexplained chocolate
    /// tick hovering over the Pay button. There is no SDK switch for it, so we
    /// clear the accessory as each field starts editing.
    ///
    /// Nothing is lost: `dismissesKeyboardOnBackgroundTap` installs its
    /// recogniser on the *window*, and the sheet is presented into that same
    /// window, so tapping anywhere off a field still closes the keypad.
    ///
    /// The inline `CardEntryField` is the same control with the same toolbar
    /// and the same window recogniser under it, so the buyer card step brackets
    /// its own appearance with these two calls.
    @MainActor
    static func beginHidingDoneAccessory() {
        doneAccessoryStripper.start()
    }

    @MainActor
    static func endHidingDoneAccessory() {
        doneAccessoryStripper.stop()
    }
    /// Walks the presentation chain from the active window's root so Stripe's
    /// UI comes up over whatever is already modal — checkout runs inside a
    /// full-screen cover, offers inside a sheet. Shared by PaymentSheet
    /// presentation and by 3-D Secure's authentication context.
    @MainActor
    static func frontmostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard let root = (scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first)?
            .rootViewController else { return nil }

        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }

    enum PresentationError: LocalizedError {
        case noPresenter

        var errorDescription: String? {
            "We couldn't open the payment sheet. Please try again."
        }
    }
}

/// Where 3-D Secure puts its challenge when the server-confirmed
/// PaymentIntent comes back needing one.
///
/// Checkout lives in a full-screen cover, so the presenter can't be captured
/// once and held — it changes as the buyer moves through the steps. Resolving
/// it on demand keeps the challenge on top of whatever is actually on screen.
/// The owning model must hold on to this object for the life of the call:
/// `STPPaymentHandler` keeps only a weak reference.
@MainActor
final class CheckoutAuthenticationContext: NSObject, STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        CalibreStripe.frontmostViewController() ?? UIViewController()
    }
}

/// Listens while a Stripe sheet is up and clears the toolbar accessory from any
/// field that starts editing. A selector-based observer rather than a block:
/// UIKit posts this on the main thread, and `@objc` dispatch keeps the
/// non-`Sendable` `Notification` from crossing an isolation boundary.
@MainActor
private final class DoneAccessoryStripper: NSObject {
    private var listening = false

    func start() {
        guard !listening else { return }
        listening = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fieldDidBeginEditing),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
    }

    func stop() {
        guard listening else { return }
        listening = false
        NotificationCenter.default.removeObserver(
            self,
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
    }

    @objc private func fieldDidBeginEditing(_ note: Notification) {
        guard let field = note.object as? UITextField,
              field.inputAccessoryView is UIToolbar else { return }
        field.inputAccessoryView = nil
        field.reloadInputViews()
    }
}
