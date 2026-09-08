import CalibreDesign
import CalibreKit
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
                    CalibreTextField(
                        "Email or username",
                        text: $identifier,
                        placeholder: "you@example.com",
                        kind: .emailOrUsername
                    )
                    .focused($focusedField, equals: .identifier)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }

                    CalibreTextField(
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

                signUpPrompt
                    .padding(.top, Space.s)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .calibrePageBackground()
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
        .onChange(of: session.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: Space.m) {
            SigningInMark(turning: busy)
            CalibreWordmark()
            Text("Welcome back. Sign in to pick up where you left off.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// "New to Calibre?" and the way in. One line while the two fit side by
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
        Text("New to Calibre?")
            .font(CalibreType.body)
            .foregroundStyle(Color.calibre.mutedForeground)
    }

    private var signUpLink: some View {
        NavigationLink("Create an account") {
            RegisterScreen()
        }
        .font(CalibreType.bodySemiBold)
        .tint(Color.calibre.primary)
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

/// The Calibre mark above the wordmark, turning while the sign-in request is
/// in flight: a slow, continuous turn that runs down onto upright once the
/// response lands.
///
/// Purely visual. It reads `turning` and nothing reads it back — the request
/// is awaited in `signIn()`, the dismiss follows the session, and neither
/// waits on a frame of this — so it cannot delay a sign-in by a tick.
///
/// Driven by a `.task` loop against `ContinuousClock` in this one leaf rather
/// than by `TimelineView` or a `repeatForever` animation: the timeline
/// redraws whatever holds it, and a forever animation cannot be eased out of
/// — retargeting it either unwinds the mark or leaves the loop running
/// underneath. The arithmetic of the turn is `LogoTurn`'s: it winds in, holds,
/// and once the answer lands carries on to the last upright it can ease onto
/// and rests there — a failed sign-in leaves this screen up, and the mark is
/// oriented, so it cannot be left standing wherever its speed ran out. The
/// loop ends with the rest, so nothing ticks on an idle screen.
///
/// Reduce Motion, from either signal, is a still mark standing upright: no
/// loop is started, and one already running is stood up rather than left on a
/// mid frame or spun to rest.
private struct SigningInMark: View {
    let turning: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the turn has got to, carried across the flip from turning to
    /// settling and across a retry.
    @State private var turn = LogoTurn()

    private static let tick: Duration = .milliseconds(16)

    private var motionIsUnwelcome: Bool {
        reduceMotion || UIAccessibility.isReduceMotionEnabled
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    var body: some View {
        CalibreLogoMark(size: 48)
            .rotationEffect(.degrees(turn.angle))
            .task(id: turning) { await run() }
            .onChange(of: motionIsUnwelcome) { _, unwelcome in
                if unwelcome { turn.stop() }
            }
    }

    private func run() async {
        guard !motionIsUnwelcome else {
            turn.stop()
            return
        }
        // Nothing to do on a screen whose mark already stands upright.
        guard turning || !turn.isAtRest else { return }
        let clock = ContinuousClock()
        var last = clock.now

        while !Task.isCancelled {
            guard (try? await clock.sleep(for: Self.tick)) != nil else { return }
            if motionIsUnwelcome {
                turn.stop()
                return
            }
            let now = clock.now
            turn.advance(by: Self.seconds(now - last), turning: turning)
            last = now
            if turn.isAtRest { return }
        }
    }
}
