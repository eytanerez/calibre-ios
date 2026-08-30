import CalibreDesign
import CalibreKit
import SwiftUI

/// How the shop is doing, and what buyers are asking for.
///
/// Every figure here is one the server sent. Nothing on this tab is worked
/// out from another number: where the payload is silent the line is absent,
/// and where it is silent about a *ratio* the tab says so in words rather
/// than printing a zero nobody measured.
struct SellerPerformanceTab: View {
    let metrics: SellerDashboardMetrics
    let whatToList: [ListingSuggestion]
    /// The seller's sales, newest first, as the ops store loaded them.
    let sales: [Order]
    /// Open buyer requests. Verified dealers only — empty for everyone else.
    let requests: [WatchRequest]
    let actions: SellerShopActions

    /// Enough of the sales list to show the shape of the week without the tab
    /// turning into a second inventory.
    private static let recentSalesShown = 5

    var body: some View {
        Group {
            attention.sellRow()
            money.sellRow()
            if !inventoryTiles.isEmpty {
                inventoryAtAGlance.sellRow()
            }
            recentSales.sellRow()
            if !whatToList.isEmpty {
                demand.sellRow()
            }
            if !requests.isEmpty {
                buyerRequests.sellRow()
            }
        }
    }

    // MARK: - Attention

    private var attention: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Attention")

            SellCard {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        headlineFigure(metrics.totalViews.formatted(.number), label: "views")
                        Rectangle()
                            .fill(Color.calibre.border)
                            .frame(width: 1, height: 44)
                        headlineFigure(metrics.totalWatchers.formatted(.number), label: "watching")
                    }
                    .padding(.vertical, Space.l)

                    Rectangle().fill(Color.calibre.border).frame(height: 1)

                    SellFigureRow(
                        label: "Views that became a sale",
                        value: conversionValue,
                        caption: conversionCaption
                    )
                }
            }
        }
    }

    private func headlineFigure(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(CalibreType.price)
                .monospacedDigit()
                .foregroundStyle(Color.calibre.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Never "0%": three of the four readings are not a percentage at all.
    private var conversionValue: String {
        switch metrics.conversionReading {
        case .noViewsYet: "\u{2014}"
        case .noOrdersYet: "None yet"
        case .belowPrecision: "Under 0.01%"
        case .rate(let text): "\(text)%"
        }
    }

    private var conversionCaption: String? {
        switch metrics.conversionReading {
        case .noViewsYet: "Nobody has opened a listing yet, so there is nothing to divide."
        case .noOrdersYet: "Buyers are looking. None of those visits has ended in a sale yet."
        case .belowPrecision, .rate: nil
        }
    }

    // MARK: - The money

    private var money: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("The money")

            if metrics.grossSales.value == 0, metrics.pendingPayoutTotal.value == 0 {
                Text("Nothing has sold yet. When it does, this is where what buyers paid and what reached you sit side by side.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SellCard {
                    VStack(spacing: 0) {
                        SellFigureRow(
                            label: "What buyers paid",
                            value: PriceFormatter.format(metrics.grossSales.value)
                        )
                        Rectangle().fill(Color.calibre.border).frame(height: 1)
                        if metrics.withheldFromSales > 0 {
                            SellFigureRow(
                                label: "Commission, labels and refunds",
                                value: "\u{2212} " + PriceFormatter.format(metrics.withheldFromSales),
                                caption: "Calibre\u{2019}s commission on each sale, the to-authentication label Calibre bought for it, and anything refunded."
                            )
                            Rectangle().fill(Color.calibre.border).frame(height: 1)
                        }
                        SellFigureRow(
                            label: "What reached you",
                            value: PriceFormatter.format(metrics.netSales.value),
                            emphasized: true
                        )
                        Rectangle().fill(Color.calibre.border).frame(height: 1)
                        SellFigureRow(
                            label: "Still to be released",
                            value: PriceFormatter.format(metrics.pendingPayoutTotal.value),
                            caption: "Yours already, and on its way \u{2014} a payout is sent once the buyer has the watch."
                        )
                    }
                }
            }
        }
    }

    // MARK: - Inventory at a glance

    /// Only the states the payload counts, and only where the count is real.
    /// Each tile leads to the same rows on the Listings tab, so a figure here
    /// is never a number a seller has to go hunting for.
    private var inventoryTiles: [(filter: SellerListingFilter, count: Int)] {
        [
            (.live, metrics.activeListings),
            (.inReview, metrics.pendingReviewListings),
            (.draft, metrics.draftListings),
            (.needsChanges, metrics.rejectedListings),
            (.sold, metrics.soldListings),
            (.archived, metrics.archivedListings),
        ].filter { $0.count > 0 }
    }

    private var inventoryAtAGlance: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Your inventory")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Space.m)],
                spacing: Space.m
            ) {
                ForEach(inventoryTiles, id: \.filter) { tile in
                    Button {
                        actions.showListings(tile.filter)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.count.formatted(.number))
                                .font(CalibreType.price)
                                .monospacedDigit()
                                .foregroundStyle(Color.calibre.primary)
                            Text(tile.filter.title)
                                .font(CalibreType.caption)
                                .foregroundStyle(Color.calibre.mutedForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Space.l)
                        .background(Color.calibre.card)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                                .strokeBorder(Color.calibre.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(tile.count) \(tile.filter.title)")
                    .accessibilityHint("Shows them in Listings")
                }
            }
        }
    }

    // MARK: - Recent sales

    private var recentSales: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Recent sales")
            if sales.isEmpty {
                Text("When a watch sells, everything you need to ship it lands here.")
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SellCard {
                    VStack(spacing: 0) {
                        let shown = Array(sales.prefix(Self.recentSalesShown))
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, order in
                            saleRow(order)
                            if index < shown.count - 1 {
                                Rectangle().fill(Color.calibre.border).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func saleRow(_ order: Order) -> some View {
        let badge = SellerStatusDisplay.badge(forOrder: order.status)
        let needsLabel = order.sellerActionState == "sold_awaiting_label_creation"
        return Button {
            actions.openSale(order.id)
        } label: {
            HStack(spacing: Space.m) {
                SellThumb(url: order.listing?.image?.url, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.listing?.title ?? "Sold watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    StatusBadge(badge.text, tone: badge.tone)
                }
                Spacer(minLength: Space.s)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PriceFormatter.format(order.subtotal.value, currency: order.currency))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)
                    // The compact payout line: what this sale pays and where
                    // that payout stands. The full ledger is one tap away on
                    // the sale itself.
                    if let payout = payoutLine(order) {
                        Text(payout)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(needsLabel ? "Add shipping details" : "View sale")
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
    }

    /// "You receive $9,400 \u{00B7} Scheduled" \u{2014} both halves the server's, and
    /// the line is simply absent when it has not stated the amount.
    private func payoutLine(_ order: Order) -> String? {
        guard let amount = order.payoutBlock?.amount?.value else { return nil }
        let money = PriceFormatter.format(amount, currency: order.currency)
        guard let status = order.payoutBlock?.statusLabel, !status.isEmpty else {
            return "You receive \(money)"
        }
        return "You receive \(money) \u{00B7} \(status)"
    }

    // MARK: - What buyers are asking for

    private var demand: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("What to list next")

            Text("References buyers are watching, where there isn\u{2019}t much for sale.")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.m) {
                ForEach(Array(whatToList.enumerated()), id: \.offset) { _, suggestion in
                    suggestionCard(suggestion)
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: ListingSuggestion) -> some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.s) {
                Eyebrow(suggestion.reason)

                Text(suggestionTitle(suggestion))
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if let reference = suggestion.referenceNumber, !reference.isEmpty {
                    Text(reference)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }

                let facts = suggestionFacts(suggestion)
                if !facts.isEmpty {
                    Text(facts.joined(separator: " \u{00B7} "))
                        .font(CalibreType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        // The separators are typographic; spoken, they are commas.
                        .accessibilityLabel(facts.joined(separator: ", "))
                }

                Button("List one") {
                    actions.listWatch(
                        ListingPrefill(
                            brand: suggestion.brand,
                            model: suggestion.model,
                            reference: suggestion.referenceNumber
                        )
                    )
                }
                .buttonStyle(.calibre(.secondary, fullWidth: true))
                .padding(.top, Space.xs)
            }
            .padding(Space.l)
        }
    }

    private func suggestionTitle(_ suggestion: ListingSuggestion) -> String {
        guard let model = suggestion.model, !model.isEmpty else { return suggestion.brand }
        return "\(suggestion.brand) \(model)"
    }

    /// Only the figures the payload actually carries — a suggestion that
    /// arrives without them says less rather than saying zero.
    private func suggestionFacts(_ suggestion: ListingSuggestion) -> [String] {
        var facts: [String] = []
        if let supply = suggestion.activeSupply {
            facts.append(supply == 1 ? "1 for sale" : "\(supply.formatted(.number)) for sale")
        }
        if let watchers = suggestion.watchers, watchers > 0 {
            facts.append("\(watchers.formatted(.number)) watching")
        }
        if let views = suggestion.views, views > 0 {
            facts.append("\(views.formatted(.number)) views")
        }
        return facts
    }

    // MARK: - Buyer requests

    /// A single summary row rather than the requests themselves — the tab
    /// stays scannable; the full list lives one tap away.
    private var buyerRequests: some View {
        Button {
            actions.openBuyerRequests()
        } label: {
            HStack(spacing: Space.m) {
                IconTile(systemName: "sparkle.magnifyingglass")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Buyers are looking for \(requests.count) watch\(requests.count == 1 ? "" : "es")")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("List against an open request")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .padding(Space.l)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows every open buyer request")
    }
}

// MARK: - One ruled line of figures

/// Label on the left, figure on the right, and the two stacked instead when
/// they cannot share a line — a figure is never shortened to fit, and a
/// truncated number is a wrong number.
struct SellFigureRow: View {
    let label: String
    let value: String
    var caption: String?
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    labelText
                    Spacer(minLength: Space.m)
                    valueText.fixedSize()
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    labelText
                    valueText.fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let caption {
                Text(caption)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        Text(label)
            .font(emphasized ? CalibreType.bodyMedium : CalibreType.body)
            .foregroundStyle(emphasized ? Color.calibre.foreground : Color.calibre.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .font(emphasized ? CalibreType.price : CalibreType.bodyMedium)
            .monospacedDigit()
            .foregroundStyle(Color.calibre.foreground)
    }
}
