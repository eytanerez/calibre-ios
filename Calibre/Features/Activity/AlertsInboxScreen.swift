import CalibreDesign
import SwiftUI

/// The Alerts inbox — a history of the pushes the app has received. Rows deep
/// link to their subject; a tap marks the row read.
struct AlertsInboxScreen: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        Group {
            if services.alerts.items.isEmpty {
                EmptyState(
                    icon: "bell",
                    title: "Nothing yet",
                    message: "We'll nudge you the moment something needs you — a reply to an offer, an update on an order, a price drop on a watch you saved."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Space.s) {
                        ForEach(services.alerts.items) { item in
                            AlertRow(item: item) {
                                services.alerts.markRead(item.id)
                                if let route = item.route {
                                    services.push.open(route: route)
                                }
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
            if services.alerts.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { services.alerts.markAllRead() }
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
        }
    }
}

private struct AlertRow: View {
    let item: AlertItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Space.m) {
                IconTile(systemName: icon)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(item.receivedAt, format: .relative(presentation: .named))
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.placeholder)
                }

                Spacer(minLength: 0)

                if !item.read {
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
        switch item.category {
        case "order_updates", "tracking_updates": "shippingbox"
        case "offer_updates": "arrow.left.arrow.right"
        case "watchlist_alerts": "heart"
        case "message_updates": "bubble.left.and.bubble.right"
        default: "bell"
        }
    }
}
