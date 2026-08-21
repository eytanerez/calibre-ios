import CalibreDesign
import CalibreKit
import SwiftUI

/// Home's "where's my watch" band.
///
/// Anything still moving gets a card at the top of Home so a buyer never has
/// to go looking for it. A finished order (delivered, refunded, cancelled)
/// lingers for a day so the good news is seen, then clears itself.
struct ShipmentTrackerSection: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session
    @Environment(AppRouter.self) private var router

    @State private var orders: [Order] = []
    @State private var loaded = false
    /// Order ids the buyer has dismissed, so a card they've waved off doesn't
    /// come back on the next refresh.
    @AppStorage("dismissedTrackedOrders") private var dismissedRaw = ""

    private var dismissed: Set<String> {
        Set(dismissedRaw.split(separator: ",").map(String.init))
    }

    private var tracked: [Order] {
        orders
            .filter { $0.isWorthTracking && !dismissed.contains($0.id) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    var body: some View {
        Group {
            if session.isAuthenticated, !tracked.isEmpty {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(tracked.count == 1 ? "Your order" : "Your orders")
                        .font(CalibreType.sectionTitle)
                        .foregroundStyle(Color.calibre.foreground)

                    ForEach(tracked) { order in
                        TrackedOrderCard(
                            order: order,
                            onOpen: { router.push(.order(order.id)) },
                            onDismiss: { dismiss(order) }
                        )
                    }
                }
                .padding(.horizontal, Space.margin)
            }
        }
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated else {
                orders = []
                loaded = false
                return
            }
            await load()
        }
    }

    private func load() async {
        // A short page: only the newest handful can still be in motion.
        orders = (try? await services.commerce.orders(page: 1, pageSize: 10).results) ?? []
        loaded = true
    }

    private func dismiss(_ order: Order) {
        Haptics.shared.play(.selection)
        var ids = dismissed
        ids.insert(order.id)
        dismissedRaw = ids.sorted().joined(separator: ",")
    }
}

// MARK: - Card

private struct TrackedOrderCard: View {
    let order: Order
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var steps: [String] {
        ["Paid", "At authentication", "Authenticated", "On its way", "Delivered"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                OrderThumb(url: order.listing?.image?.url)

                VStack(alignment: .leading, spacing: 3) {
                    Text(order.listing?.title ?? "Your watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    Text(order.displayNumber)
                        .font(CalibreType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.calibre.mutedForeground)
                    StatusBadge(order.statusLabel, tone: order.statusTone)
                }

                Spacer(minLength: 0)

                Menu {
                    Button {
                        onOpen()
                    } label: {
                        Label("Track this order", systemImage: "shippingbox")
                    }
                    Button(role: .destructive, action: onDismiss) {
                        Label("Stop tracking here", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .frame(width: Space.touchTarget, height: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tracking options")
            }

            if order.showsProgressTrack {
                ProgressCheckpoints(steps: steps, currentIndex: order.homeTrackerIndex)
            }

            Text(order.statusSummary)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)

            Button("See tracking details", action: onOpen)
                .buttonStyle(.calibre(.secondary, fullWidth: true))
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}

// MARK: - What counts as "in motion"

extension Order {
    /// Still moving, or finished within the last day.
    var isWorthTracking: Bool {
        switch status {
        case .awaitingWire, .purchased, .toAuth, .authPass, .authFail, .toBuyer:
            return true
        case .delivered, .cancelled, .refunded:
            // Good (or final) news is worth seeing once — then it clears.
            guard let settled = updatedAt else { return false }
            return Date.now.timeIntervalSince(settled) < 24 * 60 * 60
        case .unknown:
            return false
        }
    }

    /// The five-step track only makes sense once money has actually moved.
    var showsProgressTrack: Bool {
        switch status {
        case .awaitingWire, .cancelled, .refunded, .unknown: false
        default: true
        }
    }

    var homeTrackerIndex: Int {
        switch status {
        case .purchased: 0
        case .toAuth: 1
        case .authPass, .authFail: 2
        case .toBuyer: 3
        case .delivered: 4
        default: 0
        }
    }
}
