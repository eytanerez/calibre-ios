import RewoundDesign
import RewoundKit
import SwiftUI

/// The dealer application. Two fields here — the legal name the business is
/// registered under and its country — then the embedded verification step,
/// which collects the EIN on Stripe's own form. If Stripe confirms a
/// registered company, dealer status is granted straight away; if it cannot,
/// a person at Rewound reviews the application and decides.
///
/// This is the one seller-facing screen that names Stripe, because naming the
/// verifier is the honest way to say where the business details go and why
/// Rewound never sees the banking side of them.
struct DealerApplicationScreen: View {
    let application: DealerApplication?
    /// Called once the seller has finished (or left) the verification step, so
    /// the dashboard can reload and re-render the card.
    let onFinished: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var companyName = ""
    @State private var country = "US"
    @State private var nameError: String?
    @State private var countryError: String?
    @State private var formError: String?
    @State private var busy = false

    /// Set when the backend answers `connect_required`: payouts have to exist
    /// before the business step can run.
    @State private var needsPayoutSetup = false
    @State private var showSSNStep = false
    @State private var pendingConnect: PendingConnect?

    var body: some View {
        SheetScaffold(title: "Apply as a dealer", detents: [.large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if needsPayoutSetup {
                        payoutFirst
                    } else {
                        explainer
                        form
                    }

                    if let formError {
                        InlineErrorLine(message: formError)
                    }

                    Spacer(minLength: Space.l)
                }
                .padding(.bottom, Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            if companyName.isEmpty, let existing = application?.companyName {
                companyName = existing
            }
            if let existing = application?.country, InputValidation.isISO2CountryCode(existing) {
                country = existing.uppercased()
            }
        }
        .sheet(isPresented: $showSSNStep) {
            SSNStepSheet { session in
                Task {
                    await present(
                        clientSecret: session.clientSecret,
                        title: "Set up payouts",
                        isPayoutSetup: true
                    )
                }
            }
        }
        .fullScreenCover(item: $pendingConnect) { pending in
            ConnectOnboardingScreen(
                clientSecret: pending.clientSecret,
                publishableKey: pending.key,
                title: pending.title,
                onExit: {
                    pendingConnect = nil
                    if pending.isPayoutSetup {
                        Task { await finishPayoutSetup() }
                    } else {
                        finishApplication()
                    }
                },
                onLoadFailure: { message in
                    pendingConnect = nil
                    formError = message
                }
            )
        }
    }

    // MARK: - What we collect, and why

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("A dealer is a verified business. Verifying takes two pieces of information, and Stripe's verdict decides what happens next.")
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Space.m) {
                collected(
                    icon: "building.2",
                    title: "Your business legal name",
                    detail: "The name your business is registered under. Buyers see that a real business is behind the listing."
                )
                collected(
                    icon: "number",
                    title: "Your EIN",
                    detail: "Entered on the next step, on Stripe's own secure form. Stripe verifies it — Rewound never sees your banking details, they stay with Stripe."
                )
            }

            CalloutBand(
                icon: "checkmark.seal",
                message: "If Stripe confirms a registered company, dealer status is granted straight away; if it cannot, someone at Rewound reviews the application and decides."
            )

            if let benefits = benefitsLine {
                Text(benefits)
                    .font(RewoundType.label)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The three things dealer status brings, with the rate quoted from the
    /// application payload — or the same sentence without a number when the
    /// server hasn't stated one.
    private var benefitsLine: String? {
        let tail = "a dealer badge buyers can see, and bulk import plus volume tools."
        if let dealer = application?.dealerFeePercent?.value {
            return "Dealer status brings three things: the \(feePercentText(dealer))% dealer rate, \(tail)"
        }
        return "Dealer status brings three things: the dealer rate, \(tail)"
    }

    private func collected(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Text(detail)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            RewoundTextField(
                "Business legal name",
                text: $companyName,
                placeholder: "Acme Watch Company LLC",
                error: nameError
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .onChange(of: companyName) { _, _ in
                if nameError != nil { nameError = nil }
            }

            RewoundTextField(
                "Country",
                text: $country,
                placeholder: "US",
                error: countryError,
                kind: .country
            )
            .onChange(of: country) { _, newValue in
                let upper = String(newValue.prefix(2)).uppercased()
                if upper != newValue { country = upper }
                if countryError != nil { countryError = nil }
            }

            Button {
                submit()
            } label: {
                BusyLabel(title: "Continue to verification", busy: busy)
            }
            .buttonStyle(.rewound(.primary, fullWidth: true))
            .disabled(busy)
        }
    }

    // MARK: - Payouts first

    private var payoutFirst: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            CalloutBand(
                icon: "building.columns",
                title: "Payouts come first",
                message: "Your payout account has to be set up before we can verify the business, because the business details are attached to it."
            )

            Button {
                startPayoutSetup()
            } label: {
                BusyLabel(title: "Set up payouts", busy: busy)
            }
            .buttonStyle(.rewound(.primary, fullWidth: true))
            .disabled(busy)

            Text("Once payouts are ready, come back here and the business step takes a minute.")
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Flow

    private func submit() {
        guard !busy else { return }
        let name = InputValidation.trimmed(companyName)
        let code = InputValidation.trimmed(country).uppercased()
        nameError = InputValidation.isNonBlank(name)
            ? nil
            : "Enter the legal name your business is registered under."
        countryError = InputValidation.isISO2CountryCode(code)
            ? nil
            : "Use the two-letter country code, like US."
        guard nameError == nil, countryError == nil else {
            Haptics.shared.play(.warning)
            return
        }

        busy = true
        formError = nil
        Task {
            defer { busy = false }
            do {
                let result = try await services.seller.applyForDealer(companyName: name, country: code)
                Haptics.shared.play(.success)
                if let secret = result.stripe?.clientSecret {
                    await present(clientSecret: secret, title: "Verify your business", isPayoutSetup: false)
                } else {
                    finishApplication()
                }
            } catch {
                if sellErrorCode(error, is: "connect_required") {
                    withAnimation(Motion.easeMedium) { needsPayoutSetup = true }
                } else {
                    formError = sellErrorMessage(error)
                }
            }
        }
    }

    private func startPayoutSetup() {
        guard !busy else { return }
        formError = nil
        // An account already exists — the backend ignores the SSN field then,
        // exactly as the sell gate's resume path does.
        if services.seller.readiness?.connect.accountId != nil {
            busy = true
            Task {
                defer { busy = false }
                do {
                    let session = try await sell.ops.connectAccountSession(ssn: "")
                    await present(clientSecret: session.clientSecret, title: "Set up payouts", isPayoutSetup: true)
                } catch {
                    formError = sellErrorMessage(error)
                }
            }
        } else {
            showSSNStep = true
        }
    }

    /// The publishable key has to be in hand before the embedded component
    /// can present, so it is fetched here rather than raced alongside.
    private func present(clientSecret: String, title: String, isPayoutSetup: Bool) async {
        do {
            let key = try await sell.stripeKey()
            pendingConnect = PendingConnect(
                clientSecret: clientSecret,
                key: key,
                title: title,
                isPayoutSetup: isPayoutSetup
            )
        } catch {
            formError = sellErrorMessage(error)
        }
    }

    private func finishPayoutSetup() async {
        _ = try? await services.seller.loadReadiness()
        withAnimation(Motion.easeMedium) { needsPayoutSetup = false }
    }

    private func finishApplication() {
        onFinished()
        dismiss()
        toasts.show(
            title: "Details submitted",
            message: "We'll update your storefront the moment verification clears.",
            tone: .success
        )
    }
}

/// Identity for the embedded-component cover. Both the business step and the
/// payout step present through the same host.
private struct PendingConnect: Identifiable {
    let clientSecret: String
    let key: String
    let title: String
    let isPayoutSetup: Bool
    var id: String { clientSecret }
}
