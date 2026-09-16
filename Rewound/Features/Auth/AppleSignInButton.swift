import AuthenticationServices
import RewoundDesign
import RewoundKit
import CryptoKit
import Security
import SwiftUI

/// Sign in with Apple, mapped to the theme per the HIG — black button on the
/// light theme, white on dark. On credential we send the identity token (and
/// the name parts Apple only supplies on first authorization) to /auth/apple.
///
/// The entitlement is now present (com.apple.developer.applesignin, with the
/// matching capability on the com.shoprewound.rewound App ID), so this works.
/// It previously failed with ASAuthorizationError.unknown purely because the
/// entitlement was missing on a free team; the unknown-error branch below is
/// kept because that is still what a mis-provisioned build reports, and a calm
/// note beats a raw error if signing ever regresses.
struct AppleSignInButton: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    /// Called with a message the user should see (error or provisioning note).
    let onMessage: (String) -> Void
    /// Called after a successful sign-in.
    var onSuccess: () -> Void = {}

    @State private var busy = false
    @State private var currentNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
            let nonce = Self.makeNonce()
            currentNonce = nonce
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            handle(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: Space.touchTarget)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .opacity(busy ? 0.6 : 1)
        .disabled(busy)
        .accessibilityLabel("Sign in with Apple")
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                onMessage("Apple didn't return a usable credential. Please try again.")
                return
            }

            currentNonce = nil
            var payload: [String: AuthJSON] = [
                "identity_token": .string(token),
                "raw_nonce": .string(nonce),
            ]
            // Apple supplies the name only on the very first authorization —
            // pass it along then to seed the buyer profile.
            var name: [String: AuthJSON] = [:]
            if let given = credential.fullName?.givenName, !given.isEmpty {
                name["given_name"] = .string(given)
            }
            if let family = credential.fullName?.familyName, !family.isEmpty {
                name["family_name"] = .string(family)
            }
            if !name.isEmpty {
                payload["full_name"] = .object(name)
            }

            busy = true
            Task {
                defer { busy = false }
                // One endpoint serves both sign-up and sign-in; only the 201
                // this reports separates them.
                var createdAccount = false
                let ok = await performAuthAction({
                    createdAccount = try await session.authenticate(
                        path: "/auth/apple",
                        payload: payload
                    )
                }, onError: onMessage)
                if ok {
                    if createdAccount {
                        Analytics.signupCompleted(method: .apple)
                    }
                    Haptics.shared.play(.success)
                    onSuccess()
                }
            }

        case .failure(let error):
            currentNonce = nil
            guard let authError = error as? ASAuthorizationError else {
                onMessage("Sign in with Apple didn't go through. Please try again.")
                return
            }
            switch authError.code {
            case .canceled:
                break // The user changed their mind — say nothing.
            case .unknown:
                // Expected until the app is signed with the SiwA entitlement.
                onMessage("Sign in with Apple activates once the app is provisioned — use email for now.")
            default:
                onMessage("Sign in with Apple didn't go through. Please try again.")
            }
        }
    }

    private static func makeNonce(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to create Sign in with Apple nonce")
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
