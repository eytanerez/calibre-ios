import RewatchDesign
import RewatchKit
import SwiftUI

/// The seller's money, laid out as the site's builder lays it out and in its
/// order: price, commission, what you keep; the label to authentication and
/// the payout after it; then what buyers see in most states and in the
/// discount states. Every figure is the server's (publish preview and the
/// price-only shipping estimate); nothing here is a rate worked out on the
/// phone. Figures roll to their new value as the price changes.
struct BuilderPayoutBreakdown: View {
    let model: ListingBuilderModel
    /// The review's version: when the seller is paid, and the stock number.
    var review = false

    private var preview: ListingPublishPreview? { model.currentPreview }
    private var price: Decimal? { model.answers.price }
    private var discount: ListingPublishPreview.BuyerDisplay.DiscountStates? { preview?.buyerDisplay.discountStates }

    private var statesText: String {
        let states = discount?.states ?? []
        return states.isEmpty ? "Discount states" : states.joined(separator: " and ")
    }

    private var paidWhen: String {
        if let hours = model.answers.returns?.hours {
            return "when the \(hours)-hour return window closes"
        }
        return "once the watch passes authentication"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Space.s) {
                row("Listing price") {
                    RollingMoney(value: price, font: RewatchType.body)
                }
                row(commissionLabel) {
                    if let preview {
                        RollingMoney(value: preview.commission.amount.value, font: RewatchType.body, prefix: "\u{2212}")
                    } else {
                        busyOrDash(model.previewLoading)
                    }
                }
            }
            .padding(Space.l)

            divider

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("You keep")
                        .font(RewatchType.bodySemiBold)
                        .foregroundStyle(Color.rewatch.foreground)
                    Spacer(minLength: Space.m)
                    if let keep = model.keep {
                        RollingMoney(value: keep, font: RewatchType.serif(.semiBold, 26, relativeTo: .title))
                    } else {
                        busyOrDash(model.previewLoading)
                    }
                }
                if let note = keepNote {
                    Text(note)
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.l)

            divider

            VStack(alignment: .leading, spacing: Space.s) {
                row("Estimated shipping label to authentication") {
                    if let shipping = model.shipping, !model.shippingLoading {
                        RollingMoney(value: shipping.amount.value, font: RewatchType.body)
                    } else {
                        Text(shippingText)
                            .font(RewatchType.caption)
                            .foregroundStyle(Color.rewatch.mutedForeground)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                row("Estimated payout", emphasized: true) {
                    RollingMoney(value: model.estimatedPayout, font: RewatchType.bodySemiBold)
                }
                Text("An estimate from a standard box that binds nothing. Rewatch buys the real label when the watch sells, and its actual cost comes off your payout.")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)

            divider

            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow("What buyers see")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.m) { buyerCells }
                    VStack(alignment: .leading, spacing: Space.s) { buyerCells }
                }
                Text("The total a buyer pays is the same everywhere. In \(discount == nil ? "the discount states" : statesText) the listed price is the card price and paying by wire earns a discount off it.")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)

            if review {
                divider
                HStack {
                    Label("Stock number (only you)", systemImage: "lock.fill")
                        .font(RewatchType.label)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                    Spacer()
                    Text(model.answers.sku.isEmpty ? "\u{2014}" : model.answers.sku)
                        .font(RewatchType.body)
                        .foregroundStyle(Color.rewatch.foreground)
                }
                .padding(Space.l)
            }
        }
        .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.box, style: .continuous).strokeBorder(Color.rewatch.border))
        .opacity(price == nil ? 0.6 : 1)
        .animation(Motion.easeMedium, value: price == nil)
    }

    /// "(minimum)" when the minimum is what was charged, the percent when the
    /// percent was.
    private var commissionLabel: String {
        guard let preview else { return "Rewatch\u{2019}s commission" }
        let rate = preview.commission.minimumApplied ? "minimum" : "\(feePercentText(preview.commission.percent.value))%"
        return "Rewatch\u{2019}s commission (\(rate))"
    }

    private var keepNote: String? {
        if review, preview != nil { return "Paid \(paidWhen)." }
        if let preview, preview.commission.minimumApplied {
            return "Every sale carries a minimum commission of \(PriceFormatter.format(preview.commission.minimum.value)), and at this price it applies."
        }
        return nil
    }

    private var shippingText: String {
        if price == nil { return "Needs a valid price" }
        if model.shippingLoading { return "Calculating\u{2026}" }
        if let error = model.shippingError { return error }
        return "Pending"
    }

    @ViewBuilder
    private var buyerCells: some View {
        buyerCell("Most states", preview?.buyerDisplay.standard.price.value)
        buyerCell("\(statesText), by card", discount?.price.value)
        buyerCell("\(statesText), by wire", discount?.wirePrice.value)
    }

    private func buyerCell(_ label: String, _ value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            RollingMoney(value: value, font: RewatchType.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func busyOrDash(_ busy: Bool) -> some View {
        if busy, price != nil {
            ProgressView().controlSize(.small).tint(Color.rewatch.primary)
        } else {
            Text("\u{2014}").foregroundStyle(Color.rewatch.mutedForeground)
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.rewatch.border).frame(height: 1)
    }

    /// A label and its figure; they stack rather than truncate when the two
    /// cannot share a line.
    private func row<Value: View>(_ label: String, emphasized: Bool = false, @ViewBuilder value: () -> Value) -> some View {
        let figure = value()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(label)
                    .font(emphasized ? RewatchType.bodySemiBold : RewatchType.body)
                    .foregroundStyle(emphasized ? Color.rewatch.foreground : Color.rewatch.mutedForeground)
                    .fixedSize()
                Spacer(minLength: Space.m)
                figure.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(emphasized ? RewatchType.bodySemiBold : RewatchType.body)
                    .foregroundStyle(emphasized ? Color.rewatch.foreground : Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                figure
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
