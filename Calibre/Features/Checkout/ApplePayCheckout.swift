import Foundation
import PassKit
import StripeApplePay

/// Apple Pay, running through exactly the same funding gate as the card form.
///
/// The wallet hands us a PaymentMethod, and from there nothing is special:
/// the server is asked whether that card's funding is acceptable for this
/// listing, then asked to confirm the PaymentIntent. Only when both pass does
/// this hand Stripe the client secret, which is what closes the Apple Pay
/// sheet with a tick. A refusal throws, so the sheet reports the failure and
/// the buyer lands back on the refusal notice with wire one tap away.
///
/// `STPApplePayContext` holds its delegate weakly, so `CheckoutModel` keeps
/// this object alive for the life of the payment.
@MainActor
final class ApplePayCheckout: NSObject, ApplePayContextDelegate {
    private weak var model: CheckoutModel?

    init(model: CheckoutModel) {
        self.model = model
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCreatePaymentMethod paymentMethod: StripeAPI.PaymentMethod,
        paymentInformation: PKPayment
    ) async throws -> String {
        guard let model else { throw CheckoutMessageError.lost }
        return try await model.authorizeWalletPayment(paymentMethodID: paymentMethod.id)
    }

    func applePayContext(
        _ context: STPApplePayContext,
        didCompleteWith status: STPApplePayContext.PaymentStatus,
        error: Error?
    ) {
        model?.applePayFinished(succeeded: status == .success, error: error)
    }
}

/// A failure carrying copy we already wrote. Apple Pay surfaces the thrown
/// error's description inside its own sheet, so refusals have to travel as
/// errors rather than as state the sheet can't see.
struct CheckoutMessageError: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    static let lost = CheckoutMessageError(
        message: "We lost track of this checkout. Please start again."
    )
}
