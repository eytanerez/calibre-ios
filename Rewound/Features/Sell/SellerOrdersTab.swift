import RewoundDesign
import RewoundKit
import SwiftUI

/// The seller's sold watches and the money on them.
///
/// This room reorganises access to work that already exists: every row opens
/// the sale screen or the shipping form it has always opened, every figure is
/// one the server priced, and the ledger is `PayoutLedger` — the same one the
/// sale screen prints. Nothing here is a second order system.
///
/// Two rules it holds to. Nothing infers that money reached a bank: a released
/// payout has left Rewound and carries the server's expected arrival, and no
/// line here says it landed. And a payout with nothing on the payload to
/// describe it says its state is unclear rather than falling back to
/// "Scheduled", which is a promise of money on its way.
struct SellerOrdersTab: View {
    let metrics: SellerDashboardMetrics
    /// The seller's sales, newest first, as the ops store loaded them.
    let sales: [Order]
    /// The sales request failed, so an empty list is not an answer.
    let salesFailed: Bool
    let actions: SellerShopActions

    var body: some View {
        Group {
            owed.sellRow()
            salesSection.sellRow()
        }
    }

    // MARK: - What is owed

    private var owed: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Payouts")

            SellCard {
                SellFigureRow(
                    label: "Owed to you, not yet released",
                    value: PriceFormatter.format(metrics.pendingPayoutTotal.value),
                    caption: "Yours already. A payout is sent once the sale settles, and each sale below says which rule decides its timing.",
                    emphasized: true
                )
            }
        }
    }

    // MARK: - The sales

    private var salesSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SellSectionHeader("Your sales")

            Text("Where each sale has got to, who it is waiting on, and what you are due on it. The sale carries the line-by-line ledger and the paperwork.")
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if salesFailed, sales.isEmpty {
                // Not "you have no sales". A list we could not fetch and a list
                // the server actually sent empty are different sentences, and
                // telling a seller who is owed money that nothing is coming is
                // the worse of the two to get wrong.
                CalloutBand(
                    icon: "wifi.slash",
                    title: "Your sales didn't load",
                    message: "Nothing about them has changed. Pull to refresh in a moment."
                )
            } else if sales.isEmpty {
                Text("Sales appear here after a buyer completes checkout.")
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if salesFailed {
                    Text("This is the last list that loaded — the most recent check didn't come back.")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: Space.m) {
                    ForEach(sales) { order in
                        SaleCard(order: order, actions: actions)
                    }
                }
            }
        }
    }
}

// MARK: - One sale

/// A sale as the seller has to act on it: what it is, where it has got to, whose
/// move it is, what they are due, and where the payout stands.
private struct SaleCard: View {
    let order: Order
    let actions: SellerShopActions

    private var step: SellerSaleStep { order.sellerNextStep }
    private var payoutState: SellerPayoutState { order.sellerPayoutState }

    var body: some View {
        SellCard {
            VStack(alignment: .leading, spacing: Space.m) {
                identity
                chips
                whoseMove
                if let breakdown = order.payoutBlock?.breakdown {
                    PayoutLedger(
                        breakdown: breakdown,
                        currency: order.currency,
                        title: "What you are due"
                    )
                }
                payoutStanding
                openButton
            }
            .padding(Space.l)
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: Space.m) {
            SellThumb(url: order.listing?.image?.url, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(order.listing?.title ?? "Sold watch")
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reference)
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The number a seller says out loud, the day it sold, and what the buyer
    /// paid. A payload missing any of the three simply leaves that part out
    /// rather than printing a placeholder for it.
    private var reference: String {
        var parts: [String] = []
        if let number = order.orderNumber {
            parts.append("#\(number)")
        }
        if let sold = order.createdAt {
            parts.append(sold.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append(PriceFormatter.format(order.subtotal.value, currency: order.currency))
        return parts.joined(separator: " · ")
    }

    private var chips: some View {
        let badge = SellerStatusDisplay.badge(forOrder: order.status)
        return HStack(spacing: Space.s) {
            StatusBadge(badge.text, tone: badge.tone)
            StatusBadge(payoutState.label, tone: payoutTone)
            Spacer(minLength: 0)
        }
    }

    /// Only a failed payout is an alarm. Everything else is a state, including
    /// a hold — money Rewound has not sent yet is not money that went wrong.
    private var payoutTone: StatusBadge.Tone {
        switch payoutState {
        case .failed: .danger
        case .released: .success
        case .scheduled, .held, .closed, .unknown: .neutral
        }
    }

    private var whoseMove: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.who)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
            Text(step.what)
                .font(RewoundType.body)
                .foregroundStyle(Color.rewound.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Where the payout stands

    @ViewBuilder
    private var payoutStanding: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Payout: \(order.sellerPayoutStatusLine)")
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(payoutDates)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            if order.payoutBlock?.firstPayoutHold == true {
                Text("First payouts take longer than later ones; the date above already allows for it.")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = order.payoutBlock?.failureReason, !failure.isEmpty {
                Text("This payout didn't go through: \(failure)")
                    .font(RewoundType.caption)
                    .foregroundStyle(Color.rewound.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The dates a payout actually has.
    ///
    /// A released payout has left Rewound and has an estimated arrival; nothing
    /// here has seen it land anywhere. A payout that did not go through gets no
    /// arrival date at all rather than one already contradicted, and a closed
    /// or unrecognised one is never told it is "not released yet" — that is a
    /// promise for money still coming.
    private var payoutDates: String {
        let released = order.payoutBlock?.releasedAt ?? order.payoutReleasedAt
        let releasedText = released.map { $0.formatted(date: .abbreviated, time: .omitted) }

        if payoutState == .failed {
            let sent = releasedText.map { "Sent \($0)." } ?? "Not sent yet."
            return "\(sent) We'll tell you when it is sent again."
        }
        guard payoutState.isStillComing else {
            return releasedText.map { "Released \($0)." } ?? "Nothing further is due on this sale."
        }
        guard let releasedText else {
            return "Not released yet."
        }
        guard let arrival = order.payoutBlock?.expectedArrivalAt else {
            return "Released \(releasedText). We'll show a date for your bank once we have one."
        }
        return "Released \(releasedText) · should reach your bank \(arrival.formatted(date: .abbreviated, time: .omitted))"
    }

    /// One destination either way — the shipping form lives on the sale screen
    /// — so the label is what changes, not the tap.
    private var openButton: some View {
        Button {
            actions.openSale(order.id)
        } label: {
            Text(step.needsShippingDetails ? "Add shipping details" : "View sale")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.rewound(step.needsShippingDetails ? .primary : .secondary, fullWidth: true))
    }
}
