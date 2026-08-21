import CalibreDesign
import CalibreKit
import SwiftUI

/// The buyer's orders — searchable, filterable, paginated. Guests get a warm
/// sign-in prompt; the list gates through the auth session.
struct OrdersListScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var orders: [Order] = []
    @State private var phase: LoadPhase = .idle
    @State private var search = ""
    @State private var searchTask: Task<Void, Never>?

    private enum LoadPhase: Equatable { case idle, loading, loaded, failed(String) }

    var body: some View {
        Group {
            if !session.isAuthenticated {
                EmptyState(
                    icon: "shippingbox",
                    title: "Your orders live here",
                    message: "Sign in to follow a watch from purchase through authentication to your door.",
                    actionTitle: "Sign in"
                ) {
                    session.require("Sign in to see your orders") {}
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        }
        .background(Color.calibre.background)
        .task(id: session.isAuthenticated) {
            if session.isAuthenticated, phase == .idle { await load() }
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle where orders.isEmpty, .loading where orders.isEmpty:
            VStack(spacing: Space.m) {
                ForEach(0..<4, id: \.self) { _ in OrderRowSkeleton() }
            }
            .padding(Space.margin)
        case .failed(let message):
            EmptyState(
                icon: "wifi.exclamationmark",
                title: "Couldn't load your orders",
                message: message,
                actionTitle: "Try again"
            ) { Task { await load() } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            if orders.isEmpty && search.isEmpty {
                // A genuinely empty account — no search bar needed.
                EmptyState(
                    icon: "shippingbox",
                    title: "No orders yet",
                    message: "When you buy a watch, you'll follow every step of its journey here."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Keep the search field mounted even when a query returns no
                // matches, so the user can always clear or edit it.
                ScrollView {
                    if orders.isEmpty {
                        EmptyState(
                            icon: "magnifyingglass",
                            title: "No matches",
                            message: "No orders match \u{201C}\(search)\u{201D}. Try a different order number or watch name."
                        )
                        .padding(.top, Space.xxl)
                    } else {
                        LazyVStack(spacing: Space.l) {
                            ForEach(sections) { section in
                                if section.isPurchase {
                                    purchaseGroup(section)
                                } else if let order = section.orders.first {
                                    orderButton(order)
                                }
                            }
                        }
                        .padding(Space.margin)
                    }
                }
                .searchable(text: $search, prompt: "Search orders")
                .onChange(of: search) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        await load()
                    }
                }
            }
        }
    }

    // MARK: - Grouping

    /// Orders bought together belong together. Rows that share a
    /// `checkout_group_id` are gathered under one purchase header, in the
    /// order the server returned them; everything else stands alone, exactly
    /// as it always has.
    private var sections: [OrderSection] {
        var order: [String] = []
        var buckets: [String: [Order]] = [:]
        for row in orders {
            // An order with no group — or the only one of its group on this
            // page — is its own row, keyed by id so it can never merge.
            let key = row.checkoutGroupId.map { "group:\($0)" } ?? "order:\(row.id)"
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(row)
        }
        return order.map { OrderSection(id: $0, orders: buckets[$0] ?? []) }
    }

    private func orderButton(_ order: Order) -> some View {
        Button {
            services.router.push(.order(order.id))
        } label: {
            OrderRow(order: order)
        }
        .buttonStyle(PressableStyle())
    }

    /// One purchase: when it was bought, how many watches it covered, and a
    /// row per watch beneath — each still its own order, opening on its own.
    private func purchaseGroup(_ section: OrderSection) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Eyebrow("One purchase")
                Spacer()
                Text(section.headline)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("One purchase, \(section.headline)")

            VStack(spacing: Space.s) {
                ForEach(section.orders) { order in
                    orderButton(order)
                }
            }
            .padding(Space.s)
            .background(
                Color.calibre.secondary.opacity(0.35),
                in: RoundedRectangle(cornerRadius: Radius.card + Space.s, style: .continuous)
            )
        }
    }

    private func load() async {
        if orders.isEmpty { phase = .loading }
        do {
            let page = try await services.commerce.orders(search: search.isEmpty ? nil : search)
            orders = page.results
            phase = .loaded
        } catch {
            phase = .failed(error.orderMessage)
        }
    }
}

/// One row of the orders list: a lone order, or the orders of one purchase.
private struct OrderSection: Identifiable {
    let id: String
    let orders: [Order]

    /// Only a purchase that actually covered more than one watch gets a
    /// header — a single order needs no explaining.
    var isPurchase: Bool { orders.count > 1 }

    /// "14 Aug 2026 · 3 watches". The count is the purchase's own, from the
    /// order payload, so a page that happens to show only two of three still
    /// says what was bought.
    var headline: String {
        let count = orders.first?.purchaseItemCount ?? orders.count
        let watches = count == 1 ? "1 watch" : "\(count) watches"
        guard let date = orders.compactMap(\.createdAt).min() else { return watches }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) · \(watches)"
    }
}

/// A single order row — thumbnail, title, order number, status summary, total.
struct OrderRow: View {
    let order: Order

    var body: some View {
        HStack(spacing: Space.m) {
            OrderThumb(url: order.listing?.image?.url)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Space.s) {
                    Text(order.listing?.title ?? "Your watch")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .lineLimit(1)
                    Text(order.displayNumber)
                        .font(CalibreType.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .layoutPriority(1)
                }
                Text(order.statusSummary)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .lineLimit(1)
                HStack(spacing: Space.s) {
                    StatusBadge(order.statusLabel, tone: order.statusTone)
                    Text(PriceFormatter.format(order.grandTotal.value, currency: order.currency))
                        .font(CalibreType.priceSmall)
                        .foregroundStyle(Color.calibre.foreground)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.calibre.placeholder)
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}

struct OrderThumb: View {
    let url: URL?
    var body: some View {
        ListingImageWell(url: url, targetWidth: 120)
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

private struct OrderRowSkeleton: View {
    var body: some View {
        HStack(spacing: Space.m) {
            RoundedRectangle(cornerRadius: Radius.control).frame(width: 60, height: 60).shimmer()
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().frame(width: 160, height: 12).shimmer()
                Rectangle().frame(width: 100, height: 10).shimmer()
                Rectangle().frame(width: 80, height: 14).shimmer()
            }
            Spacer()
        }
        .padding(Space.l)
        .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.calibre.border, lineWidth: 1))
    }
}

// MARK: - Status presentation

extension Order {
    var statusLabel: String {
        switch status {
        case .awaitingWire: "Waiting for wire"
        case .purchased: "Paid"
        case .toAuth: "To authentication"
        case .authPass: "Authenticated"
        case .authFail: "Authentication issue"
        case .toBuyer: "On its way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        case .refunded: "Refunded"
        case .unknown: "Processing"
        }
    }

    var statusSummary: String {
        switch status {
        case .awaitingWire: "Complete your wire transfer to secure this watch."
        case .purchased: "Paid. The seller is preparing to ship it to authentication."
        case .toAuth: "On its way to our authentication center."
        case .authPass: "Authenticated by our watchmakers. Shipping to you next."
        case .authFail: "We found an issue during authentication. Our team will follow up by email."
        case .toBuyer: "Shipped to you and on the way."
        case .delivered: "Delivered. We hope you love it."
        case .cancelled: "This order was cancelled."
        case .refunded: "This order was refunded."
        case .unknown: "We're processing your order."
        }
    }

    var statusTone: StatusBadge.Tone {
        switch status {
        case .delivered, .authPass: .success
        case .awaitingWire, .toAuth, .toBuyer, .purchased: .info
        case .authFail: .warning
        case .cancelled, .refunded: .danger
        case .unknown: .neutral
        }
    }
}

extension OrderStatus {
    /// Nothing more is going to happen to this order.
    var isFinished: Bool {
        switch self {
        case .delivered, .cancelled, .refunded: true
        default: false
        }
    }
}

extension Error {
    var orderMessage: String {
        (self as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
