import RewoundDesign
import RewoundKit
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
///
/// Registering by email is two steps — who you are, then where watches ship
/// (`RegisterScreen`). A social sign-in never passes through it, so those
/// accounts arrived with nowhere to ship to and were asked for an address for
/// the first time at checkout. This screen carries the same second step for an
/// account that has none.
///
/// **The address is not part of `profile_complete`.** That flag raises this
/// gate on three clients, and an address is not an identity field: an account
/// may hold several or none, and adding it to the contract would hold every
/// existing member here before they could open their own orders. Checkout stays
/// where an address is required — it already demands one and offers the saved
/// default — so this step can be skipped.
///
/// **The address is written before the profile patch, not after.** Completing
/// the profile is what makes `needsProfileCompletion` false, which is what
/// takes this whole view off the screen. Saving the address second would mean
/// racing the teardown of the view holding the fields.
struct ProfileCompletionView: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var step: Step = .details
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var username = ""
    @State private var addressFullName = ""
    @State private var street = ""
    @State private var apartment = ""
    @State private var city = ""
    @State private var state = ""
    @State private var zip = ""
    @State private var usernameError: String?
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var confirmSignOut = false
    @State private var prefilled = false
    /// How many addresses this account holds, or nil while nobody knows. A
    /// lookup that has not landed — or that failed — is not an account with no
    /// address, and treating it as one would make a member retype one they
    /// already have.
    @State private var savedAddressCount: Int?
    @FocusState private var focusedField: Field?

    private enum Step { case details, address }

    private enum Field { case firstName, lastName, phone, username, addressName, street, apartment, city, state, zip }

    /// What the account already had. A field that arrived filled is not
    /// required to change; an empty one is what the gate is here for.
    private var startingUser: CurrentUser? { session.user }

    private var email: String { startingUser?.email ?? "" }

    private var detailsComplete: Bool {
        InputValidation.isNonBlank(firstName)
            && InputValidation.isNonBlank(lastName)
            && InputValidation.isValidPhone(phone)
            && Self.usernameProblem(username) == nil
    }

    /// Only a lookup that came back empty asks for an address.
    private var asksForAddress: Bool { savedAddressCount == 0 }

    private var addressComplete: Bool {
        InputValidation.isNonBlank(addressFullName)
            && InputValidation.isNonBlank(street)
            && InputValidation.isNonBlank(city)
            && InputValidation.isNonBlank(state)
            && InputValidation.isNonBlank(zip)
    }

    private var canSubmit: Bool {
        guard !busy, detailsComplete else { return false }
        return step == .details || addressComplete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header

                BetaFillButton { person in
                    if step == .address {
                        addressFullName = [person.address.firstName, person.address.lastName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        street = person.address.line1
                        apartment = person.address.line2
                        city = person.address.city
                        state = person.address.region
                        zip = person.address.postalCode
                    } else {
                        firstName = person.account.firstName
                        lastName = person.account.lastName
                        phone = person.account.phone
                        username = person.account.username
                    }
                }

                if let errorMessage {
                    AuthErrorLine(message: errorMessage)
                }

                if step == .address {
                    addressFields
                } else {
                    fields
                    emailRow
                }

                VStack(spacing: Space.m) {
                    Button {
                        Haptics.shared.play(.press)
                        advance()
                    } label: {
                        RewoundBusyLabel(primaryActionTitle, busy: busy)
                    }
                    .buttonStyle(.rewound(.primary, fullWidth: true))
                    .disabled(!canSubmit)

                    if step == .address {
                        // Checkout asks for an address anyway, so holding a
                        // member here over one they have not decided on would
                        // be a second gate over something already gated.
                        Button("I'll add this at checkout") {
                            Haptics.shared.play(.press)
                            Task { await submit(withAddress: false) }
                        }
                        .buttonStyle(.rewoundGhost)
                        .disabled(busy)
                    }

                    Button("Sign out") {
                        Haptics.shared.play(.press)
                        confirmSignOut = true
                    }
                    .buttonStyle(.rewoundGhost)
                    .foregroundStyle(Color.rewound.mutedForeground)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .rewoundPageBackground()
        .animation(Motion.easeFast, value: errorMessage)
        .animation(Motion.easeFast, value: usernameError)
        // A full-screen presentation has no interactive dismissal to begin
        // with; saying so out loud keeps a later change to a sheet from
        // quietly reopening the door.
        .interactiveDismissDisabled()
        .alert("Sign out of Rewound?", isPresented: $confirmSignOut) {
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
            // Deliberately not `try` — a lookup that fails leaves the count
            // unknown, which is what keeps the address step from being offered
            // to somebody who already has one. But a gate raised the instant a
            // social sign-in lands is the first request of the session, and
            // one transient failure there (a cold connection, a token still
            // settling) would permanently skip the step for someone with no
            // address at all — the more common case a fresh gate meets. One
            // retry after a beat covers that without reopening the original
            // problem, which needed permanence, not speed.
            if let rows = try? await services.commerce.loadAddresses() {
                savedAddressCount = rows.count
            } else {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if let rows = try? await services.commerce.loadAddresses() {
                    savedAddressCount = rows.count
                }
            }
        }
    }

    // MARK: - Pieces

    private var primaryActionTitle: String {
        if step == .address { return "Save address" }
        return asksForAddress ? "Continue" : "Save and continue"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            RewoundWordmark(size: 28)
            Text(step == .address ? "Where should watches ship?" : "One more thing")
                .font(RewoundType.title)
                .foregroundStyle(Color.rewound.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(
                step == .address
                    ? "We use your address for shipping estimates, checkout totals, and delivery details. Rewound ships within the United States."
                    : "We're missing a few details we need before you can buy or sell. Your username is the name other members see; your number is only ever used for an order."
            )
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The same boxes, in the same order and with the same content types, as
    /// step two of registration — so iOS AutoFill offers the saved address here
    /// exactly as it does there.
    private var addressFields: some View {
        VStack(spacing: Space.l) {
            RewoundTextField("Full name", text: $addressFullName, kind: .fullName)
                .focused($focusedField, equals: .addressName)
                .submitLabel(.next)
                .onSubmit { focusedField = .street }

            RewoundTextField(
                "Street address",
                text: $street,
                placeholder: "123 Meridian Ave",
                kind: .addressLine1
            )
            .focused($focusedField, equals: .street)
            .submitLabel(.next)
            .onSubmit { focusedField = .apartment }

            RewoundTextField("Apartment, suite (optional)", text: $apartment, kind: .addressLine2)
                .focused($focusedField, equals: .apartment)
                .submitLabel(.next)
                .onSubmit { focusedField = .city }

            RewoundTextField("City", text: $city, kind: .city)
                .focused($focusedField, equals: .city)
                .submitLabel(.next)
                .onSubmit { focusedField = .zip }

            HStack(alignment: .top, spacing: Space.m) {
                RewoundTextField("ZIP", text: $zip, kind: .postalCode)
                    .focused($focusedField, equals: .zip)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .state }

                RewoundTextField("State", text: $state, placeholder: "NY", kind: .state)
                    .focused($focusedField, equals: .state)
                    .submitLabel(.done)
                    .onSubmit { if canSubmit { advance() } }
            }
        }
    }

    private var fields: some View {
        VStack(spacing: Space.l) {
            RewoundTextField(
                "First name",
                text: $firstName,
                placeholder: "Eytan",
                kind: .givenName
            )
            .focused($focusedField, equals: .firstName)
            .submitLabel(.next)
            .onSubmit { focusedField = .lastName }

            RewoundTextField(
                "Last name",
                text: $lastName,
                placeholder: "Erez",
                kind: .familyName
            )
            .focused($focusedField, equals: .lastName)
            .submitLabel(.next)
            .onSubmit { focusedField = .phone }

            RewoundTextField(
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

            RewoundTextField(
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
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.secondaryForeground)
                .accessibilityHidden(true)

            Text(email)
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: Space.touchTarget, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.m)
                .background(
                    // `secondary`, not `card`: the subtle fill is what says
                    // "read-only" without a disabled-looking gray.
                    Color.rewound.secondary,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Color.rewound.border, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Email, \(email)")

            Text("Your sign-in address. Contact us if it needs to change.")
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
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

    /// The one thing both the button and the keyboard's Done key call.
    ///
    /// On the details step for an account with no address it moves to the
    /// address step rather than saving, because saving is what dismisses this
    /// whole screen.
    private func advance() {
        if step == .details, asksForAddress {
            if let problem = Self.usernameProblem(username) {
                usernameError = problem
                focusedField = .username
                Haptics.shared.play(.error)
                return
            }
            usernameError = nil
            errorMessage = nil
            if InputValidation.trimmed(addressFullName).isEmpty {
                addressFullName = [firstName, lastName]
                    .map { InputValidation.trimmed($0) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            step = .address
            focusedField = .street
            return
        }
        Task { await submit() }
    }

    private func submit(withAddress: Bool = true) async {
        guard !busy else { return }
        errorMessage = nil

        if let problem = Self.usernameProblem(username) {
            usernameError = problem
            focusedField = .username
            step = .details
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

        // First, because the profile patch below is what takes this screen off
        // the display: an address written after it would be typed into a view
        // that is already being torn down. A refusal here stops the sequence
        // with the boxes still on screen and the server's sentence beside them.
        if withAddress, step == .address {
            do {
                _ = try await services.commerce.createAddress(addressPayload())
            } catch let error as APIError {
                Haptics.shared.play(.error)
                errorMessage = error.authMessage
                Observability.log(.warning, "profile_completion_address_failed")
                return
            } catch {
                Haptics.shared.play(.error)
                errorMessage = "We could not save that address. Please try again."
                Observability.log(.warning, "profile_completion_address_failed")
                return
            }
        }

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
                // Back to the boxes the refusal is about, or the member is
                // looking at an address form with an error about a username.
                step = .details
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

    /// The first address on the account, so it is the default both to ship to
    /// and to bill — the same thing registration's second step writes.
    private func addressPayload() -> AddressPayload {
        let apartmentTrimmed = InputValidation.trimmed(apartment)
        let full = InputValidation.trimmed(addressFullName)
        let parts = full.split(separator: " ", maxSplits: 1).map(String.init)
        return AddressPayload(
            label: "Primary",
            firstName: parts.first ?? full,
            lastName: parts.count > 1 ? parts[1] : "",
            fullName: full,
            // The number the courier calls, which is the one just confirmed
            // above rather than a second question.
            phone: PhoneFormatter.nationalDigits(phone) ?? InputValidation.trimmed(phone),
            line1: InputValidation.trimmed(street),
            line2: apartmentTrimmed.isEmpty ? nil : apartmentTrimmed,
            city: InputValidation.trimmed(city),
            region: InputValidation.trimmed(state).uppercased(),
            postalCode: InputValidation.trimmed(zip),
            country: "US",
            isDefaultShipping: true,
            isDefaultBilling: true
        )
    }
}
