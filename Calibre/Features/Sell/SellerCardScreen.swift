import CalibreDesign
import CalibreKit
import StripePayments
import StripePaymentsUI
import SwiftUI
import UIKit

/// The credit card a seller keeps on file. Credit only, said before anyone
/// types, and explained honestly: this is the card a counterfeit or
/// misrepresentation charge lands on. Nothing else touches it.
struct SellerCardScreen: View {
    /// Handed the fresh card state once one is successfully on file, so the
    /// dashboard banner and the sell gate can settle.
    var onSaved: (SellerCardState) -> Void = { _ in }

    @Environment(AppServices.self) private var services
    @Environment(SellSession.self) private var sell
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var model: SellerCardModel?
    @ScaledMetric(relativeTo: .body) private var cardFieldHeight: CGFloat = 48

    var body: some View {
        SheetScaffold(title: "Your card on file", detents: [.large]) {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                        .tint(Color.calibre.primary)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .task {
            if model == nil {
                model = SellerCardModel(seller: services.seller, sell: sell)
            }
            await model?.load()
        }
    }

    private func content(_ model: SellerCardModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                creditOnly

                why

                if let card = model.card, card.present {
                    currentCard(card)
                }

                entry(model)

                if let error = model.error {
                    InlineErrorLine(message: error)
                }

                Spacer(minLength: Space.l)
            }
            .padding(.bottom, Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(Motion.easeMedium, value: model.error)
        .onChange(of: model.saved) { _, saved in
            guard saved, let card = model.card else { return }
            onSaved(card)
            dismiss()
            toasts.show(
                title: "Card saved",
                message: "\(card.displayName) is on file.",
                tone: .success
            )
        }
    }

    // MARK: - Said before anyone types

    private var creditOnly: some View {
        CalloutBand(
            icon: "creditcard",
            title: "A credit card, and only a credit card",
            message: "Sellers finish onboarding with a credit card on file. Debit and prepaid cards can't be used here — if the card you enter isn't a credit card, it won't be kept."
        )
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("Why we ask")
            Text("Almost every sale ends without this card being touched. It is here for the rare case where a watch turns out to be counterfeit or is not as described.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            // FIXTURE-PENDING: the counterfeit charge is a percentage of the
            // sale price, but no payload or config field carries it yet — so
            // the sentence runs without the number rather than hardcoding one.
            Text("If a watch is found to be counterfeit, the buyer is refunded in full and a percentage of the sale price is charged to this card. If a watch is genuine but not as described, the case is settled individually and may be charged here too, along with the return label.")
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("Nothing else is charged to it. Listing is free, and an ordinary sale never touches it.")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What's on file now

    private func currentCard(_ card: SellerCardState) -> some View {
        SellCard {
            HStack(spacing: Space.m) {
                IconTile(systemName: "creditcard")
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.displayName)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    if let expiry = card.expiryLabel {
                        Text("Expires \(expiry)")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }
                Spacer(minLength: Space.s)
                StatusBadge(currentBadge(card).text, tone: currentBadge(card).tone)
            }
            .padding(Space.l)
        }
        .accessibilityElement(children: .combine)
    }

    private func currentBadge(_ card: SellerCardState) -> (text: String, tone: StatusBadge.Tone) {
        if card.valid == false { return ("Needs replacing", .danger) }
        if card.expiringSoon == true { return ("Expires soon", .warning) }
        return ("On file", .success)
    }

    // MARK: - Entry

    private func entry(_ model: SellerCardModel) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(model.card?.present == true ? "Replace it" : "Add your card")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            SellerCardEntryField { isValid, params in
                model.updateEntry(isValid: isValid, params: params)
            }
            .frame(height: cardFieldHeight)
            .accessibilityLabel("Card number, expiry, security code and postal code")

            Button {
                model.save()
            } label: {
                BusyLabel(
                    title: model.card?.present == true ? "Replace card" : "Save card",
                    busy: model.busy
                )
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(model.busy || !model.entryValid)

            Text("Your card details go straight to our payments partner. Calibre stores the brand, the last four digits and the expiry date, and nothing more.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Model

/// Owns the SetupIntent round-trip. The truth about what is on file always
/// comes from re-reading the card after confirmation — the server detaches
/// anything that isn't a credit card, so the SDK's success is not the last
/// word.
@MainActor
@Observable
final class SellerCardModel {
    private(set) var card: SellerCardState?
    private(set) var busy = false
    private(set) var saved = false
    var error: String?
    /// True once the network form holds a complete, well-formed card.
    private(set) var entryValid = false

    @ObservationIgnored private let seller: SellerStore
    @ObservationIgnored private let sell: SellSession
    @ObservationIgnored private let authContext = SellerCardAuthContext()
    /// Deliberately unobserved: reading these during a body pass would redraw
    /// the form on every keystroke.
    @ObservationIgnored private var cardParams: STPPaymentMethodParams?

    init(seller: SellerStore, sell: SellSession) {
        self.seller = seller
        self.sell = sell
    }

    func load() async {
        card = try? await seller.sellerCard()
    }

    func updateEntry(isValid: Bool, params: STPPaymentMethodParams?) {
        cardParams = params
        if entryValid != isValid {
            entryValid = isValid
        }
        if error != nil {
            error = nil
        }
    }

    func save() {
        guard !busy, let params = cardParams else { return }
        busy = true
        error = nil
        Task {
            do {
                STPAPIClient.shared.publishableKey = try await sell.stripeKey()
                let intent = try await seller.sellerCardSetupIntent()
                let confirmParams = STPSetupIntentConfirmParams(clientSecret: intent.clientSecret)
                confirmParams.paymentMethodParams = params
                confirmParams.returnURL = CalibreStripe.returnURL
                STPPaymentHandler.shared().confirmSetupIntent(
                    confirmParams,
                    with: authContext
                ) { status, _, confirmError in
                    // Only Sendable values cross back, so the hop to the main
                    // actor is safe whichever thread the SDK finishes on.
                    let succeeded = status == .succeeded
                    let cancelled = status == .canceled
                    let message = confirmError?.localizedDescription
                    Task { @MainActor [weak self] in
                        await self?.finishConfirm(
                            succeeded: succeeded,
                            cancelled: cancelled,
                            message: message
                        )
                    }
                }
            } catch {
                busy = false
                self.error = sellErrorMessage(error)
            }
        }
    }

    private func finishConfirm(succeeded: Bool, cancelled: Bool, message: String?) async {
        defer { busy = false }
        guard succeeded else {
            if !cancelled {
                error = message ?? "That card couldn't be saved. Please try again."
                Haptics.shared.play(.error)
            }
            return
        }

        do {
            let state = try await seller.sellerCard()
            card = state
            if state.present, state.funding?.lowercased() == "credit" {
                saved = true
                Haptics.shared.play(.success)
            } else {
                // The server detached it. Say why plainly and leave the form
                // ready for another card.
                entryValid = false
                error = "That wasn't a credit card, so it wasn't kept. Calibre needs a credit card on file — debit and prepaid cards can't be used. Please try another card."
                Haptics.shared.play(.warning)
            }
        } catch {
            self.error = sellErrorMessage(error)
        }
    }
}

// MARK: - Card entry

/// Stripe's card field, bridged into SwiftUI and dressed in brand tokens.
/// The card details never reach Calibre — the field hands back params the
/// SDK exchanges for a PaymentMethod directly.
private struct SellerCardEntryField: UIViewRepresentable {
    let onChange: (Bool, STPPaymentMethodParams?) -> Void

    func makeUIView(context: Context) -> STPPaymentCardTextField {
        let field = STPPaymentCardTextField(frame: .zero)
        field.delegate = context.coordinator
        field.postalCodeEntryEnabled = true
        field.backgroundColor = UIColor(Color.calibre.card)
        field.textColor = UIColor(Color.calibre.foreground)
        field.textErrorColor = UIColor(Color.calibre.destructive)
        field.placeholderColor = UIColor(Color.calibre.placeholder)
        field.borderColor = UIColor(Color.calibre.border)
        field.borderWidth = 1
        field.cornerRadius = Radius.control
        field.cursorColor = UIColor(Color.calibre.primary)
        if let base = UIFont(name: "Geist-Regular", size: 15) {
            field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        }
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    func updateUIView(_ uiView: STPPaymentCardTextField, context: Context) {
        context.coordinator.onChange = onChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    @MainActor
    final class Coordinator: NSObject, STPPaymentCardTextFieldDelegate {
        var onChange: (Bool, STPPaymentMethodParams?) -> Void

        init(onChange: @escaping (Bool, STPPaymentMethodParams?) -> Void) {
            self.onChange = onChange
        }

        func paymentCardTextFieldDidChange(_ textField: STPPaymentCardTextField) {
            let isValid = textField.isValid
            onChange(isValid, isValid ? textField.paymentMethodParams : nil)
        }
    }
}

// MARK: - Authentication context

/// Where Stripe presents a 3-D Secure challenge from. Walks the active
/// scene's key window down its presentation chain so the challenge lands
/// above whatever sheet the seller is already in.
@MainActor
final class SellerCardAuthContext: NSObject, STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        guard let root = window?.rootViewController else { return UIViewController() }

        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }
}
