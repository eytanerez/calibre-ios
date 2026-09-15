import CalibreDesign
import CalibreKit
import SwiftUI

/// The gate a signed-in member meets when the server says their account is
/// missing something a purchase needs.
///
/// It exists because a social sign-in is one tap: Apple and Google hand over
/// an email and, on the first authorization only, a name — no phone at all,
/// and a username invented from the email local part that nobody chose. Those
/// are the handle other members see and the number an order is confirmed to,
/// so the account is authenticated and still not usable.
///
/// Three things about its shape are deliberate:
///
/// * **It cannot be dismissed.** There is no close control and no swipe: the
///   product decision is that a member whose payload says
///   `profile_complete: false` finishes the form. What raises it is
///   `AuthSession.needsProfileCompletion` — the one predicate both the
///   sign-in path and the launch-time restore consult.
/// * **Signing out is always possible.** A gate with no exit at all is a
///   trapped account, so the way out is the honest one rather than a hidden
///   "skip" that leaves the same hole.
/// * **Only what is missing is asked for.** Every field is prefilled from the
///   session, and a box that arrived full is a box the member can leave alone.
///   The submit sends only what actually changed — the endpoint writes exactly
///   what it is given.
struct ProfileCompletionView: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var username = ""
    @State private var usernameError: String?
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var confirmSignOut = false
    @State private var prefilled = false
    @FocusState private var focusedField: Field?

    private enum Field { case firstName, lastName, phone, username }

    /// What the account already had. A field that arrived filled is not
    /// required to change; an empty one is what the gate is here for.
    private var startingUser: CurrentUser? { session.user }

    private var email: String { startingUser?.email ?? "" }

    private var canSubmit: Bool {
        !busy
            && InputValidation.isNonBlank(firstName)
            && InputValidation.isNonBlank(lastName)
            && InputValidation.isValidPhone(phone)
            && Self.usernameProblem(username) == nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                BetaFillButton { person in
                    firstName = person.account.firstName
                    lastName = person.account.lastName
                    phone = person.account.phone
                    username = person.account.username
                }

                if let errorMessage {
                    AuthErrorLine(message: errorMessage)
                }

                fields

                emailRow

                VStack(spacing: Space.m) {
                    Button {
                        Haptics.shared.play(.press)
                        Task { await submit() }
                    } label: {
                        CalibreBusyLabel("Save and continue", busy: busy)
                    }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(!canSubmit)

                    Button("Sign out") {
                        Haptics.shared.play(.press)
                        confirmSignOut = true
                    }
                    .buttonStyle(.calibreGhost)
                    .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .calibrePageBackground()
        .animation(Motion.easeFast, value: errorMessage)
        .animation(Motion.easeFast, value: usernameError)
        // A full-screen presentation has no interactive dismissal to begin
        // with; saying so out loud keeps a later change to a sheet from
        // quietly reopening the door.
        .interactiveDismissDisabled()
        .alert("Sign out of Calibre?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task {
                    let signingOutUserID = session.user?.id
                    await services.push.unregisterOnSignOut()
                    guard session.user?.id == signingOutUserID else { return }
                    await session.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can keep browsing as a guest, and sign back in any time.")
        }
        .task {
            // Once. `session.user` is replaced by a successful save, and
            // re-running this would overwrite whatever the member had typed
            // into a field the server has not accepted yet.
            guard !prefilled else { return }
            prefilled = true
            firstName = startingUser?.firstName ?? ""
            lastName = startingUser?.lastName ?? ""
            phone = PhoneFormatter.format(startingUser?.phone ?? "")
            username = startingUser?.username ?? ""
            focusedField = firstFocus
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            CalibreWordmark(size: 28)
            Text("One more thing")
                .font(CalibreType.title)
                .foregroundStyle(Color.calibre.foreground)
                .accessibilityAddTraits(.isHeader)
            Text("We're missing a few details we need before you can buy or sell. Your username is the name other members see; your number is only ever used for an order.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(spacing: Space.l) {
            CalibreTextField(
                "First name",
                text: $firstName,
                placeholder: "Eytan",
                kind: .givenName
            )
            .focused($focusedField, equals: .firstName)
            .submitLabel(.next)
            .onSubmit { focusedField = .lastName }

            CalibreTextField(
                "Last name",
                text: $lastName,
                placeholder: "Erez",
                kind: .familyName
            )
            .focused($focusedField, equals: .lastName)
            .submitLabel(.next)
            .onSubmit { focusedField = .phone }

            CalibreTextField(
                "Phone",
                text: $phone,
                placeholder: "(415) 555-0134",
                kind: .phone
            )
            // The app's one phone convention — formats under the caret, US
            // only, and unwinds cleanly on backspace (see InputFormatting).
            .phoneFormatted($phone)
            .focused($focusedField, equals: .phone)
            .submitLabel(.next)
            .onSubmit { focusedField = .username }

            CalibreTextField(
                "Username",
                text: $username,
                placeholder: "eytan",
                error: usernameError,
                kind: .username
            )
            .focused($focusedField, equals: .username)
            .submitLabel(.done)
            .onSubmit { if canSubmit { Task { await submit() } } }
            // Lowercased as it is typed rather than at submit: the backend
            // lowercases anyway, and a member who typed "Eytan" should see
            // the handle they are actually getting.
            .onChange(of: username) { _, newValue in
                let lowered = newValue.lowercased()
                if lowered != newValue { username = lowered }
                // The server's verdict is stale the moment the box changes.
                usernameError = nil
            }
        }
    }

    /// The address the account is keyed to. Shown because the form claims to
    /// be the whole picture and would be lying without it, and read-only
    /// because changing a sign-in email is a different, verified thing.
    private var emailRow: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Email")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .accessibilityHidden(true)

            Text(email)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: Space.touchTarget, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.m)
                .background(
                    // `secondary`, not `card`: the subtle fill is what says
                    // "read-only" without a disabled-looking grey.
                    Color.calibre.secondary,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Color.calibre.border, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Email, \(email)")

            Text("Your sign-in address. Contact us if it needs to change.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    /// The first box that is actually empty, so the keyboard opens on the
    /// thing being asked for rather than on a name the account already had.
    private var firstFocus: Field? {
        if !InputValidation.isNonBlank(startingUser?.firstName ?? "") { return .firstName }
        if !InputValidation.isNonBlank(startingUser?.lastName ?? "") { return .lastName }
        if !InputValidation.isNonBlank(startingUser?.phone ?? "") { return .phone }
        return .username
    }

    // MARK: - Username

    /// The backend's rule, checked here so a bad handle costs no round trip:
    /// lowercase letters, digits and underscore, three to thirty-two of them.
    /// The server stays the authority on whether it is *taken*.
    static func usernameProblem(_ raw: String) -> String? {
        let candidate = InputValidation.trimmed(raw).lowercased()
        guard !candidate.isEmpty else { return "Pick a username." }
        guard (3...32).contains(candidate.count) else {
            return "Use 3–32 letters, numbers, or underscore."
        }
        guard candidate.allSatisfy({ $0.isASCII && ($0.isLowercase && $0.isLetter || $0.isNumber || $0 == "_") }) else {
            return "Use letters, numbers, or underscore only."
        }
        return nil
    }

    // MARK: - Submit

    private func submit() async {
        guard !busy else { return }
        errorMessage = nil

        if let problem = Self.usernameProblem(username) {
            usernameError = problem
            focusedField = .username
            Haptics.shared.play(.error)
            return
        }
        usernameError = nil

        // Only what moved. Comparing against the user the session is holding
        // is what keeps a member who changed one box from re-sending three,
        // and what makes re-sending their own username a no-op rather than a
        // conflict check the server has to run.
        let fields = changedFields()
        guard !fields.isEmpty else {
            // Nothing to send and the server still says incomplete — the only
            // honest thing is to say the boxes need filling, not to spin.
            errorMessage = "Fill in the details above to continue."
            return
        }

        busy = true
        defer { busy = false }

        do {
            let updated = try await services.account.completeProfile(fields)
            session.replaceUser(with: updated)
            Haptics.shared.play(.success)
            if updated.profileComplete == false {
                // The server accepted the write and still says incomplete.
                // Something is missing that this form did not cover, and
                // pretending otherwise would drop the member into a gate that
                // reopens on the next launch with no explanation.
                errorMessage = "Some details are still missing. Check the fields above."
            } else {
                Observability.log(.info, "profile_completion_saved")
                services.toasts.show(
                    title: "You're all set",
                    message: "Thanks — that's everything we needed.",
                    tone: .success
                )
            }
        } catch let error as APIError {
            Haptics.shared.play(.error)
            if error.httpStatus == ProfileCompletionStatus.usernameTaken {
                usernameError = "That username is taken."
                focusedField = .username
            } else {
                // 400 and everything else: the backend names the field it
                // refused, in its own words. Inventing copy over the top of
                // that would tell the member less than the server did.
                errorMessage = error.authMessage
            }
            Observability.log(.warning, "profile_completion_failed: \(error.httpStatus.map(String.init) ?? "no status")")
        } catch {
            Haptics.shared.play(.error)
            errorMessage = "Something went wrong. Please try again."
            Observability.log(.warning, "profile_completion_failed")
        }
    }

    /// The patch body: a field appears only when what is in the box differs
    /// from what the session already holds.
    private func changedFields() -> ProfileCompletionFields {
        var fields = ProfileCompletionFields()
        let user = startingUser

        let first = InputValidation.trimmed(firstName)
        if !first.isEmpty, first != (user?.firstName ?? "") { fields.firstName = first }

        let last = InputValidation.trimmed(lastName)
        if !last.isEmpty, last != (user?.lastName ?? "") { fields.lastName = last }

        // Compared on digits, not on punctuation: the server stores a
        // normalised number and the field shows a formatted one, so a straight
        // string comparison would call every unchanged phone "changed".
        let typedDigits = phone.filter(\.isNumber)
        let heldDigits = (user?.phone ?? "").filter(\.isNumber)
        if !typedDigits.isEmpty, typedDigits != heldDigits {
            fields.phone = PhoneFormatter.nationalDigits(phone) ?? InputValidation.trimmed(phone)
        }

        let handle = InputValidation.trimmed(username).lowercased()
        if !handle.isEmpty, handle != (user?.username ?? "").lowercased() { fields.username = handle }

        return fields
    }
}
