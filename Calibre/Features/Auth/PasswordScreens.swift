import CalibreDesign
import CalibreKit
import SwiftUI

/// "Forgot password" — takes an email and always answers with the same calm
/// confirmation, whether or not an account exists.
struct ForgotPasswordScreen: View {
    @Environment(AppServices.self) private var services

    @State private var email = ""
    @State private var sent = false
    @State private var busy = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        InputValidation.isValidEmail(email) && !busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if sent {
                    confirmation
                        .transition(.opacity)
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.easeMedium, value: sent)
        .animation(Motion.easeFast, value: errorMessage)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Tell us the email on your account and we'll send a link to set a new password.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)

            CalibreTextField("Email", text: $email, placeholder: "you@example.com")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let errorMessage {
                AuthErrorLine(message: errorMessage)
            }

            Button {
                Haptics.shared.play(.press)
                Task { await submit() }
            } label: {
                HStack(spacing: Space.s) {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.calibre.primaryForeground)
                    }
                    Text("Send reset link")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(!canSubmit)
        }
    }

    private var confirmation: some View {
        EmptyState(
            icon: "envelope",
            title: "Check your email",
            message: "If an account exists for \(email.trimmingCharacters(in: .whitespaces)), a reset link is on its way. It's valid for a short while, so use it soon."
        )
        .frame(maxWidth: .infinity)
        .padding(.top, Space.xxl)
    }

    private func submit() async {
        guard canSubmit else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }

        do {
            let endpoint = try Endpoint<EmptyResponse>.json(
                method: .post,
                path: "/auth/password/forgot",
                payload: ["email": email.trimmingCharacters(in: .whitespaces).lowercased()],
                requiresAuth: false
            )
            _ = try await services.client.send(endpoint)
            sent = true
        } catch let error as APIError {
            Haptics.shared.play(.error)
            errorMessage = error.authMessage
        } catch {
            Haptics.shared.play(.error)
            errorMessage = "Something went wrong. Please try again."
        }
    }
}

/// Sets a new password from a reset link — reached via
/// calibre://auth/reset?token=… (and the web's /auth/reset-password URL).
struct ResetPasswordScreen: View {
    let token: String

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var passwordSatisfiesRules: Bool {
        InputValidation.passwordMeetsRules(password)
    }

    private var canSubmit: Bool {
        passwordSatisfiesRules && passwordsMatch && !busy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Choose a new password for your account.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)

                VStack(alignment: .leading, spacing: Space.m) {
                    CalibreTextField("New password", text: $password, isSecure: true)
                        .textContentType(.newPassword)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        rule("At least 8 characters", satisfied: password.count >= 8)
                        rule("One capital letter", satisfied: password.contains(where: \.isUppercase))
                        rule("One number", satisfied: password.contains(where: \.isNumber))
                    }
                    .animation(Motion.easeFast, value: password)
                }

                CalibreTextField("Confirm password", text: $confirmPassword, isSecure: true) {
                    if !confirmPassword.isEmpty {
                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(passwordsMatch ? Color.calibre.success : Color.calibre.destructive)
                    }
                }
                .textContentType(.newPassword)

                if let errorMessage {
                    AuthErrorLine(message: errorMessage)
                }

                Button {
                    Haptics.shared.play(.press)
                    Task { await submit() }
                } label: {
                    HStack(spacing: Space.s) {
                        if busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.calibre.primaryForeground)
                        }
                        Text("Set new password")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(!canSubmit)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("New password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .animation(Motion.easeFast, value: errorMessage)
    }

    private func rule(_ text: String, satisfied: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(satisfied ? Color.calibre.success : Color.calibre.mutedForeground)
            Text(text)
                .font(CalibreType.caption)
                .foregroundStyle(satisfied ? Color.calibre.foreground : Color.calibre.mutedForeground)
        }
    }

    private func submit() async {
        guard canSubmit else { return }
        errorMessage = nil
        busy = true
        defer { busy = false }

        do {
            let endpoint = try Endpoint<EmptyResponse>.json(
                method: .post,
                path: "/auth/password/reset",
                payload: ["token": token, "password": password],
                requiresAuth: false
            )
            _ = try await services.client.send(endpoint)
            Haptics.shared.play(.success)
            toasts.show(
                title: "Password reset",
                message: "Sign in with your new password whenever you're ready.",
                tone: .success
            )
            dismiss()
        } catch let error as APIError {
            Haptics.shared.play(.error)
            errorMessage = error.authMessage
        } catch {
            Haptics.shared.play(.error)
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
