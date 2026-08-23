import CalibreKit
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// The Sendable fields lifted out of a raw APNs payload.
struct DecodedPush: Sendable {
    /// The notification's request identifier — stable across the foreground
    /// present and a later tap, so the inbox can dedupe.
    let id: String
    let title: String
    let body: String
    let route: String?
    let category: String
    /// The server-side `Notification` row this push was sent for. Absent on a
    /// push queued by a build that predates the field, which is the only
    /// reason a tap would go unreported.
    let notificationID: String?
}

/// One received notification, kept in the local Alerts inbox.
struct AlertItem: Identifiable, Hashable, Codable {
    let id: String
    let category: String
    let title: String
    let body: String
    let route: String?
    let receivedAt: Date
    var read: Bool
}

/// The on-device Alerts inbox — the last 100 pushes the app has seen. Persists
/// across launches so the Activity › Alerts tab has history even after a push
/// is cleared from Notification Center.
@MainActor
@Observable
final class AlertsInbox {
    private(set) var items: [AlertItem] = []

    @ObservationIgnored private let key = "calibre.alerts.inbox"
    @ObservationIgnored private let cap = 100

    var unreadCount: Int { items.lazy.filter { !$0.read }.count }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AlertItem].self, from: data) {
            items = decoded
        }
    }

    func record(id: String = UUID().uuidString, category: String, title: String, body: String, route: String?, at: Date) {
        // Dedupe: the same push arrives twice (foreground present, then tap).
        guard !items.contains(where: { $0.id == id }) else { return }
        items.insert(
            AlertItem(id: id, category: category, title: title, body: body, route: route, receivedAt: at, read: false),
            at: 0
        )
        if items.count > cap { items.removeLast(items.count - cap) }
        persist()
    }

    func markAllRead() {
        items = items.map { var copy = $0; copy.read = true; return copy }
        persist()
    }

    func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].read = true
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Owns push permission, APNs registration, and payload → route decoding.
/// Everything degrades gracefully without a provisioned APNs entitlement:
/// the pre-permission prompt and settings still work; only real delivery needs
/// a paid Apple Developer account.
@MainActor
@Observable
final class PushCoordinator: NSObject {
    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored weak var router: AppRouter?
    @ObservationIgnored weak var alerts: AlertsInbox?
    @ObservationIgnored weak var serverAlerts: ServerAlertsStore?

    /// Whether we've already asked (so we prompt at most once ourselves).
    var hasRequestedPermission: Bool {
        get { UserDefaults.standard.bool(forKey: "calibre.push.requested") }
        set { UserDefaults.standard.set(newValue, forKey: "calibre.push.requested") }
    }

    /// A cold-start route parked until the tab shell is ready to receive it.
    private(set) var pendingRoute: String?

    init(account: AccountStore) {
        self.account = account
        super.init()
    }

    func attach(router: AppRouter, alerts: AlertsInbox, serverAlerts: ServerAlertsStore) {
        self.router = router
        self.alerts = alerts
        self.serverAlerts = serverAlerts
        UNUserNotificationCenter.current().delegate = self
    }

    /// Whether the system-level authorization is already granted.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Requests permission and, on grant, registers for remote notifications.
    @discardableResult
    func requestAuthorization() async -> Bool {
        hasRequestedPermission = true
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            return false
        }
    }

    /// Re-registers with the backend on launch/sign-in if we already hold a
    /// token (APNs tokens rotate).
    func refreshRegistration() {
        if UserDefaults.standard.bool(forKey: "calibre.push.requested") {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task {
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            try? await account.registerDevice(token: token, environment: environment)
        }
    }

    /// Called on sign-out to stop delivery to this device's token.
    func unregisterOnSignOut() {
        guard let token = deviceToken else { return }
        Task { try? await account.unregisterDevice(token: token) }
    }

    /// Records a decoded push (deduped by id) and, on a tap, reports the open
    /// and navigates.
    func handle(_ push: DecodedPush, receivedAt: Date, foreground: Bool) {
        alerts?.record(id: push.id, category: push.category, title: push.title, body: push.body, route: push.route, at: receivedAt)
        // A foreground push surfaces as a banner (via the delegate) and is not
        // an open — seeing a banner is not reading the message.
        guard !foreground else { return }
        reportOpen(push)
        // A push with no route, or a route this build has never heard of,
        // still has to land somewhere: the inbox, where the notification
        // itself is. Swallowing the tap is the one outcome that reads as the
        // app being broken.
        open(route: push.route ?? Self.inboxRoute)
    }

    /// The tap, told to both halves of the record: our own row (so the
    /// push-first email delay knows the phone already delivered the news) and
    /// PostHog (so an open joins the `push_delivered` the backend emitted).
    ///
    /// `notification_id` is the join key on both sides, so a push without one
    /// reports nothing rather than inventing an id.
    private func reportOpen(_ push: DecodedPush) {
        guard let notificationID = push.notificationID else { return }
        Analytics.pushOpened(notificationID: notificationID, category: push.category, route: push.route)
        Task { [weak serverAlerts] in
            // A failure here is not worth surfacing: the endpoint is
            // idempotent, the next tap re-reports, and nothing the user can
            // see depends on it.
            try? await serverAlerts?.markOpened(id: notificationID)
        }
    }

    /// Extracts the Sendable fields we need from a raw APNs payload. Runs in
    /// the nonisolated delegate so nothing non-Sendable crosses to the actor.
    ///
    /// `category` is read verbatim and never derived from the route
    /// (contracts §12.3). The route cannot carry it: an `order/{id}` push is
    /// an order update or a tracking update depending on what happened, and
    /// guessing from the route is why every `tracking_updates` push used to
    /// file itself under Orders.
    nonisolated static func decode(userInfo: [AnyHashable: Any], id: String) -> DecodedPush {
        let route = userInfo["route"] as? String
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let alert = aps?["alert"] as? [AnyHashable: Any]
        let title = (alert?["title"] as? String) ?? "Calibre"
        let body = (alert?["body"] as? String) ?? ""
        let category = (userInfo["category"] as? String) ?? unknownCategory
        return DecodedPush(
            id: id,
            title: title,
            body: body,
            route: route,
            category: category,
            notificationID: userInfo["notification_id"] as? String
        )
    }

    /// Filed under nothing in particular — a push that arrived without a
    /// category, which now only happens to one queued before the server
    /// started sending it. Deliberately not one of the real category names,
    /// so a gap never masquerades as a classification.
    nonisolated static let unknownCategory = "general"

    /// Where a tap goes when its route means nothing here.
    private static let inboxRoute = "alerts"

    /// Navigates to a route string like "order/123", "offer/45", "listing/9",
    /// "support", "alerts". Parked until the shell is ready if the router isn't
    /// attached yet (cold start).
    func open(route: String) {
        guard let router else { pendingRoute = route; return }
        // An unparseable route opens the inbox rather than doing nothing: the
        // notification is there either way, and a shipped build has no way of
        // knowing what the server started sending after it.
        router.open(Self.route(from: route) ?? .alerts)
    }

    /// Drains a cold-start route once the shell has attached the router.
    func drainPendingRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        open(route: route)
    }

    /// Parses a push/deep-link route string into an app `Route`.
    static func route(from string: String) -> Route? {
        let parts = string.split(separator: "/").map(String.init)
        guard let head = parts.first else { return nil }
        let id = parts.count > 1 ? parts[1] : nil
        switch head {
        case "order": return id.map { .order($0) }
        case "offer": return id.map { .offer($0) }
        case "listing": return id.map { .listing($0) }
        case "seller": return id.map { .seller($0) }
        case "brand": return id.map { .brand($0) }
        case "journal": return id.map { .journalArticle($0) }
        case "support": return .supportChat
        case "alerts": return .alerts
        default: return nil
        }
    }
}

extension PushCoordinator: UNUserNotificationCenterDelegate {
    /// Foreground pushes still show a banner so the user notices, and land in
    /// the inbox.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let decoded = PushCoordinator.decode(userInfo: notification.request.content.userInfo, id: notification.request.identifier)
        Task { @MainActor in
            handle(decoded, receivedAt: .now, foreground: true)
        }
        completionHandler([.banner, .list, .sound])
    }

    /// A tap on a notification navigates.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let decoded = PushCoordinator.decode(userInfo: response.notification.request.content.userInfo, id: response.notification.request.identifier)
        Task { @MainActor in
            handle(decoded, receivedAt: .now, foreground: false)
        }
        completionHandler()
    }
}

/// Bridges UIKit's app-delegate APNs callbacks to the SwiftUI world. The active
/// `PushCoordinator` is handed in by the app root.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    static weak var coordinator: PushCoordinator?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in Self.coordinator?.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected on Simulator and unprovisioned builds — no-op.
    }
}
