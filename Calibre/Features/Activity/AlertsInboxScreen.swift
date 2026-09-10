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
    @Environment(\.routePush) private var routePush
    @Environment(AppRouter.self) private var router

    @State private var isLoading = false
    @State private var confirmingClearAll = false

    private var serverBacked: Bool { session.isAuthenticated }

    private var rows: [AlertRowData] {
        if serverBacked {
            return services.serverAlerts.notifications.map(AlertRowData.init(notification:))
        }
        return services.alerts.items.map(AlertRowData.init(item:))
    }

    /// What is left in the inbox. Not what is unread — a member who has read
    /// everything and cleared nothing still has an inbox with things in it.
    private var remainingCount: Int {
        serverBacked ? services.serverAlerts.remainingCount : services.alerts.remainingCount
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
                                onClear: { clear(row) }
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
        // Clear all sits on top, above the rows it sweeps.
        .toolbar {
            if remainingCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear all") { confirmingClearAll = true }
                        .font(CalibreType.label)
                        .foregroundStyle(Color.calibre.primary)
                }
            }
        }
        // Clearing is permanent and there is no history to go back to, so the
        // one that empties the whole inbox asks first. A single row does not:
        // it is one tap to undo by being told again, and a confirmation on
        // every row would make the ordinary gesture unusable.
        .confirmationDialog(
            "Clear all notifications?",
            isPresented: $confirmingClearAll,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) { clearAll() }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("They will not come back. Anything you still need is on the order, offer or listing itself.")
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

    /// A row click does both things: it goes to the thing the notification is
    /// about, and it clears the notification. Nothing is left behind to tidy
    /// up afterwards, which is the whole of the ruling.
    private func open(_ row: AlertRowData) {
        clear(row, haptic: false)
        // Only a route this build can actually resolve navigates. A push tap
        // falls back to the inbox when the route means nothing here, but from
        // inside the inbox that fallback would push a second copy of this very
        // screen, so an unknown route stays put instead.
        // Pushed, not opened. `PushCoordinator.open` is the path a tap on a
        // system notification takes, and it jumps to the route's canonical tab
        // because a tap from outside the app has no history to keep. A tap
        // inside the inbox does: the reader walked here, and the record they
        // asked for belongs above the list they asked for it from.
        if row.opensSellerEditor, let listingID = row.listingID {
            router.openSellerListing(id: listingID)
        } else if let route = row.route, let destination = PushCoordinator.route(from: route), destination != .alerts {
            routePush(destination)
        }
    }

    /// Clearing a row and going to the thing it is about are two different
    /// intentions, and the inbox has to offer both. Tapping the row does both;
    /// this control does only the first, so a member can clear a notification
    /// they have already dealt with without being thrown into an order they
    /// did not ask to open.
    private func clear(_ row: AlertRowData, haptic: Bool = true) {
        if haptic { Haptics.shared.play(.press) }
        if serverBacked {
            Task { try? await services.serverAlerts.clear(id: row.id) }
        } else {
            services.alerts.clear(row.id)
        }
    }

    private func clearAll() {
        Haptics.shared.play(.press)
        if serverBacked {
            Task { try? await services.serverAlerts.clearAll() }
        } else {
            services.alerts.clearAll()
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
    let route: String?
    let kind: String?
    let listingID: String?
    let listingStatus: String?

    var opensSellerEditor: Bool {
        Self.isSellerModeration(kind: kind, status: listingStatus)
    }

    private static func isSellerModeration(kind: String?, status: String?) -> Bool {
        switch kind?.lowercased() {
        case "listing_needs_more_info", "listing_needs_changes", "listing_rejected", "listing_taken_down":
            return true
        default:
            return status == "draft" || status == "rejected" || status == "archived"
        }
    }

    init(notification: ServerNotification) {
        id = notification.id
        category = notification.category
        title = notification.title
        body = notification.body
        dateText = Self.relative(iso: notification.createdAt)
        route = notification.route
        kind = notification.payload?.kind
        listingID = notification.payload?.listingId ?? Self.listingID(from: notification.route)
        listingStatus = notification.payload?.listingStatus
    }

    init(item: AlertItem) {
        id = item.id
        category = item.category
        title = item.title
        body = item.body
        dateText = item.receivedAt.formatted(.relative(presentation: .named))
        route = item.route
        kind = item.kind
        listingID = item.listingID ?? item.route.flatMap(Self.listingID(from:))
        listingStatus = item.listingStatus
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

    private static func listingID(from route: String) -> String? {
        let parts = route.split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.first == "listing", parts.count > 1 else { return nil }
        return parts[1]
    }
}

private struct AlertRow: View {
    let row: AlertRowData
    let onTap: () -> Void
    let onClear: () -> Void

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

                // The clear control's own footprint, reserved inside the row
                // button so the text does not run under the control that sits
                // on top of it. The control itself is the overlay below.
                Color.clear.frame(width: 20, height: 20)
            }
            .padding(Space.l)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens it and clears it")
        // VoiceOver reaches the clear control through the row's actions rather
        // than by hunting for a small target inside a full-width row.
        .accessibilityAction(named: "Clear") { onClear() }
        // A separate control that clears the row *without* navigating. It has
        // to be a sibling of the row button, not a child of its label — a
        // Button inside another Button's label is drawn but never tapped, so
        // nesting it would have produced a control that looks right and does
        // nothing.
        .overlay(alignment: .topTrailing) {
            clearControl
        }
    }

    private var clearControl: some View {
        Button(action: onClear) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.calibre.mutedForeground)
                .frame(width: Space.touchTarget, height: Space.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Clear")
        // The row above already offers this as a named action, and a 44pt
        // element floating over the row would otherwise be a second thing for
        // VoiceOver to find in the same place.
        .accessibilityHidden(true)
        // The glyph sits at the centre of a 44pt target, so the target is
        // offset to put the glyph back where it was drawn rather than where a
        // 44pt box would centre it. Nothing overhangs the card.
        .padding(.top, 4)
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
