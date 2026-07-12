import CalibreDesign
import CalibreKit
import NukeUI
import SwiftUI

/// One sale, from the seller's side: what sold, who bought it, the money
/// breakdown, and the fulfillment path (label purchase → label ready).
/// Owns its NavigationStack — present it modally, don't push it.
struct SaleDetailScreen: View {
    let orderID: String

    @Environment(SellSession.self) private var sell
    @Environment(\.dismiss) private var dismiss

    private enum FlowStep: Hashable {
        case purchaseLabel
        case labelReady
    }

    @State private var order: Order?
    @State private var loadError: String?
    @State private var path: [FlowStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let order {
                    content(order)
                } else if let loadError {
                    EmptyState(
                        icon: "shippingbox",
                        title: "This sale didn't load",
                        message: loadError,
                        actionTitle: "Try again",
                        action: { Task { await load() } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    saleSkeleton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.calibre.background.ignoresSafeArea())
            .navigationTitle("Your sale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .navigationDestination(for: FlowStep.self) { step in
                switch step {
                case .purchaseLabel:
                    if let order {
                        LabelPurchaseFlow(order: order) { updated in
                            self.order = updated
                            path = [.labelReady]
                        }
                    }
                case .labelReady:
                    if let order {
                        LabelReadyScreen(order: order)
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        loadError = nil
        do {
            order = try await sell.ops.order(id: orderID)
        } catch {
            loadError = sellErrorMessage(error)
        }
    }

    private var awaitingLabel: Bool {
        guard let order else { return false }
        return order.sellerActionState == "sold_awaiting_label_creation"
            || (order.status == .purchased && order.toAuthShipment == nil)
    }

    // MARK: - Content

    private func content(_ order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                summary(order)

                if let deadline = order.fulfillmentDeadlineAt, awaitingLabel {
                    HStack(spacing: Space.m) {
                        Text("Ship by")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.secondaryForeground)
                        CountdownChip(until: deadline)
                    }
                }

                financials(order)

                if awaitingLabel {
                    VStack(spacing: Space.s) {
                        Button("Get shipping label") {
                            path.append(.purchaseLabel)
                        }
                        .buttonStyle(.calibre(.primary, fullWidth: true))
                        Text("A prepaid, insured label to our authentication center. The cost is yours; the quote comes up next.")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                } else if order.toAuthShipment != nil {
                    Button("View shipping label") {
                        path.append(.labelReady)
                    }
                    .buttonStyle(.calibre(.secondary, fullWidth: true))
                }
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xxl)
        }
    }

    private func summary(_ order: Order) -> some View {
        let badge = SellerStatusDisplay.badge(forOrder: order.status)
        return SellCard {
            HStack(spacing: Space.m) {
                SellThumb(url: order.listing?.image?.url, size: 64)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(order.listing?.title ?? "Sold watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(2)
                    StatusBadge(badge.text, tone: badge.tone)
                    if let buyer = order.shippingAddress?.fullName, !buyer.isEmpty {
                        Text("Sold to \(buyer)")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Space.l)
        }
    }

    private func financials(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Your payout")
                .font(CalibreType.sectionTitle)
                .foregroundStyle(Color.calibre.foreground)
            SpecList(financialRows(order))
        }
    }

    private func financialRows(_ order: Order) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Sale price", PriceFormatter.format(order.subtotal.value)),
        ]
        if let fee = order.sellerFeeAmount?.value {
            let percent = order.sellerFeePercentApplied?.value
            let keep = percent.map { 100 - $0 }
            let label = keep.map { "Commission (you keep \(compactPercent($0))%)" } ?? "Commission"
            rows.append((label, "− \(PriceFormatter.format(fee))"))
            rows.append(("Estimated payout", PriceFormatter.format(max(order.subtotal.value - fee, 0))))
        }
        rows.append(("Payout status", payoutStatusText(order)))
        if let released = order.payoutReleasedAt {
            rows.append(("Released", released.formatted(date: .abbreviated, time: .omitted)))
        }
        return rows
    }

    private func compactPercent(_ value: Decimal) -> String {
        var raw = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    private func payoutStatusText(_ order: Order) -> String {
        switch order.payoutStatus {
        case "released": "Released"
        case "pending_connect": "Waiting on your Stripe account"
        case "reversed": "Reversed"
        case "refunded": "Refunded"
        case .some(let other) where !other.isEmpty:
            other.replacingOccurrences(of: "_", with: " ").capitalized
        default: "Pending — releases after authentication"
        }
    }

    private var saleSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Rectangle().frame(maxWidth: .infinity).frame(height: 96).shimmer()
            Rectangle().frame(width: 160, height: 20).shimmer()
            Rectangle().frame(maxWidth: .infinity).frame(height: 180).shimmer()
            Spacer()
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.l)
    }
}
