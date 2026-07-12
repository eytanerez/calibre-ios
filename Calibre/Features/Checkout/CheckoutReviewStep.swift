import CalibreDesign
import CalibreKit
import StripePaymentSheet
import SwiftUI

/// Step 3 (card path) — the server-priced breakdown, the watch, the trust
/// note, and the pay button that raises Stripe PaymentSheet.
struct CheckoutReviewStep: View {
    @Bindable var model: CheckoutModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                EyebrowProgress(steps: ["Shipping", "Payment", "Review"], currentIndex: 2)

                Text("Review and pay")
                    .font(CalibreType.title)
                    .foregroundStyle(Color.calibre.foreground)

                if let listing = model.listing {
                    ListingMiniCard(listing: listing)
                } else {
                    ListingMiniCardSkeleton()
                }

                if let breakdown = model.cardIntent?.breakdown {
                    breakdownCard(breakdown)
                } else if model.pricingError == nil {
                    breakdownSkeleton
                }

                if let error = model.pricingError {
                    VStack(alignment: .leading, spacing: Space.s) {
                        InlineErrorLine(message: error)
                        Button("Try again") {
                            Task { await model.prepareCardIntent() }
                        }
                        .buttonStyle(.calibreGhost)
                    }
                }

                CalloutBand(
                    icon: "checkmark.shield",
                    message: "Your watch is inspected at our authentication center before it ships."
                )

                if let failure = model.paymentFailure {
                    InlineErrorLine(message: failure)
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xxl)
        }
        .background(Color.calibre.background.ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.confirmingOrder)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { CheckoutCloseButton() }
        }
        .safeAreaInset(edge: .bottom) { payBar }
        .background(paymentSheetHost)
        .animation(Motion.easeFast, value: model.paymentFailure)
        .animation(Motion.easeMedium, value: model.confirmingOrder)
    }

    // MARK: - Breakdown

    private func breakdownCard(_ breakdown: CheckoutBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SpecList(breakdownRows(breakdown))

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

    private func breakdownRows(_ breakdown: CheckoutBreakdown) -> [(label: String, value: String)] {
        let currency = breakdown.currency
        var rows: [(String, String)] = [
            (
                model.offerID == nil ? "Watch price" : "Your accepted offer",
                PriceFormatter.format(breakdown.subtotal.value, currency: currency)
            ),
            ("Shipping", PriceFormatter.format(breakdown.shipping.value, currency: currency)),
        ]
        if let fee = breakdown.cardConvenienceFee {
            rows.append(("Card processing", PriceFormatter.format(fee.value, currency: currency)))
        }
        if let tax = breakdown.tax {
            rows.append(("Tax", PriceFormatter.format(tax.value, currency: currency)))
        }
        return rows
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

    // MARK: - Pay

    @ViewBuilder
    private var payBar: some View {
        Group {
            if model.confirmingOrder {
                HStack(spacing: Space.m) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.calibre.primary)
                    Text("Confirming your order…")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                }
                .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
            } else {
                Button {
                    Haptics.shared.play(.press)
                    model.pay()
                } label: {
                    Text(payTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
                .disabled(model.cardIntent == nil)
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.m)
        .background(Color.calibre.background.opacity(0.97))
    }

    private var payTitle: String {
        guard let breakdown = model.cardIntent?.breakdown else { return "Pay" }
        return "Pay \(PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency))"
    }

    /// PaymentSheet rides on an invisible background leaf so creating the
    /// sheet doesn't re-identify the step's content.
    @ViewBuilder
    private var paymentSheetHost: some View {
        if let sheet = model.paymentSheet {
            Color.clear
                .paymentSheet(isPresented: $model.presentingPaymentSheet, paymentSheet: sheet) { result in
                    model.handlePaymentResult(result)
                }
        }
    }
}
