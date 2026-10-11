import RewatchDesign
import RewatchKit
import SwiftUI

/// The sign-in screen: a modal reached from the Me tab once a guest wants in.
/// Always the screen — never a half sheet.
///
/// It used to live a second life as the app's front door, a full-screen gate
/// after the intro with "Browse as guest" at the bottom. That door is gone —
/// the app opens on the market now — and the gate went with it rather than
/// being left standing behind a flag, because a screen nothing reaches is a
/// screen nobody maintains. The mid-action sheet (`AuthGateSheet`) is what a
/// signed-out visitor meets instead, at the moment they reach for something
/// that needs an account.
struct LoginScreen: View {
    enum Context {
        /// Presented modally over the tab shell — offers "Close".
        case modal
    }

    /// Names the presentation at the call site. Nothing reads it while
    /// `.modal` is the only shape the screen has.
    let context: Context

    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

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
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.s)

                VStack(spacing: Space.l) {
                    RewatchTextField(
                        "Email or username",
                        text: $identifier,
                        placeholder: "you@example.com",
                        kind: .emailOrUsername
                    )
                    .focused($focusedField, equals: .identifier)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    RewatchTextField(
                        "Password",
                        text: $password,
                        kind: .password
                    )
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
                        RewatchBusyLabel("Sign In", busy: busy)
                    }
                    .buttonStyle(.rewatch(.primary, fullWidth: true))
                    .disabled(!canSubmit)

                    NavigationLink("Forgot password?") {
                        ForgotPasswordScreen()
                    }
                    .buttonStyle(.rewatchGhost)
                }

                AuthDivider()

                VStack(spacing: Space.m) {
                    AppleSignInButton(onMessage: { showMessage($0) })
                    GoogleSignInButton(onMessage: { showMessage($0) })
                }

                signUpPrompt
                    .padding(.top, Space.s)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .rewatchPageBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Close")
            }
        }
        .animation(Motion.easeFast, value: errorMessage)
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: Space.m) {
            // The wordmark alone, and it is also what shows the request is
            // in flight: it breathes until the answer lands.
            SigningInWordmark(breathing: busy)
                .accessibilityAddTraits(.isHeader)
            Text("Welcome back. Sign in to pick up where you left off.")
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// "New to ReWatch?" and the way in. One line while the two fit side by
    /// side — which is every normal text size — and stacked once they don't,
    /// rather than the link running off the right edge of the screen.
    private var signUpPrompt: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.xs) {
                signUpLead
                signUpLink
            }
            VStack(spacing: Space.xs) {
                signUpLead
                signUpLink
            }
        }
    }

    private var signUpLead: some View {
        Text("New to ReWatch?")
            .font(RewatchType.body)
            .foregroundStyle(Color.rewatch.mutedForeground)
    }

    private var signUpLink: some View {
        NavigationLink("Create an account") {
            RegisterScreen()
        }
        .font(RewatchType.bodySemiBold)
        .tint(Color.rewatch.primary)
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
            Observability.log(.info, "sign-in succeeded")
            Haptics.shared.play(.success)
            toasts.show(title: "Welcome back", message: "You're signed in.", tone: .success)
        } else {
            Observability.log(.warning, "sign-in failed: \(errorMessage ?? "canceled")")
        }
    }

    private func showMessage(_ message: String) {
        errorMessage = message
    }
}

/// The wordmark, breathing while the sign-in request is in flight: its
/// opacity eases 1 → 0.55 → 1 over 1.4 s for as long as the request is out,
/// and once the answer lands it eases back to full and stops. A word cannot
/// turn the way the old mark did, and a breath is the one motion that still
/// reads as "working" on letters.
///
/// Purely visual. It reads `breathing` and nothing reads it back — the
/// request is awaited in `signIn()`, the dismiss follows the session, and
/// neither waits on a frame of this — so it cannot delay a sign-in by a tick.
///
/// Driven by explicit state and `withAnimation` from a `.task` in this one
/// leaf rather than by `TimelineView` or a `repeatForever` animation: the
/// timeline redraws whatever holds it, and a forever animation cannot be
/// eased out of — retargeting it either jumps or leaves the loop running
/// underneath. Each half-breath is its own eased animation, so ending one
/// mid-way is just one more, back to full; the loop ends with the request,
/// so nothing ticks on an idle screen.
///
/// Reduce Motion, from either signal, is the word standing still at full
/// opacity: no loop is started, and one already running is stood up.
private struct SigningInWordmark: View {
    let breathing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    /// Half a breath: 1.4 s in and out.
    private static let half: Duration = .milliseconds(700)
    private static let breath = Animation.easeInOut(duration: 0.7)
    private static let lowest = 0.55

    private var motionIsUnwelcome: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        RewatchWordmark(height: 30)
            .opacity(dimmed ? Self.lowest : 1)
            .task(id: breathing) { await run() }
            .onChange(of: motionIsUnwelcome) { _, unwelcome in
                if unwelcome { standStill() }
            }
    }

    private func run() async {
        guard breathing, !motionIsUnwelcome else {
            settle()
            return
        }
        while !Task.isCancelled {
            withAnimation(Self.breath) { dimmed = true }
            guard (try? await Task.sleep(for: Self.half)) != nil else { return }
            withAnimation(Self.breath) { dimmed = false }
            guard (try? await Task.sleep(for: Self.half)) != nil else { return }
            if motionIsUnwelcome {
                standStill()
                return
            }
        }
    }

    /// The answer landed: back to full, eased, from wherever the breath was.
    private func settle() {
        guard dimmed else { return }
        if motionIsUnwelcome {
            standStill()
        } else {
            withAnimation(.easeOut(duration: 0.35)) { dimmed = false }
        }
    }

    private func standStill() {
        var still = Transaction(animation: nil)
        still.disablesAnimations = true
        withTransaction(still) { dimmed = false }
    }
}
