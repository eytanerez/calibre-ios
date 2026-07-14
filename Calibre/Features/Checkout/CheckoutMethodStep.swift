import CalibreDesign
import CalibreKit
import SwiftUI

/// Step 2 — how to pay. Two quiet cards: card/Apple Pay (instant, 3% cost)
/// vs wire transfer (no card cost, 24 h reservation). The fee difference is
/// shown in dollars once the server has priced the order.
struct CheckoutMethodStep: View {
    @Bindable var model: CheckoutModel
    @State private var tutorial = TutorialController(
        id: "checkout.method",
        steps: [
            TutorialStep(
                id: "methods",
                anchor: "checkout.methods",
                title: "Two ways to pay",
                message: "Card or Apple Pay clears instantly but adds about 3%. A wire transfer skips that cost — your watch is held for 24 hours while the transfer lands.",
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

                VStack(spacing: Space.m) {
                    MethodCard(
                        icon: "creditcard",
                        title: "Card or Apple Pay",
                        subtitle: "Pay instantly. A 3% card processing cost applies.",
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
                        subtitle: "No card processing cost. Your watch is reserved for 24 hours.",
                        detail: wireDetail,
                        detailLoading: model.preparingCardIntent && model.cardFeeText == nil,
                        isSelected: model.method == .wire
                    ) {
                        Haptics.shared.play(.selection)
                        model.method = .wire
                    }
                }
                .tutorialAnchor("checkout.methods")

                if let error = model.pricingError {
                    VStack(alignment: .leading, spacing: Space.s) {
                        InlineErrorLine(message: error)
                        Button("Try again") {
                            Task { await model.prepareCardIntent() }
                        }
                        .buttonStyle(.calibreGhost)
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
        .animation(Motion.easeFast, value: model.pricingError)
    }

    private var cardDetail: String? {
        guard let fee = model.cardFeeText else { return nil }
        return "Card processing today: \(fee)"
    }

    private var wireDetail: String? {
        guard let fee = model.cardFeeText else { return nil }
        return "Save \(fee) vs. paying by card"
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
