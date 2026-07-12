import AuthenticationServices
import CalibreDesign
import CalibreKit
import SwiftUI

/// Sign in with Apple, mapped to the theme per the HIG — black button on the
/// light theme, white on dark. On credential we send the identity token (and
/// the name parts Apple only supplies on first authorization) to /auth/apple.
///
/// The app is currently built without the SiwA entitlement (no paid team),
/// so authorization fails with ASAuthorizationError.unknown — we surface a
/// calm provisioning note instead of an error. The flow itself is complete.
struct AppleSignInButton: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    /// Called with a message the user should see (error or provisioning note).
    let onMessage: (String) -> Void
    /// Called after a successful sign-in.
    var onSuccess: () -> Void = {}

    @State private var busy = false

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
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
                  let token = String(data: tokenData, encoding: .utf8) else {
                onMessage("Apple didn't return a usable credential. Please try again.")
                return
            }

            var payload: [String: AuthJSON] = ["identity_token": .string(token)]
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
                let ok = await performAuthAction({
                    try await session.authenticate(path: "/auth/apple", payload: payload)
                }, onError: onMessage)
                if ok {
                    Haptics.shared.play(.success)
                    onSuccess()
                }
            }

        case .failure(let error):
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
}
