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
                        LazyVStack(spacing: Space.m) {
                            ForEach(orders) { order in
                                Button {
                                    services.router.open(.order(order.id))
                                } label: {
                                    OrderRow(order: order)
                                }
                                .buttonStyle(PressableStyle())
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

/// A single order row — thumbnail, title, order number, status summary, total.
struct OrderRow: View {
    let order: Order

    var body: some View {
        HStack(spacing: Space.m) {
            OrderThumb(url: order.listing?.image?.url)

            VStack(alignment: .leading, spacing: 4) {
                Text(order.listing?.title ?? "Your watch")
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
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

extension Error {
    var orderMessage: String {
        (self as? APIError)?.errorDescription ?? "Something went wrong. Please try again."
    }
}
