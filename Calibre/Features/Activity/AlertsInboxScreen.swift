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
                                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
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
                            AlertRow(
                                row: row,
                                onTap: { open(row) },
                                onMarkRead: row.read ? nil : { markRead(row) }
                            )
                        }
                    }
                    .padding(Space.margin)
                }
            }
        }
        .calibrePageBackground()
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
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    /// Refetches every time the inbox is opened, not only when it is empty.
    /// A row now exists for events this device never got a push for — muted
    /// categories still write the record (contracts §12.4), and so does every
    /// event that arrived while another device held the session — so the
    /// cached list is stale by default rather than by exception. The shimmer
    /// is still reserved for a genuinely empty first load; a refresh over
    /// rows already on screen replaces them in place.
    private func reload() async {
        guard serverBacked else { return }
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
        // Only a route this build can actually resolve navigates. A push tap
        // falls back to the inbox when the route means nothing here, but from
        // inside the inbox that fallback would push a second copy of this very
        // screen, so an unknown route stays put instead.
        if let route = row.route, let destination = PushCoordinator.route(from: route), destination != .alerts {
            services.push.open(route: route)
        }
    }

    /// Item 1.12: reading a row and going to the thing it is about are two
    /// different intentions, and the inbox has to offer both. Tapping the row
    /// does both (navigate and mark read); this control does only the second,
    /// so a member can clear a notification they have already dealt with
    /// without being thrown into an order they did not ask to open.
    private func markRead(_ row: AlertRowData) {
        Haptics.shared.play(.press)
        if serverBacked {
            Task { try? await services.serverAlerts.markRead(id: row.id) }
        } else {
            services.alerts.markRead(row.id)
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
    /// Nil once the row is read — there is nothing left for it to do.
    let onMarkRead: (() -> Void)?

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

                // The dot's own footprint, reserved inside the row button so
                // the text does not run under the control that sits on top of
                // it. The control itself is the overlay below.
                if !row.read {
                    Color.clear.frame(width: 20, height: 20)
                }
            }
            .padding(Space.l)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        // Unread is drawn as an 8pt dot and nothing else, so without this a row
        // reads identically whether it has been opened or not.
        .accessibilityValue(row.read ? "" : "Unread")
        .accessibilityHint(row.read ? "" : "Opens it and marks it read")
        // VoiceOver reaches the mark-read control through the row's actions
        // rather than by hunting for a small target inside a full-width row.
        .accessibilityAction(named: "Mark as read") {
            onMarkRead?()
        }
        // Item 1.12: a separate control that marks the row read *without*
        // navigating. It has to be a sibling of the row button, not a child of
        // its label — a Button inside another Button's label is drawn but
        // never tapped, so nesting it would have produced a control that looks
        // right and does nothing.
        .overlay(alignment: .topTrailing) {
            unreadControl
        }
    }

    @ViewBuilder
    private var unreadControl: some View {
        if let onMarkRead {
            Button(action: onMarkRead) {
                Circle()
                    .fill(Color.calibre.primary)
                    .frame(width: 8, height: 8)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Mark as read")
            // The row above already offers this as a named action, and a 44pt
            // element floating over the row would otherwise be a second thing
            // for VoiceOver to find in the same place.
            .accessibilityHidden(true)
            // The 8pt dot sits at the centre of a 44pt target, so the target
            // is offset to put the dot back where it was drawn (row padding
            // 16 + 6) rather than where a 44pt box would centre it. Nothing
            // overhangs the card: 4pt down, flush right.
            .padding(.top, 4)
        }
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
