import CalibreDesign
import CalibreKit
import Foundation
import Observation
import SwiftUI

// MARK: - Model

/// Display pricing for the product detail page.
///
/// Logged-out visitors see the seller's listed price and nothing else — that
/// price is the canonical one for crawlers and structured data, so no quote is
/// fetched and no toggle is offered.
///
/// Signed-in buyers get a read-only quote from `GET /listings/<id>/quote`: the
/// same breakdown checkout uses, with no PaymentIntent and — the reason that
/// endpoint exists — no reservation. Creating a checkout intent merely to show
/// a price would take the listing off the market for everyone else.
///
/// Every figure this model hands to the view comes from the breakdown. Nothing
/// is added up here; where the server hasn't spoken, the number is absent
/// rather than guessed.
@MainActor
@Observable
final class ListingPricingModel {
    /// What the pricing block can honestly offer right now.
    enum Phase: Equatable {
        /// Signed out, or a watch that isn't for sale — listed price only.
        case listedPriceOnly
        case loading
        /// A quote landed; the all-in toggle is live.
        case quoted
        /// Signed in with nothing to price tax and shipping against. The
        /// toggle asks for an address rather than quietly disappearing.
        case needsAddress
        /// The quote didn't land. Fall back to the listed price silently — a
        /// stale or half-assembled total is worse than no total.
        case unavailable
    }

    private(set) var phase: Phase = .listedPriceOnly
    private(set) var breakdown: CheckoutBreakdown?

    /// Default OFF, per the display rules, and deliberately never persisted:
    /// a fresh model is built for each listing so the all-in view is always an
    /// explicit choice.
    var allInShown = false
    /// The discount-presentation companion — reveals the lower wire price.
    /// Also default OFF.
    var wirePriceShown = false

    @ObservationIgnored private let listingID: String
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore

    init(listingID: String, catalog: CatalogStore, commerce: CommerceStore) {
        self.listingID = listingID
        self.catalog = catalog
        self.commerce = commerce
    }

    // MARK: Loading

    func load(isAuthenticated: Bool) async {
        guard isAuthenticated else {
            reset(to: .listedPriceOnly)
            return
        }
        phase = .loading

        // The store already holds the addresses on most visits; only pay for
        // the round trip when it doesn't.
        var addresses = commerce.addresses
        if addresses.isEmpty {
            addresses = (try? await commerce.loadAddresses()) ?? []
        }
        guard let addressID = (addresses.first(where: \.isDefaultShipping) ?? addresses.first)?.id else {
            reset(to: .needsAddress)
            return
        }

        do {
            let quote = try await catalog.listingQuote(listingID: listingID, shippingAddressID: addressID)
            breakdown = quote
            phase = .quoted
        } catch {
            guard !(error is CancellationError) else { return }
            reset(to: .unavailable)
        }
    }

    private func reset(to phase: Phase) {
        breakdown = nil
        allInShown = false
        wirePriceShown = false
        self.phase = phase
    }

    // MARK: Display

    /// True where surcharges are prohibited and the price shown is the card
    /// price, with wire earning a discount off it. The final total is the same
    /// either way; only the presentation differs.
    var isDiscountPresentation: Bool {
        breakdown?.isDiscountPresentation ?? false
    }

    /// The headline figure in the buy box. Always a server-supplied number:
    /// the grand total when the buyer asked for the all-in view, the quoted
    /// card price under the discount presentation, and otherwise the seller's
    /// listed price exactly as it was published.
    func headlinePrice(for listing: Listing) -> String {
        if allInShown, let breakdown {
            return PriceFormatter.format(breakdown.grandTotal.value, currency: breakdown.currency)
        }
        if let breakdown, breakdown.isDiscountPresentation, let display = breakdown.display {
            return PriceFormatter.format(display.price.value, currency: breakdown.currency)
        }
        return PriceFormatter.format(listing.price.value, currency: listing.currency)
    }

    /// The line under the price. It never states a figure — it only says what
    /// the figure above it already includes.
    var headlineCaption: String {
        if allInShown {
            return "All in — the card fee, sales tax, and shipping are included."
        }
        if isDiscountPresentation {
            return "This is the card price. Taxes and shipping are calculated at checkout."
        }
        return "Taxes and shipping calculated at checkout."
    }

    /// The all-in receipt, itemised from the breakdown. Empty until a quote
    /// exists — there is nothing to itemise from until then.
    var allInRows: [(label: String, value: String)] {
        guard let breakdown else { return [] }
        let currency = breakdown.currency
        var rows: [(label: String, value: String)] = [
            ("Watch", PriceFormatter.format(breakdown.subtotal.value, currency: currency))
        ]
        // Breakdown v2 sends `card_fee.amount`; older payloads only have the
        // legacy convenience-fee key.
        if let fee = breakdown.cardFee?.amount.value ?? breakdown.cardConvenienceFee?.value, fee > 0 {
            rows.append(("Card fee", PriceFormatter.format(fee, currency: currency)))
        }
        if let tax = breakdown.tax {
            rows.append(("Sales tax", PriceFormatter.format(tax.value, currency: currency)))
        }
        rows.append(("Shipping", PriceFormatter.format(breakdown.shipping.value, currency: currency)))
        rows.append(("Total", PriceFormatter.format(breakdown.grandTotal.value, currency: currency)))
        return rows
    }

    /// The lower wire price the discount presentation's second toggle reveals.
    var wirePriceText: String? {
        guard let breakdown, let wire = breakdown.display?.wirePrice else { return nil }
        return PriceFormatter.format(wire.value, currency: breakdown.currency)
    }

    /// The all-in wire figure, when the server sent one. Never derived from
    /// the card total.
    var wireAllInText: String? {
        guard let breakdown, let wire = breakdown.totals?.wire else { return nil }
        return PriceFormatter.format(wire.value, currency: breakdown.currency)
    }

    var wireRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let price = wirePriceText {
            rows.append(("Watch price by wire", price))
        }
        if allInShown, let total = wireAllInText {
            rows.append(("All in by wire", total))
        }
        return rows
    }

    /// Only offered when the server has actually quoted a wire price.
    var canShowWirePrice: Bool {
        isDiscountPresentation && wirePriceText != nil
    }

    /// The return-fee terms this listing's quote carries. A live payload
    /// always beats the marketplace config, so the screen asks here first.
    var quotedReturnFee: ReturnFeeTerms? {
        breakdown?.returnFee
    }
}

// MARK: - Controls

/// The all-in toggle, its itemised receipt, and — where surcharges are
/// prohibited — the payment-method price notice and the wire-price toggle.
///
/// Nothing here renders for a signed-out visitor: they see the seller's listed
/// price, full stop.
struct ListingPriceControls: View {
    @Bindable var model: ListingPricingModel
    let onAddAddress: () -> Void

    var body: some View {
        switch model.phase {
        case .listedPriceOnly, .loading, .unavailable:
            // Nothing to add, and nothing to apologize for — the listed price
            // above is complete and correct on its own.
            EmptyView()
        case .needsAddress:
            addressPrompt
        case .quoted:
            quotedControls
        }
    }

    // MARK: No address yet

    private var addressPrompt: some View {
        CalloutBand(
            icon: "mappin.and.ellipse",
            title: "Add an address to see the all-in price",
            message: "Sales tax and shipping depend on where the watch is going, so we need an address before we can total it up.",
            action: onAddAddress
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your saved addresses.")
    }

    // MARK: Quoted

    private var quotedControls: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            toggleRow(
                title: "Show the all-in price",
                detail: "The watch, the card fee, sales tax, and shipping to your address.",
                isOn: $model.allInShown
            )

            if model.allInShown {
                SpecList(model.allInRows)
                    .transition(.opacity)
            }

            if model.isDiscountPresentation {
                // Clear and conspicuous, as the discount presentation requires
                // — a band the buyer reads, not a footnote they scroll past.
                CalloutBand(
                    icon: "creditcard",
                    title: "Card and wire prices differ here",
                    message: "The price shown includes the cost of paying by card. Paying by wire costs less, and the watch, the tax, and the shipping are identical either way."
                )

                if model.canShowWirePrice {
                    toggleRow(
                        title: "Show the wire price",
                        detail: "What the same watch costs paid by bank transfer.",
                        isOn: $model.wirePriceShown
                    )

                    if model.wirePriceShown {
                        SpecList(model.wireRows)
                            .transition(.opacity)
                    }
                }
            }
        }
        .animation(Motion.easeMedium, value: model.allInShown)
        .animation(Motion.easeMedium, value: model.wirePriceShown)
    }

    private func toggleRow(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Text(detail)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
        }
        .tint(Color.calibre.primary)
        .frame(minHeight: Space.touchTarget)
        .padding(Space.l)
        .background(
            Color.calibre.card,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        // Keep the switch trait — VoiceOver should announce this as a switch
        // with a plain name, not as a merged paragraph.
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
