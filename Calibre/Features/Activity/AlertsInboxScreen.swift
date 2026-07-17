import CalibreDesign
import CalibreKit
import SwiftUI

/// The Alerts inbox. Signed-in members read the server-side notification
/// record (shared with the web bell — saved-search matches, price drops,
/// order and offer updates land here even if the push never arrived); guests
/// see the device-local push history.
struct AlertsInboxScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AuthSession.self) private var session

    @State private var isLoading = false

    private var serverBacked: Bool { session.isAuthenticated }

    private var rows: [AlertRowData] {
        if serverBacked {
            return services.serverAlerts.notifications.map(AlertRowData.init(notification:))
        }
        return services.alerts.items.map(AlertRowData.init(item:))
    }

    private var unreadCount: Int {
        serverBacked ? services.serverAlerts.unreadCount : services.alerts.unreadCount
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                if isLoading {
                    ScrollView {
                        VStack(spacing: Space.s) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .fill(Color.calibre.card)
                                    .frame(height: 76)
                                    .shimmer()
                            }
                        }
                        .padding(Space.margin)
                    }
                } else {
                    EmptyState(
                        icon: "bell",
                        title: "Nothing yet",
                        message: "We'll nudge you the moment something needs you — a reply to an offer, an update on an order, a price drop on a watch you saved."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.s) {
                        ForEach(rows) { row in
                            AlertRow(row: row) {
                                open(row)
                            }
                        }
                    }
                    .padding(Space.margin)
                }
            }
        }
        .background(Color.calibre.background)
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { markAllRead() }
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
        }
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await loadIfNeeded(force: true)
        }
    }

    private func loadIfNeeded(force: Bool = false) async {
        guard serverBacked else { return }
        if !force, !services.serverAlerts.notifications.isEmpty { return }
        isLoading = services.serverAlerts.notifications.isEmpty
        defer { isLoading = false }
        try? await services.serverAlerts.load()
    }

    private func open(_ row: AlertRowData) {
        if serverBacked {
            if !row.read {
                Task { try? await services.serverAlerts.markRead(id: row.id) }
            }
        } else {
            services.alerts.markRead(row.id)
        }
        if let route = row.route, !route.isEmpty, route != "alerts" {
            services.push.open(route: route)
        }
    }

    private func markAllRead() {
        if serverBacked {
            Task { try? await services.serverAlerts.markAllRead() }
        } else {
            services.alerts.markAllRead()
        }
    }
}

/// One row, whichever store it came from.
struct AlertRowData: Identifiable {
    let id: String
    let category: String
    let title: String
    let body: String
    let dateText: String
    let read: Bool
    let route: String?

    init(notification: ServerNotification) {
        id = notification.id
        category = notification.category
        title = notification.title
        body = notification.body
        dateText = Self.relative(iso: notification.createdAt)
        read = notification.readAt != nil
        route = notification.route
    }

    init(item: AlertItem) {
        id = item.id
        category = item.category
        title = item.title
        body = item.body
        dateText = item.receivedAt.formatted(.relative(presentation: .named))
        read = item.read
        route = item.route
    }

    private static func relative(iso: String?) -> String {
        guard let iso else { return "" }
        // The API emits fractional-second timestamps; accept plain ones too.
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        guard let date = (try? Date(iso, strategy: fractional)) ?? (try? Date(iso, strategy: .iso8601)) else {
            return ""
        }
        return date.formatted(.relative(presentation: .named))
    }
}

private struct AlertRow: View {
    let row: AlertRowData
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Space.m) {
                IconTile(systemName: icon)

                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    if !row.body.isEmpty {
                        Text(row.body)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if !row.dateText.isEmpty {
                        Text(row.dateText)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.placeholder)
                    }
                }

                Spacer(minLength: 0)

                if !row.read {
                    Circle()
                        .fill(Color.calibre.primary)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)
                }
            }
            .padding(Space.l)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var icon: String {
        switch row.category {
        case "order_updates", "tracking_updates": "shippingbox"
        case "offer_updates": "arrow.left.arrow.right"
        case "watchlist_alerts": "heart"
        case "message_updates": "bubble.left.and.bubble.right"
        default: "bell"
        }
    }
}
