import CalibreDesign
import CalibreKit
import SwiftUI

/// The guest gate — a medium sheet that appears when a signed-out visitor
/// tries something that needs an account. The pending intent's reason leads;
/// a successful sign-in replays the intent automatically.
struct AuthGateSheet: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var identifier = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var showRegister = false

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        SheetScaffold(
            title: session.pendingIntent?.reason ?? "Sign in to continue",
            detents: [.medium, .large]
        ) {
            ScrollView {
                VStack(spacing: Space.l) {
                    CalibreTextField(
                        "Email or username",
                        text: $identifier,
                        placeholder: "you@example.com"
                    )
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    CalibreTextField("Password", text: $password, isSecure: true)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { Task { await signIn() } } }

                    if let errorMessage {
                        AuthErrorLine(message: errorMessage)
                    }

                    Button {
                        Haptics.shared.play(.press)
                        Task { await signIn() }
                    } label: {
                        HStack(spacing: Space.s) {
                            if busy {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(Color.calibre.primaryForeground)
                            }
                            Text("Sign In")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(!canSubmit)

                    AppleSignInButton(onMessage: { errorMessage = $0 })
                    GoogleSignInButton(onMessage: { errorMessage = $0 })

                    HStack(spacing: Space.xs) {
                        Text("New to Calibre?")
                            .font(CalibreType.body)
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Button("Create an account") {
                            showRegister = true
                        }
                        .font(CalibreType.bodySemiBold)
                        .tint(Color.calibre.primary)
                    }

                    Button("Not now") {
                        dismiss()
                    }
                    .buttonStyle(.calibreGhost)
                    .foregroundStyle(Color.calibre.mutedForeground)
                }
                .padding(.bottom, Space.xxl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(Motion.easeFast, value: errorMessage)
        .fullScreenCover(isPresented: $showRegister) {
            NavigationStack {
                RegisterScreen(isModal: true)
            }
        }
    }

    private func signIn() async {
        guard canSubmit else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }

        // Success clears pendingIntent by replaying it, which flips the
        // sheet's presentation binding — no manual dismiss needed.
        let ok = await performAuthAction({
            try await session.login(
                identifier: identifier.trimmingCharacters(in: .whitespaces),
                password: password
            )
        }, onError: { errorMessage = $0 })

        if ok {
            Haptics.shared.play(.success)
        }
    }
}
