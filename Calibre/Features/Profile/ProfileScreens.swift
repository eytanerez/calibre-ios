import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

/// Destinations reachable from the You tab's account list. Kept local to the
/// tab (they aren't cross-tab routes), resolved by a `navigationDestination`
/// on the You screen.
enum ProfileDestination: Hashable {
    case profile
    case addresses
    case paymentMethod
    case notifications
    case changePassword
    case deleteAccount
}

// MARK: - About

/// About Calibre — the quiet footer: what the marketplace is, version, and
/// links to the web legal pages.
struct AboutScreen: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.s) {
                    CalibreWordmark(size: 32)
                    Text("A marketplace for authenticated luxury watches. Every watch is inspected by our watchmakers before it reaches you.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                VStack(spacing: 0) {
                    NavigationLink {
                        MarketplaceGuideScreen()
                    } label: {
                        aboutRow("How it works")
                    }
                    .buttonStyle(PressableStyle())
                    Divider().overlay(Color.calibre.border)
                    Link(destination: URL(string: "https://buycalibre.com/terms")!) {
                        aboutRow("Terms of Service")
                    }
                    Divider().overlay(Color.calibre.border)
                    Link(destination: URL(string: "https://buycalibre.com/privacy")!) {
                        aboutRow("Privacy Policy")
                    }
                }
                .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))

                Text("Version \(version)")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.placeholder)
            }
            .padding(Space.margin)
        }
        .background(Color.calibre.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aboutRow(_ title: String) -> some View {
        HStack {
            Text(title).font(CalibreType.bodyMedium).foregroundStyle(Color.calibre.foreground)
            Spacer()
            Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: Space.touchTarget + 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Profile (login info)

/// Account overview and login information.
struct ProfileScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var profile: Profile?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if let profile {
                    header(profile)
                    SpecList([
                        ("Email", profile.email),
                        ("Username", "@\(profile.username)"),
                        ("Phone", profile.phone ?? "—"),
                        ("Member since", profile.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "—"),
                    ])
                } else if failed {
                    EmptyState(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: "Couldn't load your profile",
                        message: "Check your connection and try again.",
                        actionTitle: "Try again"
                    ) { Task { await load() } }
                    .padding(.top, Space.xxl)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Space.xxl)
                }
            }
            .padding(Space.margin)
        }
        .background(Color.calibre.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            profile = try await services.client.accountProfile()
        } catch {
            if profile == nil { failed = true }
        }
    }

    private func header(_ profile: Profile) -> some View {
        HStack(spacing: Space.l) {
            AvatarInitial(name: profile.username, size: .l)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(profile.username)").font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
                Text(profile.email).font(CalibreType.body).foregroundStyle(Color.calibre.mutedForeground)
            }
        }
    }
}

// MARK: - Addresses

struct AddressesScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    @State private var addresses: [Address] = []
    @State private var loaded = false
    @State private var editing: Address?
    @State private var showNew = false

    var body: some View {
        Group {
            if addresses.isEmpty && loaded {
                EmptyState(
                    icon: "mappin.and.ellipse",
                    title: "No addresses yet",
                    message: "Add a shipping address so checkout is one tap.",
                    actionTitle: "Add address"
                ) { showNew = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.m) {
                        ForEach(addresses) { address in
                            Button { editing = address } label: { AddressCard(address: address) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(Space.margin)
                }
            }
        }
        .background(Color.calibre.background)
        .navigationTitle("Addresses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNew = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add address")
            }
        }
        .sheet(isPresented: $showNew) {
            AddressForm(existing: nil) { await reload() }
        }
        .sheet(item: $editing) { address in
            AddressForm(existing: address) { await reload() }
        }
        .task { await reload() }
    }

    private func reload() async {
        addresses = (try? await services.commerce.loadAddresses()) ?? []
        loaded = true
    }
}

private struct AddressCard: View {
    let address: Address
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(address.fullName ?? [address.firstName, address.lastName].compactMap { $0 }.joined(separator: " "))
                    .font(CalibreType.bodyMedium).foregroundStyle(Color.calibre.foreground)
                Spacer()
                if address.isDefaultShipping { StatusBadge("Default", tone: .info) }
            }
            Text(address.line1).font(CalibreType.body).foregroundStyle(Color.calibre.mutedForeground)
            Text([address.city, address.region, address.postalCode].compactMap { $0 }.joined(separator: ", "))
                .font(CalibreType.body).foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }
}

private struct AddressForm: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    let existing: Address?
    let onSave: () async -> Void

    @State private var fullName = ""
    @State private var line1 = ""
    @State private var line2 = ""
    @State private var city = ""
    @State private var region = ""
    @State private var postalCode = ""
    @State private var country = "US"
    @State private var phone = ""
    @State private var makeDefault = true
    @State private var saving = false

    var body: some View {
        SheetScaffold(title: existing == nil ? "Add address" : "Edit address", detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    CalibreTextField("Full name", text: $fullName)
                    CalibreTextField("Street", text: $line1)
                    CalibreTextField("Apt, suite (optional)", text: $line2)
                    CalibreTextField("City", text: $city)
                    HStack(spacing: Space.m) {
                        CalibreTextField("State", text: $region)
                        CalibreTextField("ZIP", text: $postalCode).keyboardType(.numbersAndPunctuation)
                    }
                    CalibreTextField(
                        "Country code",
                        text: $country,
                        placeholder: "2-letter, e.g. US",
                        error: InputValidation.isISO2CountryCode(country) || country.isEmpty ? nil : "Use a 2-letter code like US or CA"
                    )
                    CalibreTextField(
                        "Phone",
                        text: $phone,
                        error: InputValidation.isValidPhone(phone, required: false)
                            ? nil
                            : "Enter a valid phone number, or leave it blank."
                    )
                    .keyboardType(.phonePad)
                    Toggle("Set as default shipping address", isOn: $makeDefault)
                        .font(CalibreType.body).tint(Color.calibre.primary)
                    Button(saving ? "Saving…" : "Save address") { Task { await save() } }
                        .buttonStyle(.calibre(.primary, fullWidth: true))
                        .disabled(!isValid || saving)
                    if let existing {
                        Button(role: .destructive) { Task { await delete(existing) } } label: {
                            Text("Delete address").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.calibre(.ghost, fullWidth: true))
                        .foregroundStyle(Color.calibre.destructive)
                        .disabled(saving)
                    }
                }
                .padding(Space.margin)
            }
        }
        .onAppear(perform: prefill)
    }

    private var isValid: Bool {
        InputValidation.isNonBlank(fullName)
            && InputValidation.isNonBlank(line1)
            && InputValidation.isNonBlank(city)
            && InputValidation.isNonBlank(postalCode)
            && InputValidation.isISO2CountryCode(country)
            && InputValidation.isValidPhone(phone, required: false)
    }

    private func prefill() {
        guard let existing else { return }
        fullName = existing.fullName ?? [existing.firstName, existing.lastName].compactMap { $0 }.joined(separator: " ")
        line1 = existing.line1
        line2 = existing.line2 ?? ""
        city = existing.city
        region = existing.region ?? ""
        postalCode = existing.postalCode
        country = existing.country
        phone = existing.phone ?? ""
        makeDefault = existing.isDefaultShipping
    }

    private func save() async {
        guard isValid, !saving else { return }
        saving = true
        defer { saving = false }
        let payload = AddressPayload(
            fullName: InputValidation.trimmed(fullName),
            phone: InputValidation.isNonBlank(phone) ? InputValidation.trimmed(phone) : nil,
            line1: InputValidation.trimmed(line1),
            line2: InputValidation.isNonBlank(line2) ? InputValidation.trimmed(line2) : nil,
            city: InputValidation.trimmed(city),
            region: InputValidation.isNonBlank(region) ? InputValidation.trimmed(region) : nil,
            postalCode: InputValidation.trimmed(postalCode),
            country: InputValidation.trimmed(country).uppercased(),
            isDefaultShipping: makeDefault
        )
        do {
            if let existing {
                _ = try await services.commerce.updateAddress(id: existing.id, payload)
            } else {
                _ = try await services.commerce.createAddress(payload)
            }
            await onSave()
            Haptics.shared.play(.success)
            dismiss()
        } catch {
            toasts.show(title: "Couldn't save address", message: error.orderMessage, tone: .error)
        }
    }

    private func delete(_ address: Address) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await services.commerce.deleteAddress(id: address.id)
            await onSave()
            dismiss()
        } catch {
            toasts.show(title: "Couldn't delete", message: error.orderMessage, tone: .error)
        }
    }
}

// MARK: - Payment method

struct PaymentMethodScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    @State private var method: SavedPaymentMethod?
    @State private var canRemove = true
    @State private var removeBlockedReason: String?
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var isPreparingSetup = false
    @State private var isSyncingAfterSetup = false
    @State private var paymentSheet: PaymentSheet?
    @State private var presentingPaymentSheet = false
    /// Bumped by every operation that ends up writing `method`/`canRemove`/
    /// `removeBlockedReason` — a late result from a superseded load, poll, or
    /// removal checks this before committing so it can never clobber a newer
    /// one (e.g. a slow post-setup poll finishing after the user already hit
    /// Remove).
    @State private var stateGeneration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                if let method {
                    VStack(alignment: .leading, spacing: Space.s) {
                        HStack(spacing: Space.m) {
                            IconTile(systemName: "creditcard")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(method.brand?.capitalized ?? "Card") •••• \(method.last4 ?? "----")")
                                    .font(CalibreType.bodyMedium).foregroundStyle(Color.calibre.foreground)
                                if let m = method.expMonth, let y = method.expYear {
                                    Text("Expires \(m)/\(y % 100)").font(CalibreType.caption)
                                        .foregroundStyle(Color.calibre.mutedForeground)
                                }
                            }
                            Spacer()
                        }
                        .padding(Space.l)
                        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))

                        Button {
                            Task { await startAddOrReplaceCard() }
                        } label: {
                            HStack(spacing: Space.s) {
                                Text("Replace card")
                                if isPreparingSetup || isSyncingAfterSetup {
                                    ProgressView().tint(Color.calibre.foreground)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.calibre(.secondary, fullWidth: true))
                        .disabled(isPreparingSetup || isSyncingAfterSetup)

                        if canRemove {
                            Button(role: .destructive) { Task { await removeCard() } } label: {
                                Text("Remove card").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.calibre(.ghost, fullWidth: true))
                            .foregroundStyle(Color.calibre.destructive)
                            .disabled(isPreparingSetup || isSyncingAfterSetup)
                        } else if let removeBlockedReason {
                            Text(removeBlockedReason)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                        }
                    }
                } else if loadFailed {
                    // Distinct from "no card on file" — a failed fetch used to
                    // render identically to a genuinely empty account, with no
                    // way to retry short of leaving and re-entering the screen.
                    EmptyState(
                        icon: "wifi.slash",
                        title: "Couldn't load your payment method",
                        message: "Check your connection and try again.",
                        actionTitle: "Try again"
                    ) {
                        Task { await loadMethod() }
                    }
                } else if loaded {
                    EmptyState(
                        icon: "creditcard",
                        title: "No card on file",
                        message: "Add a card here, at checkout, or before making an offer — Calibre places a $250 hold to confirm you're serious.",
                        actionTitle: isPreparingSetup || isSyncingAfterSetup ? nil : "Add card"
                    ) {
                        Task { await startAddOrReplaceCard() }
                    }
                }
                CalloutBand(
                    icon: "lock.shield",
                    message: "Your card details are handled by Stripe. Calibre never sees your full card number."
                )
            }
            .padding(Space.margin)
        }
        .refreshable {
            // While the post-setup poll owns the authoritative "did the
            // webhook land yet" answer, a manual refresh must not race it —
            // sharing `stateGeneration` would let a fast refresh silently
            // invalidate a later `.ready` result and drop the "Card saved"
            // confirmation. The poll is short (bounded backoff, seconds),
            // and this screen already shows a spinner on the Replace/Add
            // button while it runs, so ignoring a pull here isn't a dead end
            // — refresh works again the moment the poll settles.
            guard !isSyncingAfterSetup else { return }
            await loadMethod()
        }
        .background(Color.calibre.background)
        .background {
            // Invisible leaf so creating the sheet doesn't re-identify the
            // screen's content — same pattern as Checkout's payment sheet host.
            if let paymentSheet {
                Color.clear
                    .paymentSheet(isPresented: $presentingPaymentSheet, paymentSheet: paymentSheet) { result in
                        handleSetupResult(result)
                    }
            }
        }
        .navigationTitle("Payment method")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMethod()
        }
    }

    private func loadMethod() async {
        stateGeneration += 1
        let generation = stateGeneration
        loadFailed = false
        do {
            let info = try await services.commerce.paymentMethod()
            guard generation == stateGeneration else { return }
            apply(info)
        } catch {
            guard generation == stateGeneration else { return }
            loadFailed = true
        }
        guard generation == stateGeneration else { return }
        loaded = true
    }

    private func apply(_ info: PaymentMethodInfo) {
        method = info.paymentMethod
        canRemove = info.canRemove
        removeBlockedReason = info.removeBlockedReason
        loadFailed = false
    }

    /// Real Add/Replace: a SetupIntent from the same `/billing/setup-intent`
    /// endpoint Checkout's PaymentIntent flow rides alongside, confirmed with
    /// PaymentSheet's setup mode using the *mobile* CustomerSession — not a
    /// locally fabricated card.
    private func startAddOrReplaceCard() async {
        guard !isPreparingSetup, !isSyncingAfterSetup else { return }
        isPreparingSetup = true
        defer { isPreparingSetup = false }
        do {
            let intent = try await services.commerce.setupIntent()
            STPAPIClient.shared.publishableKey = intent.publishableKey
            let configuration = CalibreStripe.configuration(
                customerID: intent.customerId,
                customerSessionClientSecret: intent.customerSessionMobile?.clientSecret
            )
            paymentSheet = PaymentSheet(
                setupIntentClientSecret: intent.setupIntent.clientSecret,
                configuration: configuration
            )
            presentingPaymentSheet = true
        } catch {
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't start adding a card", message: error.orderMessage, tone: .error)
        }
    }

    private func handleSetupResult(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            Task { await pollForConfirmedCard() }
        case .canceled:
            break
        case .failed(let error):
            Haptics.shared.play(.error)
            toasts.show(title: "Couldn't add card", message: CalibreStripe.failureMessage(for: error), tone: .error)
        }
    }

    /// PaymentSheet reporting `.completed` only means Stripe accepted the
    /// card — the backend's webhook that actually records it as the buyer's
    /// default lands asynchronously afterward. Poll with backoff for the
    /// card to change rather than trusting an immediate re-fetch, which would
    /// often still show the old (or no) card and falsely announce success.
    private func pollForConfirmedCard() async {
        stateGeneration += 1
        let generation = stateGeneration
        let previousID = method?.id
        isSyncingAfterSetup = true
        defer { isSyncingAfterSetup = false }

        let outcome = await poll(
            maxAttempts: 6,
            delay: { attempt in .seconds(min(1 << attempt, 8)) },
            fetch: { try await services.commerce.paymentMethod() },
            isReady: { info in
                guard let newMethod = info.paymentMethod else { return false }
                return newMethod.id != previousID
            }
        )

        guard generation == stateGeneration else { return }
        switch outcome {
        case .ready(let info):
            apply(info)
            Haptics.shared.play(.save)
            toasts.show(title: "Card saved", tone: .success)
        case .timedOut(let info):
            if let info { apply(info) }
            toasts.show(
                title: "Card submitted",
                message: "It's still syncing on our end — pull to refresh in a moment, or check back shortly.",
                tone: .neutral
            )
        }
    }

    private func removeCard() async {
        stateGeneration += 1
        let generation = stateGeneration
        do {
            try await services.commerce.deletePaymentMethod()
            guard generation == stateGeneration else { return }
            method = nil
            canRemove = true
            removeBlockedReason = nil
            Haptics.shared.play(.selection)
            toasts.show(title: "Card removed")
        } catch {
            guard generation == stateGeneration else { return }
            toasts.show(title: "Couldn't remove card", message: error.orderMessage, tone: .error)
        }
    }
}

// MARK: - Notification settings

struct NotificationSettingsScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    @State private var prefs: NotificationPreferences?
    @State private var pushEnabled = false
    @State private var pushDenied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                if !pushEnabled {
                    pushPrimer
                        .padding(.bottom, Space.m)
                }
                if let prefs {
                    toggle("Offers", "Counters, accepts, and declines on your offers", prefs.offerUpdates) {
                        NotificationPreferencesPatch(offerUpdates: $0)
                    }
                    toggle("Orders", "Purchases, authentication, and payouts", prefs.orderUpdates) {
                        NotificationPreferencesPatch(orderUpdates: $0)
                    }
                    toggle("Tracking", "Shipping and delivery updates", prefs.trackingUpdates) {
                        NotificationPreferencesPatch(trackingUpdates: $0)
                    }
                    toggle("Messages", "Replies from Calibre support", prefs.messageUpdates) {
                        NotificationPreferencesPatch(messageUpdates: $0)
                    }
                    toggle("Saved watches", "Price drops on watches you've saved", prefs.watchlistAlerts) {
                        NotificationPreferencesPatch(watchlistAlerts: $0)
                    }
                    toggle("Market", "New arrivals and market notes", prefs.marketUpdates) {
                        NotificationPreferencesPatch(marketUpdates: $0)
                    }
                    toggle("Security", "Sign-ins and account changes", prefs.securityAlerts) {
                        NotificationPreferencesPatch(securityAlerts: $0)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Space.xxl)
                }
            }
            .padding(Space.margin)
        }
        .background(Color.calibre.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            prefs = try? await services.account.loadPreferences()
            await refreshPushStatus()
        }
    }

    /// Prompt to turn on system notifications — the category toggles below only
    /// matter once push delivery is authorized.
    private var pushPrimer: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(pushDenied ? "Notifications are off" : "Turn on notifications")
                .font(CalibreType.bodySemiBold)
                .foregroundStyle(Color.calibre.foreground)
            Text(pushDenied
                 ? "Enable notifications for Calibre in Settings to know the moment a seller responds or an order moves."
                 : "Know the second a seller responds, an order ships, or a saved watch drops in price.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
            Button(pushDenied ? "Open Settings" : "Enable notifications") {
                Task { await enablePush() }
            }
            .buttonStyle(.calibre(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Color.calibre.accent.opacity(0.4), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func refreshPushStatus() async {
        let status = await services.push.authorizationStatus()
        pushEnabled = status == .authorized || status == .provisional
        pushDenied = status == .denied
    }

    private func enablePush() async {
        if pushDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }
        _ = await services.push.requestAuthorization()
        await refreshPushStatus()
    }

    @ViewBuilder
    private func toggle(_ title: String, _ subtitle: String, _ value: Bool, patch: @escaping (Bool) -> NotificationPreferencesPatch) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in Task { await update(patch(newValue)) } }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(CalibreType.bodyMedium).foregroundStyle(Color.calibre.foreground)
                Text(subtitle).font(CalibreType.caption).foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .tint(Color.calibre.primary)
        .padding(.vertical, Space.s)
        Divider().overlay(Color.calibre.border)
    }

    private func update(_ patch: NotificationPreferencesPatch) async {
        do {
            prefs = try await services.account.updatePreferences(patch)
            Haptics.shared.play(.selection)
        } catch {
            toasts.show(title: "Couldn't update", message: error.orderMessage, tone: .error)
            // Re-sync from the server, but never wipe the loaded prefs on a
            // failed reload — that would strand the screen on a spinner.
            if let fresh = try? await services.account.loadPreferences() {
                prefs = fresh
            }
        }
    }
}

// MARK: - Change password

struct ChangePasswordScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                CalibreTextField("Current password", text: $current, isSecure: true)
                CalibreTextField(
                    "New password",
                    text: $newPassword,
                    error: newPassword.isEmpty || InputValidation.passwordMeetsRules(newPassword)
                        ? nil
                        : "Use 8+ characters with a capital letter and a number.",
                    isSecure: true
                )
                CalibreTextField("Confirm new password", text: $confirm, error: mismatch ? "Passwords don't match" : nil, isSecure: true)
                if let errorText {
                    Text(errorText).font(CalibreType.caption).foregroundStyle(Color.calibre.destructive)
                }
                Button(saving ? "Saving…" : "Update password") { Task { await save() } }
                    .buttonStyle(.calibre(.primary, fullWidth: true))
                    .disabled(!isValid || saving)
            }
            .padding(Space.margin)
        }
        .background(Color.calibre.background)
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mismatch: Bool { !confirm.isEmpty && confirm != newPassword }
    private var isValid: Bool {
        !current.isEmpty
            && InputValidation.passwordMeetsRules(newPassword)
            && newPassword == confirm
    }

    private func save() async {
        guard isValid, !saving else { return }
        saving = true
        errorText = nil
        defer { saving = false }
        do {
            try await services.account.changePassword(current: current, new: newPassword)
            Haptics.shared.play(.success)
            toasts.show(title: "Password updated", tone: .success)
            dismiss()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? "Couldn't update password."
            Haptics.shared.play(.error)
        }
    }
}

// MARK: - Delete account

struct DeleteAccountScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    @State private var confirming = false
    @State private var working = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text("Delete your account")
                    .font(CalibreType.sectionTitle).foregroundStyle(Color.calibre.foreground)
                Text("Your account is scheduled for deletion after a 30-day grace period. Sign in any time within those 30 days to cancel and keep your account.")
                    .font(CalibreType.body).foregroundStyle(Color.calibre.mutedForeground)
                CalloutBand(
                    icon: "exclamationmark.triangle",
                    message: "Active orders and offers must be resolved before your account can be fully removed."
                )
                Button(role: .destructive) { confirming = true } label: {
                    Text(working ? "Working…" : "Request account deletion").frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.destructive, fullWidth: true))
                .disabled(working)
            }
            .padding(Space.margin)
        }
        .background(Color.calibre.background)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete your Calibre account?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete my account", role: .destructive) { Task { await requestDeletion() } }
            Button("Keep my account", role: .cancel) {}
        } message: {
            Text("You'll have 30 days to change your mind before it's permanent.")
        }
    }

    private func requestDeletion() async {
        guard !working else { return }
        working = true
        defer { working = false }
        do {
            _ = try await services.account.requestDeletion()
            toasts.show(title: "Deletion scheduled", message: "Sign in within 30 days to cancel.", tone: .success)
        } catch {
            toasts.show(title: "Couldn't schedule deletion", message: error.orderMessage, tone: .error)
        }
    }
}
