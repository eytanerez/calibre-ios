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
        /// The quote didn't land at all. Fall back to the listed price
        /// silently — a stale or half-assembled total is worse than no total.
        ///
        /// Not the tax outage: that used to arrive here as a 503 and take the
        /// whole panel with it, and now arrives as a priced 200 that reaches
        /// `.quoted` with `breakdown.isTaxUnavailable` set. This case means
        /// the server priced nothing.
        case unavailable
    }

    private(set) var phase: Phase = .listedPriceOnly
    private(set) var breakdown: CheckoutBreakdown?

    /// Whether the buyer wants to see the all-in price.
    ///
    /// **A preference of the person's, not state of the listing.** It used to
    /// be a plain stored property on a model built fresh per watch, so turning
    /// it on and opening the next watch turned it off again — somebody who
    /// shops for totals had to ask for the total on every single listing. The
    /// address the quote is priced against is already remembered; this is the
    /// other half of the same answer, and it is read back on every watch.
    ///
    /// Default OFF for a buyer who has never touched it, per the display
    /// rules: the seller's listed price is what a first visit shows.
    var allInShown: Bool {
        get {
            access(keyPath: \.allInShown)
            return defaults.bool(forKey: Self.allInPreferenceKey)
        }
        set {
            withMutation(keyPath: \.allInShown) {
                defaults.set(newValue, forKey: Self.allInPreferenceKey)
            }
        }
    }

    static let allInPreferenceKey = "listingAllInPricing"

    /// The discount-presentation companion — reveals the lower wire price.
    /// Default OFF and not persisted: it is offered on the minority of
    /// listings priced this way, and it answers "what would wire cost here",
    /// which is a question about this watch rather than a standing choice.
    var wirePriceShown = false

    @ObservationIgnored private let listingID: String
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let commerce: CommerceStore
    @ObservationIgnored private let defaults: UserDefaults

    init(
        listingID: String,
        catalog: CatalogStore,
        commerce: CommerceStore,
        defaults: UserDefaults = .standard
    ) {
        self.listingID = listingID
        self.catalog = catalog
        self.commerce = commerce
        self.defaults = defaults
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

    /// Clears the quote and the controls that read from it.
    ///
    /// `allInShown` is deliberately left alone: it is the buyer's standing
    /// preference, and a signed-out visit or a listing with no address to
    /// price against is not them changing their mind. Writing false here
    /// would erase the preference on the way past.
    private func reset(to phase: Phase) {
        breakdown = nil
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
    /// the wire total when the buyer asked for the all-in view, the quoted
    /// card price under the discount presentation, and otherwise the seller's
    /// listed price exactly as it was published.
    func headlinePrice(for listing: Listing) -> String {
        if allInShown, let breakdown {
            let total = breakdown.totals?.wire?.value ?? breakdown.grandTotal.value
            return PriceFormatter.format(total, currency: breakdown.currency)
        }
        if let breakdown, breakdown.isDiscountPresentation, let display = breakdown.display {
            return PriceFormatter.format(display.price.value, currency: breakdown.currency)
        }
        return PriceFormatter.format(listing.price.value, currency: listing.currency)
    }

    /// True when the server priced everything except sales tax. The quote
    /// endpoints used to answer 503 during a tax outage and the whole panel
    /// went with it; now they price the rest and flag the gap, so the figures
    /// are real and every total behind them is a before-tax total.
    var isTaxUnavailable: Bool {
        breakdown?.isTaxUnavailable ?? false
    }

    /// The sentence to print under the receipt during a tax outage — the
    /// server's own words where it sent them, so the app and the site explain
    /// the same outage the same way, and a fallback carrying the identical
    /// meaning for a server that sent none.
    var taxUnavailableNote: String? {
        guard let breakdown, breakdown.isTaxUnavailable else { return nil }
        let served = breakdown.taxUnavailableWarning?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let served, !served.isEmpty { return served }
        return Self.taxUnavailableFallback
    }

    static let taxUnavailableFallback = "Sales tax could not be calculated just now, so it is not included here. The full total, tax included, is shown again at checkout before you pay."

    /// The line under the price. It never states a figure — it only says what
    /// the figure above it already includes.
    var headlineCaption: String {
        if allInShown {
            if isTaxUnavailable {
                // The headline is the wire total, which is missing its tax line.
                // Calling that "all in" would be the one wrong word here.
                return "The wire price and shipping are included. Sales tax is not — it could not be calculated just now."
            }
            return "Full cost delivered — the wire price, sales tax, and shipping are included."
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
            ("Watch price by wire", PriceFormatter.format(breakdown.subtotal.value, currency: currency))
        ]
        if isTaxUnavailable {
            // The server sends 0.00 here during an outage, and a tax row that
            // is dropped — or printed as zero — reads as "no tax is owed".
            // That is a much more expensive claim than "we could not work it
            // out", so the row stays and says which one it is.
            rows.append(("Sales tax", "Not available right now"))
        } else if let tax = breakdown.tax {
            rows.append(("Sales tax", PriceFormatter.format(tax.value, currency: currency)))
        }
        rows.append(("Shipping", PriceFormatter.format(breakdown.shipping.value, currency: currency)))
        rows.append((
            isTaxUnavailable ? "Full cost delivered, before tax" : "Full cost delivered",
            PriceFormatter.format(
                breakdown.totals?.wire?.value ?? breakdown.grandTotal.value,
                currency: currency
            )
        ))
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
            // `totals.wire` is missing the same tax line the card total is.
            rows.append((
                isTaxUnavailable ? "Total paying by wire, before tax" : "All in by wire",
                total
            ))
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
                title: "Show the full cost delivered",
                detail: model.isTaxUnavailable
                    ? "The wire price and shipping to your address. Sales tax could not be calculated just now."
                    : "The wire price, sales tax, and shipping to your address.",
                isOn: $model.allInShown
            )

            if model.allInShown {
                SpecList(model.allInRows)
                    .transition(.opacity)

                // The receipt above already labels its own totals "before
                // tax"; this is the sentence that says what happens next, and
                // it is the server's wherever the server sent one.
                if let note = model.taxUnavailableNote {
                    Text(note)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
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
            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
        // Keep the switch trait — VoiceOver should announce this as a switch
        // with a plain name, not as a merged paragraph.
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
