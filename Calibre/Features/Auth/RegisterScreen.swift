import CalibreDesign
import CalibreKit
import SwiftUI

/// Two-step account creation. Step one is who you are — with a live username
/// check and a password checklist that ticks as you type. Step two is where
/// watches should ship, and where the terms are accepted — the backend now
/// refuses a registration without it. Registration signs the new member in on
/// the spot.
struct RegisterScreen: View {
    /// True when presented in its own modal cover (adds a close button).
    var isModal = false

    @Environment(AuthSession.self) private var session
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Step 1 — identity.
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    // Step 2 — shipping address.
    @State private var addressFullName = ""
    @State private var street = ""
    @State private var apartment = ""
    @State private var city = ""
    @State private var zip = ""
    @State private var state = ""
    @State private var country = "US"

    /// Never seeded true, never restored from anywhere. A pre-ticked box is
    /// not consent, and this one is the only record that the person agreed.
    @State private var acceptedTerms = false

    @State private var step = 1
    @State private var usernameState: UsernameCheckState = .idle
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                stepIndicator

                Group {
                    if step == 1 {
                        stepOne
                            .transition(stepTransition(forward: false))
                    } else {
                        stepTwo
                            .transition(stepTransition(forward: true))
                    }
                }

                if let errorMessage {
                    AuthErrorLine(message: errorMessage)
                }

                footerButtons
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .calibrePageBackground()
        .navigationTitle("Create account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModal {
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
        .animation(reduceMotion ? nil : Motion.easeMedium, value: step)
        .animation(Motion.easeFast, value: errorMessage)
        .onChange(of: username) { _, newValue in
            scheduleUsernameCheck(for: newValue)
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Step \(step) of 2")
            HStack(spacing: Space.xs) {
                Capsule()
                    .fill(Color.calibre.primary)
                    .frame(height: 3)
                Capsule()
                    .fill(step == 2 ? Color.calibre.primary : Color.calibre.border)
                    .frame(height: 3)
            }
            Text(step == 1 ? "Tell us who you are." : "Where should watches ship?")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Step 1

    private var stepOne: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                CalibreTextField("First name", text: $firstName, kind: .givenName)
                CalibreTextField("Last name", text: $lastName, kind: .familyName)
            }

            CalibreTextField(
                "Email",
                text: $email,
                placeholder: "you@example.com",
                kind: .email
            )

            CalibreTextField(
                "Phone",
                text: $phone,
                placeholder: "(415) 555-0134",
                kind: .phone
            )
            .phoneFormatted($phone)

            usernameField

            VStack(alignment: .leading, spacing: Space.m) {
                CalibreTextField("Password", text: $password, kind: .newPassword)
                passwordChecklist
            }

            confirmPasswordField
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            CalibreTextField(
                "Username",
                text: $username,
                placeholder: "e.g. dialside",
                kind: .username
            ) {
                usernameAccessory
            }

            if let caption = usernameState.caption {
                Text(caption.text)
                    .font(CalibreType.caption)
                    .foregroundStyle(caption.positive ? Color.calibre.success : Color.calibre.destructive)
                    .transition(.opacity)
            }
        }
        .animation(Motion.easeFast, value: usernameState)
    }

    @ViewBuilder
    private var usernameAccessory: some View {
        switch usernameState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .controlSize(.small)
                .tint(Color.calibre.mutedForeground)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.calibre.success)
                .accessibilityLabel("Username is available")
        case .unavailable, .invalid:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.calibre.destructive)
                .accessibilityLabel("Username is not available")
        }
    }

    private var passwordChecklist: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            passwordRule("At least 8 characters", satisfied: password.count >= 8)
            passwordRule("One capital letter", satisfied: password.contains(where: \.isUppercase))
            passwordRule("One number", satisfied: password.contains(where: \.isNumber))
        }
        .animation(Motion.easeFast, value: password)
    }

    private func passwordRule(_ text: String, satisfied: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(satisfied ? Color.calibre.success : Color.calibre.mutedForeground)
            Text(text)
                .font(CalibreType.caption)
                .foregroundStyle(satisfied ? Color.calibre.foreground : Color.calibre.mutedForeground)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(satisfied ? "met" : "not met")
    }

    private var confirmPasswordField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            CalibreTextField("Confirm password", text: $confirmPassword, kind: .newPassword) {
                if !confirmPassword.isEmpty {
                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(passwordsMatch ? Color.calibre.success : Color.calibre.destructive)
                        .accessibilityLabel(passwordsMatch ? "Passwords match" : "Passwords don't match")
                }
            }

            if !confirmPassword.isEmpty && !passwordsMatch {
                Text("These passwords don't match yet.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.destructive)
                    .transition(.opacity)
            }
        }
        .animation(Motion.easeFast, value: confirmPassword)
    }

    // MARK: - Step 2

    private var stepTwo: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            CalibreTextField("Full name", text: $addressFullName, kind: .fullName)

            CalibreTextField(
                "Street address",
                text: $street,
                placeholder: "123 Meridian Ave",
                kind: .addressLine1
            )

            CalibreTextField("Apartment, suite (optional)", text: $apartment, kind: .addressLine2)

            CalibreTextField("City", text: $city, kind: .city)

            HStack(alignment: .top, spacing: Space.m) {
                CalibreTextField("ZIP", text: $zip, kind: .postalCode)
                CalibreTextField("State", text: $state, placeholder: "NY", kind: .state)
            }

            CalibreTextField("Country", text: $country, placeholder: "US", kind: .country)

            CalibreTextField("Phone", text: $phone, placeholder: "(415) 555-0134", kind: .phone)
                .phoneFormatted($phone)

            termsAcceptance
        }
    }

    // MARK: - Terms

    /// The same two site pages the About screen links to, opened the same way
    /// — one set of URLs, so what you accept here and what you can read there
    /// cannot drift apart.
    private static let termsURL = URL(string: "https://buycalibre.com/terms")!
    private static let privacyURL = URL(string: "https://buycalibre.com/privacy")!

    /// The acceptance `POST /auth/register` now requires. The client sends the
    /// boolean and nothing else: the server stamps the version it actually
    /// published, and a version the app guessed at would be a record of the
    /// wrong document.
    private var termsAcceptance: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Button {
                Haptics.shared.play(.selection)
                acceptedTerms.toggle()
            } label: {
                // The same two symbols the password checklist above uses, at a
                // size you can hit rather than one you can only read.
                Image(systemName: acceptedTerms ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(acceptedTerms ? Color.calibre.primary : Color.calibre.borderBright)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            // A bare circle is silent. The box carries the whole sentence as
            // its name and its tick as its value, so VoiceOver can say what is
            // being agreed to and whether it has been.
            .accessibilityLabel("I accept the Terms of Service and the Privacy Policy")
            .accessibilityValue(acceptedTerms ? "Checked" : "Not checked")
            .accessibilityAddTraits(acceptedTerms ? .isSelected : [])

            VStack(alignment: .leading, spacing: Space.xs) {
                Text("I accept the Terms of Service and the Privacy Policy.")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    // Word for word the box's own label, so leaving it in the
                    // tree only makes VoiceOver say the sentence twice before
                    // it reaches the two links. Sighted readers still see it.
                    .accessibilityHidden(true)
                legalLinks
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: Space.touchTarget)
        .animation(Motion.easeFast, value: acceptedTerms)
    }

    /// Side by side while they fit — which is every normal text size — and
    /// stacked once they don't, rather than the second one running off the
    /// right edge. Same shape as the login screen's sign-up prompt.
    private var legalLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.l) {
                termsLink
                privacyLink
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                termsLink
                privacyLink
            }
        }
    }

    private var termsLink: some View {
        Link("Read the Terms of Service", destination: Self.termsURL)
            .font(CalibreType.label)
            .tint(Color.calibre.primary)
    }

    private var privacyLink: some View {
        Link("Read the Privacy Policy", destination: Self.privacyURL)
            .font(CalibreType.label)
            .tint(Color.calibre.primary)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerButtons: some View {
        if step == 1 {
            Button {
                Haptics.shared.play(.press)
                advanceToAddress()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(!stepOneComplete)
        } else {
            VStack(spacing: Space.m) {
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
                        Text("Create account")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(!stepTwoComplete || busy)

                Button("Back to your details") {
                    errorMessage = nil
                    step = 1
                }
                .buttonStyle(.calibreGhost)
                .disabled(busy)
            }
        }
    }

    // MARK: - Validation

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var passwordSatisfiesRules: Bool {
        InputValidation.passwordMeetsRules(password)
    }

    private var stepOneComplete: Bool {
        InputValidation.isNonBlank(firstName)
            && InputValidation.isNonBlank(lastName)
            && InputValidation.isValidEmail(email)
            && InputValidation.isValidPhone(phone)
            && usernameState.isAvailable
            && passwordSatisfiesRules
            && passwordsMatch
    }

    private var stepTwoComplete: Bool {
        InputValidation.isNonBlank(addressFullName)
            && InputValidation.isNonBlank(street)
            && InputValidation.isNonBlank(city)
            && InputValidation.isNonBlank(zip)
            && InputValidation.isNonBlank(state)
            && InputValidation.isISO2CountryCode(country)
            // The backend rejects a registration without it, so it belongs
            // beside the other required fields rather than in a second gate
            // the submit path could forget to consult.
            && acceptedTerms
    }

    private func advanceToAddress() {
        errorMessage = nil
        if addressFullName.trimmingCharacters(in: .whitespaces).isEmpty {
            addressFullName = [firstName, lastName]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        step = 2
    }

    // MARK: - Username availability

    private func scheduleUsernameCheck(for candidate: String) {
        usernameCheckTask?.cancel()
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty else {
            usernameState = .idle
            return
        }
        guard trimmed.wholeMatch(of: /[A-Za-z0-9_]{3,32}/) != nil else {
            usernameState = .invalid("Use 3–32 letters, numbers, or underscore.")
            return
        }

        usernameState = .checking
        let client = services.client
        usernameCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            do {
                let result = try await client.send(Endpoint<UsernameAvailability>(
                    path: "/auth/username-availability",
                    query: [URLQueryItem(name: "username", value: trimmed)],
                    requiresAuth: false
                ))
                guard !Task.isCancelled, trimmed == username.trimmingCharacters(in: .whitespaces) else { return }
                usernameState = result.available
                    ? .available(result.message)
                    : .unavailable(result.message)
            } catch {
                guard !Task.isCancelled else { return }
                // Can't verify right now — stay quiet and let the backend
                // be the final word at submit time.
                usernameState = .idle
            }
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard stepOneComplete, stepTwoComplete, !busy else {
            if !stepOneComplete {
                errorMessage = "Some account details changed or still need attention. Go back and check them."
            }
            return
        }
        errorMessage = nil
        busy = true
        defer { busy = false }

        // Exact RegisterPayload shape — the backend rejects unknown fields,
        // and the address sub-object takes no phone.
        var address: [String: AuthJSON] = [
            "full_name": .string(addressFullName.trimmingCharacters(in: .whitespaces)),
            "line1": .string(street.trimmingCharacters(in: .whitespaces)),
            "city": .string(city.trimmingCharacters(in: .whitespaces)),
            "postal_code": .string(zip.trimmingCharacters(in: .whitespaces)),
            "country": .string(country.trimmingCharacters(in: .whitespaces).uppercased()),
        ]
        let apartmentTrimmed = apartment.trimmingCharacters(in: .whitespaces)
        if !apartmentTrimmed.isEmpty {
            address["line2"] = .string(apartmentTrimmed)
        }
        let stateTrimmed = state.trimmingCharacters(in: .whitespaces)
        if !stateTrimmed.isEmpty {
            address["region"] = .string(stateTrimmed)
        }

        let payload: [String: AuthJSON] = [
            "username": .string(username.trimmingCharacters(in: .whitespaces).lowercased()),
            "first_name": .string(firstName.trimmingCharacters(in: .whitespaces)),
            "last_name": .string(lastName.trimmingCharacters(in: .whitespaces)),
            "email": .string(email.trimmingCharacters(in: .whitespaces).lowercased()),
            "password": .string(password),
            "phone": .string(phone.trimmingCharacters(in: .whitespaces)),
            "address": .object(address),
            // The state of the box, not a literal `true`: the guard above
            // already refuses to submit without it, and encoding the flag
            // means the body can never claim more than the person did.
            "accepted_terms": .bool(acceptedTerms),
        ]

        var createdAccount = false
        let ok = await performAuthAction({
            createdAccount = try await session.authenticate(path: "/auth/register", payload: payload)
        }, onError: { errorMessage = $0 })

        if ok {
            if createdAccount {
                Analytics.signupCompleted(method: .email)
            }
            Haptics.shared.play(.success)
            toasts.show(
                title: "Welcome to Calibre",
                message: "Your account is ready.",
                tone: .success
            )
            if isModal {
                dismiss()
            }
        }
    }

    /// `.newPassword` in production; nil under UI tests, where the system's
    /// Automatic Strong Password cover would swallow synthesized typing.
    private static var newPasswordContentType: UITextContentType? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") { return nil }
        #endif
        return .newPassword
    }

    private func stepTransition(forward: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
            removal: .opacity
        )
    }
}

/// Where the live username check currently stands.
enum UsernameCheckState: Equatable {
    case idle
    case checking
    case invalid(String)
    case unavailable(String)
    case available(String)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var caption: (text: String, positive: Bool)? {
        switch self {
        case .idle, .checking:
            nil
        case .invalid(let message), .unavailable(let message):
            (message, false)
        case .available(let message):
            (message, true)
        }
    }
}
