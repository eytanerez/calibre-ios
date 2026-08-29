import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

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
                // A card already on file is the answer to this screen, so it
                // leads. The credit-only briefing is instruction for someone
                // about to type a number, and re-reading it to a seller who
                // has already finished turns a done step back into a chore.
                if let card = model.card, card.present {
                    onFile(card)
                } else {
                    creditOnly
                }

                why

                entry(model)

                if let error = model.error {
                    InlineErrorLine(message: error)
                }

                Spacer(minLength: Space.l)
            }
            .padding(.bottom, Space.xxl)
        }
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

    /// The card as an object, with the words about it beside rather than on
    /// it. Stripe hands back four facts and no image, so the card is drawn.
    private func onFile(_ card: SellerCardState) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            GuaranteeCard(
                brand: GuaranteeCard.Brand(stripeBrand: card.brand),
                last4: card.last4,
                expiry: card.expiryLabel,
                status: cardStatus(card)
            )

            VStack(alignment: .leading, spacing: Space.s) {
                if let badge = standingBadge(card) {
                    StatusBadge(badge.text, tone: badge.tone)
                }
                Text(standingTitle(card))
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(
                        card.valid == false ? Color.calibre.destructive : Color.calibre.foreground
                    )
                    .fixedSize(horizontal: false, vertical: true)
                Text(standingBody(card))
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// The server's verdict, never a date compared here.
    private func cardStatus(_ card: SellerCardState) -> GuaranteeCard.Status {
        if card.valid == false { return .lapsed }
        if card.expiringSoon == true { return .expiringSoon }
        return .onFile
    }

    private func standingTitle(_ card: SellerCardState) -> String {
        if card.valid == false { return "This card can't be charged any more." }
        if card.expiringSoon == true { return "This card expires soon." }
        return "Your guarantee is in place."
    }

    /// Names the card in prose as well as on it. The drawn card is a picture
    /// of an object and grows only so far; these words scale all the way, so
    /// the brand and the last four are readable at any type size.
    private func standingBody(_ card: SellerCardState) -> String {
        if card.valid == false {
            return "\(card.displayName) has expired. Replacing it puts your listings back on the market."
        }
        if card.expiringSoon == true {
            return "\(card.displayName) expires soon. Replace it before it lapses — a lapsed card takes your listings off the market until a valid one replaces it."
        }
        return "\(card.displayName) is on file. An ordinary sale never touches it."
    }

    /// No badge on a healthy card: the card face already says "card on file",
    /// and a second green chip beside it only adds noise.
    private func standingBadge(_ card: SellerCardState) -> (text: String, tone: StatusBadge.Tone)? {
        if card.valid == false { return ("Needs replacing", .danger) }
        if card.expiringSoon == true { return ("Expires soon", .warning) }
        return nil
    }

    // MARK: - Entry

    /// Adding is the ask; replacing a card that is working is an option. A
    /// settled card gets the quiet inline control, not a full-width CTA that
    /// reads as the next thing to do.
    private func entry(_ model: SellerCardModel) -> some View {
        let present = model.card?.present == true
        let settled = present && model.card?.needsAttention == false

        return VStack(alignment: .leading, spacing: Space.m) {
            if !settled {
                Text(present ? "Replace it" : "Add your card")
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
            }

            if settled {
                Button {
                    model.save()
                } label: {
                    HStack(spacing: Space.s) {
                        if model.busy {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.calibre.primary)
                        }
                        Text("Replace card")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.primary)
                    }
                    .frame(minHeight: Space.touchTarget, alignment: .leading)
                }
                .buttonStyle(PressableStyle())
                .disabled(model.busy)
            } else {
                Button {
                    model.save()
                } label: {
                    BusyLabel(title: present ? "Replace card" : "Add card", busy: model.busy)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.busy)
            }

            if settled {
                Text("A replacement has to be a credit card too — debit and prepaid can't be used.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    @ObservationIgnored private let seller: SellerStore
    @ObservationIgnored private let sell: SellSession
    /// Kept for the life of the call: Stripe holds the sheet weakly.
    @ObservationIgnored private var paymentSheet: PaymentSheet?

    init(seller: SellerStore, sell: SellSession) {
        self.seller = seller
        self.sell = sell
    }

    func load() async {
        card = try? await seller.sellerCard()
    }

    func save() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                STPAPIClient.shared.publishableKey = try await sell.stripeKey()
                let intent = try await seller.sellerCardSetupIntent()
                let sheet = PaymentSheet(
                    setupIntentClientSecret: intent.clientSecret,
                    configuration: sheetConfiguration()
                )
                paymentSheet = sheet
                let result: PaymentSheetResult = await withCheckedContinuation { continuation in
                    CalibreStripe.present(sheet) { continuation.resume(returning: $0) }
                }
                await finish(result)
            } catch {
                busy = false
                self.error = sellErrorMessage(error)
            }
        }
    }

    /// The shared sheet dressed for a guarantee card rather than a purchase.
    ///
    /// Apple Pay is dropped: this card has to be chargeable weeks later with
    /// nobody present, and an Apple Pay credential is bound to the device that
    /// authorized it. The sheet also runs customer-less — the setup-intent
    /// endpoint sends no Stripe customer id or customer-session secret — which
    /// suits a screen whose whole purpose is entering a new card.
    private func sheetConfiguration() -> PaymentSheet.Configuration {
        var configuration = CalibreStripe.configuration(
            customerID: nil,
            customerSessionClientSecret: nil
        )
        configuration.applePay = nil
        return configuration
    }

    private func finish(_ result: PaymentSheetResult) async {
        defer { busy = false }
        switch result {
        case .canceled:
            return
        case .failed(let failure):
            // Not `CalibreStripe.failureMessage`: its fallback talks about a
            // payment that didn't go through, and nothing is being paid here.
            let text = failure.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            error = text.isEmpty ? "That card couldn't be saved. Please try again." : text
            Haptics.shared.play(.error)
        case .completed:
            await readBackCard()
        }
    }

    private func readBackCard() async {
        do {
            let state = try await seller.sellerCard()
            card = state
            if state.present, state.funding?.lowercased() == "credit" {
                saved = true
                Haptics.shared.play(.success)
            } else {
                // The server detached it. Say why plainly and leave the screen
                // ready for another card.
                error = "That wasn't a credit card, so it wasn't kept. Calibre needs a credit card on file — debit and prepaid cards can't be used. Please try another card."
                Haptics.shared.play(.warning)
            }
        } catch {
            self.error = sellErrorMessage(error)
        }
    }
}
