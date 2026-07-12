import CalibreDesign
import CalibreKit
import SwiftUI

/// The sign-in screen. Lives two lives: the full-screen gate after the intro
/// (with "Browse as guest" at the bottom) and a modal reached from the You
/// tab once a guest wants in. Always the screen — never a half sheet.
struct LoginScreen: View {
    enum Context {
        /// The app's front door — offers "Browse as guest".
        case gate
        /// Presented modally over the tab shell — offers "Close" instead.
        case modal
    }

    let context: Context

    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @AppStorage("guestChosen") private var guestChosen = false

    @State private var identifier = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var busy = false
    @FocusState private var focusedField: Field?

    private enum Field { case identifier, password }

    private var canSubmit: Bool {
        !identifier.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !busy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                header
                    .padding(.top, context == .gate ? Space.xxl * 2 : Space.xl)
                    .padding(.bottom, Space.s)

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
                    .focused($focusedField, equals: .identifier)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    CalibreTextField(
                        "Password",
                        text: $password,
                        isSecure: true
                    )
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { Task { await signIn() } } }
                }

                if let errorMessage {
                    AuthErrorLine(message: errorMessage)
                }

                VStack(spacing: Space.m) {
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

                    NavigationLink("Forgot password?") {
                        ForgotPasswordScreen()
                    }
                    .buttonStyle(.calibreGhost)
                }

                AuthDivider()

                VStack(spacing: Space.m) {
                    AppleSignInButton(onMessage: { showMessage($0) })
                    GoogleSignInButton(onMessage: { showMessage($0) })
                }

                HStack(spacing: Space.xs) {
                    Text("New to Calibre?")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                    NavigationLink("Create an account") {
                        RegisterScreen()
                    }
                    .font(CalibreType.bodySemiBold)
                    .tint(Color.calibre.primary)
                }
                .padding(.top, Space.s)

                if context == .gate {
                    Button("Browse as guest") {
                        Haptics.shared.play(.press)
                        guestChosen = true
                    }
                    .buttonStyle(.calibre(.ghost, fullWidth: true))
                    .padding(.top, Space.l)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.calibre.background.ignoresSafeArea())
        .toolbar {
            if context == .modal {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .frame(width: Space.touchTarget, height: Space.touchTarget)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Close")
                }
            }
        }
        .animation(Motion.easeFast, value: errorMessage)
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated, context == .modal {
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: Space.m) {
            CalibreWordmark()
            Text("Welcome back. Sign in to pick up where you left off.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func signIn() async {
        guard canSubmit else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }

        let ok = await performAuthAction({
            try await session.login(
                identifier: identifier.trimmingCharacters(in: .whitespaces),
                password: password
            )
        }, onError: { errorMessage = $0 })

        if ok {
            Haptics.shared.play(.success)
            toasts.show(title: "Welcome back", message: "You're signed in.", tone: .success)
        }
    }

    private func showMessage(_ message: String) {
        errorMessage = message
    }
}
