import RewoundDesign
import RewoundKit
import SwiftUI

/// Step 3 (card path) — the server-priced breakdown, one Pay button, and
/// every disclosure that has to be on screen *before* the buyer pays.
///
/// The card itself is collected inside Stripe's own PaymentSheet rather than
/// a field of ours — the same sheet "add a card" already uses, with Apple Pay
/// in it. PaymentSheet's deferred-confirmation flow is what keeps the funding
/// gate alive after that move: its confirm handler (`CheckoutModel.
/// confirmForPaymentSheet`) gets a full `STPPaymentMethod` and no money moves
/// until it hands back a client secret, so a refusal still lands before any
/// charge — just inside the sheet, after the buyer taps its own Pay button,
/// rather than inline at a field of ours. Wire stays exactly where it is,
/// one tap away, as the way out of a refusal.
struct CheckoutReviewStep: View {
    @Bindable var model: CheckoutModel
    @Environment(BetaStore.self) private var beta

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                EyebrowProgress(steps: ["Shipping", "Payment", "Review"], currentIndex: 2)

                Text("Review and pay")
                    .font(RewoundType.title)
                    .foregroundStyle(Color.rewound.foreground)

                // What is being bought. One watch keeps its mini card; a set
                // is itemised, because each watch has its own price, its own
                // shipping and its own return terms.
                if model.isMultiItem {
                    CheckoutItemsCard(items: model.items)
                } else if let listing = model.listing {
                    ListingMiniCard(listing: listing)
                } else {
                    ListingMiniCardSkeleton()
                }

                if let dropped = model.droppedWatch {
                    DroppedWatchNote(title: dropped.title, remaining: model.itemCount) {
                        model.dismissDroppedWatchNote()
                    }
                }

                if let breakdown = model.breakdown {
                    if breakdown.isDiscountPresentation {
                        DiscountPresentationNotice(breakdown: breakdown)
                    }
                    breakdownCard(breakdown)
                    disclosures(breakdown)
                } else if model.pricingProblem == nil {
                    breakdownSkeleton
                }

                if let problem = model.pricingProblem {
                    CheckoutProblemBlock(model: model, problem: problem) {
                        await model.prepareCardIntent()
                    }
                }

                CalloutBand(
                    icon: "checkmark.shield",
                    message: model.isMultiItem
                        ? "Every watch is inspected at the authentication center before it ships."
                        : "Your watch is inspected at the authentication center before it ships."
                )

                if let problem = model.paymentProblem {
                    CheckoutProblemBlock(model: model, problem: problem) {
                        model.dismissPaymentProblem()
                    }
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
        .rewoundPageBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.confirmingOrder || model.presentingPaymentSheet)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CheckoutCloseButton(disabled: model.confirmingOrder || model.presentingPaymentSheet)
            }
        }
        .safeAreaInset(edge: .bottom) { payBar }
        .animation(Motion.easeFast, value: model.paymentProblem)
        .animation(Motion.easeMedium, value: model.confirmingOrder)
        .animation(Motion.easeMedium, value: model.presentingPaymentSheet)
    }

    // MARK: - Breakdown

    private func breakdownCard(_ breakdown: CheckoutBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SpecList(breakdownRows(breakdown))

            // The card cost is its own receipt line above; this is the
            // promise behind the number.
            if CheckoutCopy.cardFeeAmount(breakdown) != nil {
                Text(CheckoutCopy.cardFeeNote(breakdown))
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.l)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Spacer()
                Text(PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency))
                    .font(RewoundType.price)
                    .foregroundStyle(Color.rewound.foreground)
            }
            .padding(.horizontal, Space.l)
            .accessibilityElement(children: .combine)
        }
    }

    /// The purchase's single column. However many watches it covers, there is
    /// one card-fee line, one tax line and one total — every one of them the
    /// server's own combined figure, never a sum taken on the device. The
    /// per-watch prices are stated once, above, in the items card.
    private func breakdownRows(_ breakdown: CheckoutBreakdown) -> [(label: String, value: String)] {
        let currency = breakdown.currency
        var rows: [(String, String)] = [
            (
                subtotalLabel,
                PriceFormatter.format(breakdown.subtotal.value, currency: currency)
            ),
            ("Shipping", PriceFormatter.format(breakdown.shipping.value, currency: currency)),
        ]
        if let fee = CheckoutCopy.cardFeeAmountText(breakdown) {
            let rate = CheckoutCopy.cardFeeRateText(breakdown)
            rows.append((rate.map { "Card processing (\($0))" } ?? "Card processing", fee))
        }
        if let tax = breakdown.tax {
            rows.append(("Tax", PriceFormatter.format(tax.value, currency: currency)))
        }
        return rows
    }

    private var subtotalLabel: String {
        if model.isMultiItem { return CheckoutCopy.watchCount(model.itemCount) }
        return model.offerID == nil ? "Watch price" : "Your accepted offer"
    }

    private var breakdownSkeleton: some View {
        VStack(spacing: Space.s) {
            ForEach(0..<4, id: \.self) { _ in
                Rectangle().frame(height: 18).shimmer()
            }
        }
        .padding(Space.l)
        .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }

    // MARK: - Disclosures

    private func disclosures(_ breakdown: CheckoutBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if breakdown.paymentDisclosures?.cardFeeNonrefundable == true {
                disclosureLine(
                    icon: "arrow.uturn.backward",
                    text: "If you return the watch, the card fee is not refunded."
                )
            }

            // Return terms are the seller's, so a purchase of several watches
            // states them per watch in the items card above rather than
            // merging them into one sentence that would be true of neither.
            let returnLines = model.isMultiItem ? [] : CheckoutCopy.returnTermLines(breakdown)
            if !returnLines.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Returns on this watch")
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
                    ForEach(returnLines, id: \.self) { line in
                        Text(line)
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .background(
                    Color.rewound.card,
                    in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                        .strokeBorder(Color.rewound.border, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
            }

            if model.offerID != nil {
                disclosureLine(icon: "hand.raised", text: offerForfeitureText)
            }

            // Seeing the fee and being able to walk away from it is the whole
            // point of showing it before payment.
            Button {
                Haptics.shared.play(.press)
                Task { await model.switchToWire() }
            } label: {
                BusyLabel(title: "Pay by wire instead", busy: model.preparingWire)
            }
            .buttonStyle(.rewound(.secondary, fullWidth: true))
            .disabled(model.presentingPaymentSheet || model.confirmingOrder)
        }
    }

    private func disclosureLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.rewound.mutedForeground)
                .frame(width: 18)
            Text(text)
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The hold at stake, in the offer's own figure. Without one, the
    /// sentence loses its number rather than gaining a guess.
    private var offerForfeitureText: String {
        if let hold = model.offerHoldText {
            return "This is payment on an accepted offer. If it isn't completed in time, the \(hold) hold is forfeited and split between the seller and Rewound."
        }
        return "This is payment on an accepted offer. If it isn't completed in time, your hold is forfeited and split between the seller and Rewound."
    }

    // MARK: - Test mode

    /// The card to print in the test-mode banner, when the checkout is
    /// running against a Stripe test key. The beta program's own test card
    /// wins when it has one (the server's `REWOUND_BETA_TEST_CARD*` env
    /// vars, carried on `/beta/config`); Stripe's universal test number is
    /// the fallback for a test key outside the beta program, where the
    /// server has nothing configured to hand back. The heading and note are
    /// always ours — regardless of source, the banner has to say plainly
    /// that this is test mode and nothing is charged, which is not
    /// necessarily what the beta program's own card copy says.
    private var testModeCard: BetaTestCard? {
        guard model.isTestModePayment else { return nil }
        let card = beta.config.testCard
        return BetaTestCard(
            number: card?.number ?? "4242 4242 4242 4242",
            expiry: card?.expiry ?? "12/34",
            cvc: card?.cvc ?? "123",
            caption: "Test mode. Nothing is charged.",
            note: "Pay with the card below to try checkout end to end."
        )
    }

    // MARK: - Pay

    @ViewBuilder
    private var payBar: some View {
        VStack(spacing: Space.m) {
            if let testModeCard {
                BetaTestCardPanel(card: testModeCard)
            }

            Group {
                if model.confirmingOrder {
                    busyRow(model.isMultiItem ? "Confirming your orders…" : "Confirming your order…")
                } else if model.presentingPaymentSheet {
                    busyRow("Opening payment…")
                } else {
                    Button {
                        Haptics.shared.play(.press)
                        model.presentPaymentSheet()
                    } label: {
                        Text(payTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.rewound(.primary, fullWidth: true))
                    .disabled(!model.canPayWithCard)
                }
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.m)
        .background(Color.rewound.background.opacity(0.97))
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: Space.m) {
            RewoundInlineLoading(size: 20)
            Text(text)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.secondaryForeground)
        }
        .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
        .accessibilityElement(children: .combine)
    }

    private var payTitle: String {
        guard let breakdown = model.breakdown else { return "Pay" }
        return "Pay \(PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency))"
    }
}
