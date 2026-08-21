import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

/// Step 2 — how to pay. Two quiet cards: card or Apple Pay (instant, with the
/// card's processing cost) versus wire transfer (no processing cost, the
/// watch reserved while the transfer arrives). Every figure comes from the
/// server's breakdown once the order is priced; nothing here is a rate we
/// remember.
struct CheckoutMethodStep: View {
    @Bindable var model: CheckoutModel
    @Environment(AppServices.self) private var services
    /// The SDK holds the sheet weakly, so the view owns it for the life of
    /// the add-card round trip.
    @State private var cardSheet: PaymentSheet?
    @State private var tutorial = TutorialController(
        id: "checkout.method",
        steps: [
            TutorialStep(
                id: "methods",
                anchor: "checkout.methods",
                title: "Two ways to pay",
                // True under both presentations: where a surcharge is allowed
                // the card carries its processing cost, and where it is not
                // the wire route earns a discount instead. Either way the
                // difference is in dollars on this screen, before paying.
                message: "Card or Apple Pay clears instantly. Paying by wire comes to less, and the difference is shown to you in dollars on this screen before you pay. Choosing wire holds the watch while the transfer lands.",
                advance: .tapToContinue,
                cutout: .roundedRect(Radius.card)
            )
        ]
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                EyebrowProgress(steps: ["Shipping", "Payment", "Review"], currentIndex: 1)

                Text("How would you like to pay?")
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)

                // What is being paid for, before how. One payment covers the
                // whole set, so the set is on screen when the method is chosen.
                if model.isMultiItem {
                    CheckoutItemsCard(items: model.items, showsReturnTerms: false)
                }

                if let dropped = model.droppedWatch {
                    DroppedWatchNote(title: dropped.title, remaining: model.itemCount) {
                        model.dismissDroppedWatchNote()
                    }
                }

                // Where surcharges are prohibited and discounts permitted, the
                // price difference has to be clear and conspicuous *here* —
                // a buyer who chooses wire leaves for the wire screen and
                // never sees the review step.
                if let breakdown = model.breakdown, breakdown.isDiscountPresentation {
                    DiscountPresentationNotice(breakdown: breakdown)
                }

                VStack(spacing: Space.m) {
                    MethodCard(
                        icon: "creditcard",
                        title: "Card or Apple Pay",
                        subtitle: cardSubtitle,
                        detail: cardDetail,
                        detailLoading: model.preparingCardIntent && model.cardFeeText == nil,
                        isSelected: model.method == .card
                    ) {
                        Haptics.shared.play(.selection)
                        model.method = .card
                    }

                    MethodCard(
                        icon: "building.columns",
                        title: "Wire transfer",
                        subtitle: wireSubtitle,
                        detail: wireDetail,
                        detailLoading: model.preparingCardIntent && model.cardFeeText == nil,
                        isSelected: model.method == .wire
                    ) {
                        Haptics.shared.play(.selection)
                        model.method = .wire
                    }
                }
                .tutorialAnchor("checkout.methods")

                // Which cards work here, before the buyer commits to the card
                // route at all — the card form says it again at entry.
                if let breakdown = model.breakdown, model.method == .card {
                    Text(CheckoutCopy.acceptedCardsNote(breakdown, statesText: discountStatesText))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Before payment is committed, and on the one screen both
                // routes pass through: what this seller's return terms
                // actually are, and \u{2014} when wire is selected \u{2014} what the $250
                // authorization means.
                returnTermsDisclosure

                if model.method == .wire {
                    wireDepositDisclosure
                }

                if let refusal = model.wireCardRefusal {
                    wireCardRefusalBlock(refusal)
                }

                if let problem = model.pricingProblem {
                    CheckoutProblemBlock(model: model, problem: problem) {
                        Task { await model.prepareCardIntent() }
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .tutorialOverlay(tutorial)
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { tutorial.startIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CheckoutCloseButton() }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Haptics.shared.play(.press)
                Task { await model.continueFromMethod() }
            } label: {
                BusyLabel(
                    title: model.method == .card ? "Continue to review" : "Get wire instructions",
                    busy: model.preparingWire
                )
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .disabled(model.preparingWire)
            .padding(.horizontal, Space.margin)
            .padding(.vertical, Space.m)
            .background(Color.calibre.background.opacity(0.97))
        }
        .task { await model.prepareCardIntent() }
        .task { try? await services.config.load() }
        .animation(Motion.easeFast, value: model.pricingError)
    }

    // MARK: - Disclosures

    /// The seller's return terms, said plainly, before any payment. Terms are
    /// the seller's, so a purchase covering several watches states them per
    /// watch in the items card above rather than merging two into one
    /// sentence that would be true of neither.
    @ViewBuilder
    private var returnTermsDisclosure: some View {
        if !model.isMultiItem, let breakdown = model.breakdown {
            let lines = CheckoutCopy.returnTermLines(breakdown)
            if !lines.isEmpty {
                DisclosureCard(
                    icon: "arrow.uturn.backward",
                    title: CheckoutCopy.returnTermsHeadline(breakdown)
                ) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Shown the moment wire is selected, before the deposit is placed and
    /// before any bank details exist. There is no release control anywhere:
    /// the authorization comes off when the transfer arrives.
    private var wireDepositDisclosure: some View {
        DisclosureCard(icon: "creditcard", title: "A $250 authorization") {
            Text(CheckoutCopy.wireHoldDisclosure)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text("It has to be a credit card. Debit and prepaid cards can\u{2019}t hold a deposit.")
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The card gate, and the way through it. A refusal is never a dead end:
    /// either a card can be added here, or card checkout is still one tap
    /// away on the other option.
    private func wireCardRefusalBlock(_ refusal: WireCardRefusal) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(CheckoutCopy.wireCardRefusalMessage(refusal))
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if refusal.offersAddCard {
                Button {
                    Haptics.shared.play(.press)
                    Task { await addCardForWire() }
                } label: {
                    BusyLabel(title: "Add a credit card", busy: model.addingWireCard)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.addingWireCard)
            }

            Button("Pay by card instead") {
                Haptics.shared.play(.selection)
                model.dismissWireCardRefusal()
                model.method = .card
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(
            Color.calibre.destructive.opacity(0.06),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.destructive.opacity(0.35), lineWidth: 1)
        )
    }

    /// The account's own saved-card flow, run inline. The 402 arrives before
    /// any deposit is placed, so re-opening the wire checkout afterwards
    /// costs the buyer nothing.
    private func addCardForWire() async {
        await model.addCardForWire { intent in
            await withCheckedContinuation { continuation in
                STPAPIClient.shared.publishableKey = intent.publishableKey
                let sheet = PaymentSheet(
                    setupIntentClientSecret: intent.setupIntent.clientSecret,
                    configuration: CalibreStripe.configuration(
                        customerID: intent.customerId,
                        customerSessionClientSecret: intent.customerSessionMobile?.clientSecret
                    )
                )
                cardSheet = sheet
                CalibreStripe.present(sheet) { result in
                    if case .completed = result {
                        continuation.resume(returning: true)
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    /// Which presentation this order is priced under. In discount mode the
    /// listed price *is* the card price, so nothing on this step may frame the
    /// card as adding a cost — the wire route earns a discount instead.
    private var isDiscountMode: Bool {
        model.breakdown?.isDiscountPresentation == true
    }

    private var cardSubtitle: String {
        if isDiscountMode {
            return "Pay instantly. The listed price is the card price, so this is what the watch is listed at."
        }
        guard let breakdown = model.breakdown,
              let rate = CheckoutCopy.cardFeeRateText(breakdown) else {
            return "Pay instantly. The card's processing cost is shown before you pay."
        }
        return "Pay instantly. The card's processing cost is \(rate) — exactly our cost of accepting it."
    }

    private var wireSubtitle: String {
        let reservation = CheckoutCopy.wireReservationSentence(services.config.config?.wireReservationText)
        if isDiscountMode {
            return "A discount off the listed price. \(reservation)"
        }
        return "No processing cost. \(reservation)"
    }

    private var cardDetail: String? {
        if isDiscountMode {
            guard let total = cardTotalText else { return nil }
            return "Card price: \(total)"
        }
        guard let fee = model.cardFeeText else { return nil }
        return "Card processing today: \(fee)"
    }

    private var wireDetail: String? {
        if isDiscountMode {
            // The wire figure is the discounted amount the server priced, not
            // a saving subtracted on the device.
            guard let total = wireTotalText else { return nil }
            return "Wire price: \(total)"
        }
        guard let fee = model.cardFeeText else { return nil }
        return "Save \(fee) versus paying by card"
    }

    private var cardTotalText: String? {
        guard let breakdown = model.breakdown else { return nil }
        guard let amount = breakdown.totals?.card?.value ?? breakdown.display?.price.value else { return nil }
        return PriceFormatter.format(amount, currency: breakdown.currency)
    }

    private var wireTotalText: String? {
        guard let breakdown = model.breakdown else { return nil }
        guard let amount = breakdown.totals?.wire?.value ?? breakdown.display?.wirePrice?.value else { return nil }
        return PriceFormatter.format(amount, currency: breakdown.currency)
    }

    private var discountStatesText: String? {
        services.config.config?.discountStatesText
    }
}

/// One selectable payment-method card.
private struct MethodCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String?
    let detailLoading: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.calibre.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.calibre.accent.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    Text(subtitle)
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail {
                        Text(detail)
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.accentForeground)
                            .padding(.top, 2)
                    } else if detailLoading {
                        Rectangle()
                            .frame(width: 150, height: 11)
                            .shimmer()
                            .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "inset.filled.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.calibre.primary : Color.calibre.borderBright)
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.calibre.primary.opacity(0.06) : Color.calibre.card,
                in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.calibre.primary.opacity(0.5) : Color.calibre.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.easeFast, value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
