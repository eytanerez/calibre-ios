import CalibreDesign
import CalibreKit
import SwiftUI

/// The sheet a signed-out visitor meets when they reach for something that
/// needs an account. The pending intent's reason leads; a successful sign-in
/// replays the intent automatically.
///
/// With the app opening on the market, this is the **first sign-in most new
/// people ever see** — so it is shaped for someone who has no account rather
/// than for someone remembering a password. Apple and Google lead, because
/// one tap is the whole flow. Creating an account is a real button under
/// them. The email fields stay folded away behind "Already have an account?",
/// which is the only person they are any use to. And "Not now" stays at the
/// bottom, where it says out loud that walking away costs nothing.
struct AuthGateSheet: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var identifier = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var showRegister = false
    /// False until somebody says they already have an account.
    @State private var showsCredentials = false
    @FocusState private var focusedField: Field?

    private enum Field { case identifier, password }

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        SheetScaffold(
            title: session.pendingIntent?.reason ?? "Sign in to continue",
            // Narrowing to a single detent is what moves an already-presented
            // sheet: the password field and its keyboard do not fit in the
            // medium one, and nobody should have to drag a sheet upward to
            // reach the button that submits the form they just opened.
            detents: showsCredentials ? [.large] : [.medium, .large]
        ) {
            ScrollView {
                VStack(spacing: Space.l) {
                    // What happens after. True of every intent — a successful
                    // sign-in replays the action that raised this sheet (see
                    // `AuthSession.replayPendingIntent`) — and the same
                    // promise checkout already makes in the same words.
                    Text("We'll bring you right back here.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // One error line for the whole sheet, above everything
                    // rather than beside each control: Apple, Google and the
                    // password form all fail into it, and only this position
                    // is on screen whichever of them the reader was using.
                    if let errorMessage {
                        AuthErrorLine(message: errorMessage)
                    }

                    VStack(spacing: Space.m) {
                        AppleSignInButton(onMessage: { errorMessage = $0 })
                        GoogleSignInButton(onMessage: { errorMessage = $0 })
                    }

                    AuthDivider()

                    Button("Create an account") {
                        Haptics.shared.play(.press)
                        showRegister = true
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))

                    if showsCredentials {
                        credentialForm
                    } else {
                        Button("Already have an account? Sign in") {
                            Haptics.shared.play(.press)
                            showsCredentials = true
                        }
                        .buttonStyle(.calibre(.ghost, fullWidth: true))
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
        .animation(Motion.easeMedium, value: showsCredentials)
        .fullScreenCover(isPresented: $showRegister) {
            NavigationStack {
                RegisterScreen(isModal: true)
            }
        }
    }

    /// The email path, unfolded only for someone who says they already have
    /// an account.
    private var credentialForm: some View {
        VStack(spacing: Space.l) {
            CalibreTextField(
                "Email or username",
                text: $identifier,
                placeholder: "you@example.com",
                kind: .emailOrUsername
            )
            .focused($focusedField, equals: .identifier)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }

            CalibreTextField("Password", text: $password, kind: .password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { if canSubmit { Task { await signIn() } } }

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
        }
        // Focused here rather than in the button that opened the form: the
        // field does not exist yet at the moment of that tap, and a
        // `@FocusState` written at a value the hierarchy has not got is
        // simply dropped.
        .onAppear { focusedField = .identifier }
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
