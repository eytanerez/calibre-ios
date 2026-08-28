import CalibreDesign
import CalibreKit
import PassKit
import SwiftUI

/// Step 3 (card path) — the server-priced breakdown, the card itself, and
/// every disclosure that has to be on screen *before* the buyer pays.
///
/// The card is collected here rather than in a Stripe sheet because the
/// card's funding has to be known before any money moves. That is also why a
/// refusal lands inline, with wire still one tap away, instead of arriving
/// after a submission the buyer thought had succeeded.
struct CheckoutReviewStep: View {
    @Bindable var model: CheckoutModel
    @Environment(AppServices.self) private var services

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                EyebrowProgress(steps: ["Shipping", "Payment", "Review"], currentIndex: 2)

                Text("Review and pay")
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)

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
                    cardSection(breakdown)
                    disclosures(breakdown)
                } else if model.pricingProblem == nil {
                    breakdownSkeleton
                }

                if let problem = model.pricingProblem {
                    CheckoutProblemBlock(model: model, problem: problem) {
                        Task { await model.prepareCardIntent() }
                    }
                }

                CalloutBand(
                    icon: "checkmark.shield",
                    message: model.isMultiItem
                        ? "Every watch is inspected at the authentication centre before it ships."
                        : "Your watch is inspected at the authentication centre before it ships."
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
        .calibrePageBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.confirmingOrder || model.payState.isBusy)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CheckoutCloseButton() }
        }
        .safeAreaInset(edge: .bottom) { payBar }
        .animation(Motion.easeFast, value: model.cardRefusal)
        .animation(Motion.easeFast, value: model.paymentProblem)
        .animation(Motion.easeFast, value: model.cardCheckProblem)
        .animation(Motion.easeFast, value: model.checkingCardEntry)
        .animation(Motion.easeFast, value: model.cardAccepted)
        .animation(Motion.easeMedium, value: model.confirmingOrder)
        .animation(Motion.easeMedium, value: model.payState)
    }

    // MARK: - Breakdown

    private func breakdownCard(_ breakdown: CheckoutBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SpecList(breakdownRows(breakdown))

            // The card cost is its own receipt line above; this is the
            // promise behind the number.
            if CheckoutCopy.cardFeeAmount(breakdown) != nil {
                Text(CheckoutCopy.cardFeeNote(breakdown))
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.l)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Total")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Spacer()
                Text(PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency))
                    .font(CalibreType.price)
                    .foregroundStyle(Color.calibre.foreground)
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
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    // MARK: - Card

    private func cardSection(_ breakdown: CheckoutBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Your card")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)

            // Which cards work here, said at card entry — while wire is still
            // one tap away, never after submission.
            Text(CheckoutCopy.acceptedCardsNote(breakdown, statesText: discountStatesText))
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            // The funding check runs the moment the card is complete, so a
            // refusal arrives here — with wire one tap away — rather than
            // after a payment the buyer thought had gone through.
            CardEntryField(
                cardParams: $model.cardParams,
                isValid: $model.cardIsValid,
                onComplete: { Task { await model.validateEnteredCard() } }
            )
            .frame(height: 48)
            .disabled(model.payState.isBusy || model.confirmingOrder)

            if model.checkingCardEntry {
                cardCheckRow
            } else if model.cardAccepted {
                cardAcceptedRow
            }

            if let refusal = model.cardRefusal {
                refusalBlock(refusal)
            }

            if let problem = model.cardCheckProblem {
                VStack(alignment: .leading, spacing: Space.s) {
                    InlineErrorLine(message: problem.message)
                    Button("Check this card again") {
                        Task { await model.validateEnteredCard() }
                    }
                    .buttonStyle(.calibreGhost)
                }
            }

            if model.canOfferApplePay {
                VStack(spacing: Space.s) {
                    Text("or")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(maxWidth: .infinity)
                    PayWithApplePayButton(.buy) {
                        Haptics.shared.play(.press)
                        model.startApplePay()
                    }
                    .payWithApplePayButtonStyle(.automatic)
                    .frame(height: Space.touchTarget)
                    .disabled(model.payState.isBusy || model.confirmingOrder)
                    .accessibilityLabel("Pay with Apple Pay")
                }
            }
        }
    }

    /// The check is quick and quiet, but it is happening, so it says so.
    private var cardCheckRow: some View {
        HStack(spacing: Space.s) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.calibre.primary)
            Text("Checking your card…")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var cardAcceptedRow: some View {
        Label("This card works here. Nothing has been charged yet.", systemImage: "checkmark.circle")
            .font(CalibreType.label)
            .foregroundStyle(Color.calibre.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    /// A refused card is never a dead end: the buyer can type another one, or
    /// take the wire route, which is available at any price.
    private func refusalBlock(_ refusal: CardRefusal) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label {
                    Text(CheckoutCopy.refusalMessage(refusal, statesText: discountStatesText))
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .foregroundStyle(Color.calibre.destructive)
                }
                Text("Nothing has been charged.")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }

            HStack(spacing: Space.m) {
                Button("Use a different card") {
                    model.clearCardEntry()
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))

                Button {
                    Haptics.shared.play(.press)
                    Task { await model.switchToWire() }
                } label: {
                    BusyLabel(title: "Pay by wire", busy: model.preparingWire)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }

            Text(CheckoutCopy.wireAlwaysAvailable)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.calibre.destructive.opacity(0.06),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.destructive.opacity(0.35), lineWidth: 1)
        )
        .transition(.opacity)
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
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    ForEach(returnLines, id: \.self) { line in
                        Text(line)
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.l)
                .background(
                    Color.calibre.card,
                    in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Color.calibre.border, lineWidth: 1)
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
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            .disabled(model.payState.isBusy || model.confirmingOrder)
        }
    }

    private func disclosureLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(width: 18)
            Text(text)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The hold at stake, in the offer's own figure. Without one, the
    /// sentence loses its number rather than gaining a guess.
    private var offerForfeitureText: String {
        if let hold = model.offerHoldText {
            return "This is payment on an accepted offer. If it isn't completed in time, the \(hold) hold is forfeited to the seller, less the cost of processing it."
        }
        return "This is payment on an accepted offer. If it isn't completed in time, your hold is forfeited to the seller, less the cost of processing it."
    }

    private var discountStatesText: String? {
        services.config.config?.discountStatesText
    }

    // MARK: - Pay

    @ViewBuilder
    private var payBar: some View {
        Group {
            if model.confirmingOrder {
                busyRow(model.isMultiItem ? "Confirming your orders…" : "Confirming your order…")
            } else if let label = model.payState.label {
                busyRow(label)
            } else {
                Button {
                    Haptics.shared.play(.press)
                    Task { await model.payWithCard() }
                } label: {
                    Text(payTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(!model.canPayWithCard)
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.m)
        .background(Color.calibre.background.opacity(0.97))
    }

    private func busyRow(_ text: String) -> some View {
        HStack(spacing: Space.m) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.calibre.primary)
            Text(text)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.secondaryForeground)
        }
        .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
        .accessibilityElement(children: .combine)
    }

    private var payTitle: String {
        guard let breakdown = model.breakdown else { return "Pay" }
        return "Pay \(PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency))"
    }
}
