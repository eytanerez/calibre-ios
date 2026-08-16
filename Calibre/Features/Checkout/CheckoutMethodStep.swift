import CalibreDesign
import CalibreKit
import SwiftUI

/// Step 2 — how to pay. Two quiet cards: card or Apple Pay (instant, with the
/// card's processing cost) versus wire transfer (no processing cost, the
/// watch reserved while the transfer arrives). Every figure comes from the
/// server's breakdown once the order is priced; nothing here is a rate we
/// remember.
struct CheckoutMethodStep: View {
    @Bindable var model: CheckoutModel
    @Environment(AppServices.self) private var services
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
