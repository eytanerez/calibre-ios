import AuthenticationServices
import CalibreDesign
import CalibreKit
import SwiftUI

/// "Continue with Google" — runs the backend's native-handoff OAuth flow in
/// an ASWebAuthenticationSession, then redeems the one-time code at
/// /auth/exchange. Error codes from the callback map to human sentences.
struct GoogleSignInButton: View {
    @Environment(AuthSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    /// Called with a message the user should see.
    let onMessage: (String) -> Void
    /// Called after a successful sign-in.
    var onSuccess: () -> Void = {}

    @State private var busy = false

    var body: some View {
        Button {
            Haptics.shared.play(.press)
            Task { await run() }
        } label: {
            HStack(spacing: Space.s) {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.calibre.mutedForeground)
                }
                Text("Continue with Google")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.calibre(.secondary, fullWidth: true))
        .disabled(busy)
    }

    private func run() async {
        busy = true
        defer { busy = false }

        var components = URLComponents(
            url: services.client.baseURL.appending(path: "/auth/google/start"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "client", value: "ios"),
            URLQueryItem(name: "redirect", value: "/"),
        ]
        guard let startURL = components.url else { return }

        let callbackURL: URL
        do {
            callbackURL = try await webAuthenticationSession.authenticate(
                using: startURL,
                callback: .customScheme("calibre"),
                additionalHeaderFields: [:]
            )
        } catch {
            if let sessionError = error as? ASWebAuthenticationSessionError,
               sessionError.code == .canceledLogin {
                return // The user closed the sheet — say nothing.
            }
            onMessage("We couldn't open Google sign-in. Please try again.")
            return
        }

        let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        if let errorCode = query?.first(where: { $0.name == "error" })?.value {
            Haptics.shared.play(.error)
            onMessage(GoogleAuthError.message(for: errorCode))
            return
        }
        guard let code = query?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            onMessage("Google sign-in didn't go through. Please try again.")
            return
        }

        // The one-time code lives 60 seconds — redeem it immediately.
        let ok = await performAuthAction({
            try await session.authenticate(path: "/auth/exchange", payload: ["code": code])
        }, onError: onMessage)
        if ok {
            Haptics.shared.play(.success)
            onSuccess()
        }
    }
}
