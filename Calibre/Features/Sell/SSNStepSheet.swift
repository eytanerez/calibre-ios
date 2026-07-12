import CalibreDesign
import CalibreKit
import SwiftUI

/// Native SSN step before Stripe Connect onboarding. The number is masked,
/// auto-formats as 123-45-6789, and goes straight to Stripe — Calibre keeps
/// only a one-way fingerprint.
struct SSNStepSheet: View {
    let onSession: (ConnectAccountSession) -> Void

    @Environment(SellSession.self) private var sell
    @Environment(\.dismiss) private var dismiss

    @State private var ssn = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        SheetScaffold(title: "Verify your identity", detents: [.medium]) {
            VStack(alignment: .leading, spacing: Space.xl) {
                CalibreTextField(
                    "Social Security number",
                    text: $ssn,
                    placeholder: "123-45-6789",
                    error: error,
                    isSecure: true
                )
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .onChange(of: ssn) { _, newValue in
                    let formatted = Self.format(newValue)
                    if formatted != newValue {
                        ssn = formatted
                    }
                    if error != nil {
                        error = nil
                    }
                }

                CalloutBand(
                    icon: "lock.shield",
                    message: "Your SSN is sent securely to Stripe to verify your identity. Calibre never stores it — only a one-way fingerprint that keeps previously banned sellers off the marketplace."
                )

                Button {
                    submit()
                } label: {
                    if busy {
                        ProgressView().tint(Color.calibre.primaryForeground)
                    } else {
                        Text("Continue to Stripe")
                    }
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(busy || digits.count != 9)

                Spacer(minLength: 0)
            }
            .padding(.top, Space.s)
        }
    }

    private var digits: String {
        ssn.filter(\.isNumber)
    }

    /// 9 digits max, dashes after the 3rd and 5th.
    static func format(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(9))
        var out = ""
        for (index, character) in digits.enumerated() {
            if index == 3 || index == 5 {
                out.append("-")
            }
            out.append(character)
        }
        return out
    }

    private func submit() {
        guard digits.count == 9, !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let session = try await sell.ops.connectAccountSession(ssn: ssn)
                Haptics.shared.play(.success)
                dismiss()
                onSession(session)
            } catch let apiError as APIError {
                error = Self.humanMessage(for: apiError)
            } catch let other {
                error = sellErrorMessage(other)
            }
        }
    }

    /// Human copy for the account-session error codes.
    static func humanMessage(for error: APIError) -> String {
        switch error.serverCode {
        case "ssn_required":
            return "Enter your 9-digit Social Security number so Stripe can verify your identity."
        case "seller_onboarding_blocked":
            return "We can't enable selling for this account. Please contact support and we'll take a look together."
        case "phone_required":
            return "Add a US phone number to your account first — Stripe needs it to verify your identity."
        default:
            if case .server(let message, _, _, _) = error, message.lowercased().contains("phone") {
                return "Add a US phone number to your account first — Stripe needs it to verify your identity."
            }
            return error.sellMessage
        }
    }
}
