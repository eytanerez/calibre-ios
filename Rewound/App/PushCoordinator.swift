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
    let kind: String?
    let listingID: String?
    let listingStatus: String?
}

/// One received notification, kept in the local Alerts inbox.
struct AlertItem: Identifiable, Hashable, Codable {
    let id: String
    let category: String
    let title: String
    let body: String
    let route: String?
    let receivedAt: Date
    /// The server `Notification` row this push was sent for, where it carried
    /// one. It is what a `notifications_cleared` push names, so it is what a
    /// clear made on another device can be matched against. Optional because a
    /// push queued before the field existed has none.
    var notificationID: String?
    /// Moderation metadata. Optional so saved rows from older builds continue
    /// to decode, and so unrelated notifications carry no empty fields.
    var kind: String?
    var listingID: String?
    var listingStatus: String?
    /// Still written, no longer read by anything: the inbox is cleared rather
    /// than ticked off. The key stays on the wire because these rows are
    /// persisted, and a `JSONDecoder` handed an archive with a key it has no
    /// property for is fine, while one missing a key it needs is not — the
    /// whole saved inbox would fail to decode and quietly come back empty.
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

    /// What is left in the inbox — the same thing the signed-in badge counts.
    /// A guest's inbox is emptied by clearing, not by reading, so this is the
    /// row count and not the unread count.
    var remainingCount: Int { items.count }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([AlertItem].self, from: data) {
            items = decoded
        }
    }

    func record(
        id: String = UUID().uuidString,
        category: String,
        title: String,
        body: String,
        route: String?,
        notificationID: String? = nil,
        kind: String? = nil,
        listingID: String? = nil,
        listingStatus: String? = nil,
        at: Date
    ) {
        // Dedupe: the same push arrives twice (foreground present, then tap).
        guard !items.contains(where: { $0.id == id }) else { return }
        items.insert(
            AlertItem(
                id: id,
                category: category,
                title: title,
                body: body,
                route: route,
                receivedAt: at,
                notificationID: notificationID,
                kind: kind,
                listingID: listingID,
                listingStatus: listingStatus,
                read: false
            ),
            at: 0
        )
        if items.count > cap { items.removeLast(items.count - cap) }
        persist()
    }

    /// Empties the local inbox. Permanent and invisible, exactly as the
    /// signed-in one is — there is no history view to fall back on.
    func clearAll() {
        items = []
        persist()
    }

    func clear(_ id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// Drops the rows a `notifications_cleared` push named.
    ///
    /// The ids on the wire are server `Notification` ids, and a row here is
    /// keyed by the APNs request identifier — so the match is on what the
    /// original push carried, which is the same join key the tap report uses.
    func clearServerRows(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let before = items.count
        items.removeAll { $0.notificationID.map(ids.contains) ?? false }
        guard items.count != before else { return }
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
    @ObservationIgnored private let auth: AuthSession
    @ObservationIgnored private let registration: PushDeviceRegistrar
    @ObservationIgnored private var signingOutUserID: String?
    private static let tokenCacheKey = "calibre.push.latestDeviceToken"
    private struct CachedToken: Codable { let token: String; let environment: String }
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
    private var pendingKind: String?
    private var pendingListingID: String?
    private var pendingListingStatus: String?

    init(account: AccountStore, auth: AuthSession) {
        self.account = account
        self.auth = auth
        self.registration = PushDeviceRegistrar { target in
            guard auth.isAuthenticated, auth.user?.id == target.userID else { throw CancellationError() }
            do {
                try await account.registerDevice(token: target.token, environment: target.environment)
            } catch {
                Observability.log(.warning, "push device registration failed")
                throw error
            }
        }
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.tokenCacheKey),
           let cached = try? JSONDecoder().decode(CachedToken.self, from: data),
           cached.environment == Self.apsEnvironment() {
            deviceToken = cached.token
            registration.setToken(cached.token, environment: cached.environment)
        }
    }

    /// Identity changes include restored sessions and A → B without a guest
    /// interval. Notification permission belongs to the device, not its user.
    func accountDidChange(to userID: String?) {
        registration.setUser(nil)
        if signingOutUserID != userID { signingOutUserID = nil }
        guard userID != nil else {
            Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
            return
        }
        Task { await requestAuthorizationIfNeeded() }
    }

    private func activateRegistration() {
        guard auth.isAuthenticated, let userID = auth.user?.id,
              signingOutUserID != userID else { return }
        registration.setUser(userID)
        registration.refresh()
        // Keep asking APNs for the authoritative current token. The cached
        // token lets an account switch re-associate without waiting on a
        // callback for a token that has not changed.
        UIApplication.shared.registerForRemoteNotifications()
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
                activateRegistration()
            }
            return granted
        } catch {
            return false
        }
    }

    /// Asks for permission the first time a signed-in member reaches the app,
    /// and only then.
    ///
    /// `requestAuthorization()` existed from the start but its only caller was
    /// the Profile toggle, so a member who never opened that screen was never
    /// asked — the app held no token, and every push the backend sent went
    /// nowhere. Nothing surfaced that: the send path reports success against a
    /// device list that is simply empty.
    ///
    /// Gated on `.notDetermined` so a member who said no is not asked again on
    /// every launch (iOS would refuse anyway, but the intent matters), and on
    /// being signed in so the prompt lands with some context rather than cold
    /// on first open.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        switch await authorizationStatus() {
        case .notDetermined:
            return await requestAuthorization()
        case .authorized, .provisional, .ephemeral:
            // Permission survives reinstall/restore independently of our
            // defaults. Always restore the backend registration on sign-in.
            activateRegistration()
            return true
        default:
            return false
        }
    }

    /// Re-registers with the backend on launch/sign-in if we already hold a
    /// token (APNs tokens rotate).
    func refreshRegistration() {
        Task {
            switch await authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                activateRegistration()
            default:
                break
            }
        }
    }

    /// Which APNs host will accept this device's token.
    ///
    /// This used to be `#if DEBUG ? "sandbox" : "production"`, which is the
    /// build configuration — but APNs decides from the `aps-environment`
    /// entitlement, and the two disagree for any Release build installed
    /// straight onto a device: it reported "production" while holding a
    /// sandbox token, and every push to it came back 400 BadDeviceToken.
    ///
    /// Verified 2026-09-07 on a Release-to-device install: production was
    /// rejected, sandbox delivered the same payload to the same token.
    ///
    /// The failure was silent, which is the worst part — the backend records a
    /// send, APNs answers cleanly, and nobody is notified. Reading the profile
    /// the binary was actually signed with is the only source that agrees with
    /// whoever is going to reject the token.
    ///
    /// TestFlight and App Store builds have no embedded profile and are
    /// production, which is why the old code happened to be right for them and
    /// this returns "production" when the profile is absent or unreadable.
    private static func apsEnvironment() -> String {
        guard
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .isoLatin1),
            let range = raw.range(of: "<key>aps-environment</key>")
        else { return "production" }

        // The value is the first <string> after the key; anything else means a
        // profile shape we do not recognise, and production is the safe read.
        let tail = raw[range.upperBound...].prefix(200)
        return tail.contains("<string>development</string>") ? "sandbox" : "production"
    }

    func didRegister(deviceToken data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        let environment = Self.apsEnvironment()
        if let data = try? JSONEncoder().encode(CachedToken(token: token, environment: environment)) {
            UserDefaults.standard.set(data, forKey: Self.tokenCacheKey)
        }
        registration.setToken(token, environment: environment)
    }

    /// Finish an in-flight POST before deleting, so a late callback cannot
    /// resurrect the old user's association after their sign-out.
    func unregisterOnSignOut() async {
        guard let userID = auth.user?.id else { return }
        signingOutUserID = userID
        await registration.unregister(
            userID: userID,
            fallbackToken: deviceToken,
            environment: Self.apsEnvironment()
        ) { [auth, account] target in
            guard auth.user?.id == target.userID else { return }
            try await account.unregisterDevice(token: target.token)
        }
    }

    /// Records a decoded push (deduped by id) and, on a tap, reports the open
    /// and navigates.
    func handle(_ push: DecodedPush, receivedAt: Date, foreground: Bool) {
        alerts?.record(
            id: push.id,
            category: push.category,
            title: push.title,
            body: push.body,
            route: push.route,
            notificationID: push.notificationID,
            kind: push.kind,
            listingID: push.listingID,
            listingStatus: push.listingStatus,
            at: receivedAt
        )
        // APNs normally applies its `aps.badge` value. Keep the local inbox
        // path correct too for injected/debug pushes and older server payloads.
        updateApplicationBadge()
        // A foreground push surfaces as a banner (via the delegate) and is not
        // an open — seeing a banner is not reading the message.
        guard !foreground else { return }
        reportOpen(push)
        // A push with no route, or a route this build has never heard of,
        // still has to land somewhere: the inbox, where the notification
        // itself is. Swallowing the tap is the one outcome that reads as the
        // app being broken.
        open(
            route: push.route ?? Self.inboxRoute,
            kind: push.kind,
            listingID: push.listingID,
            listingStatus: push.listingStatus
        )
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

    // MARK: - Notifications cleared somewhere else

    /// What one device's clear says to every other device the member holds.
    ///
    /// Every value on the wire is a string on both platforms. FCM's data map
    /// is string-to-string and the two clients must read one payload, so this
    /// does not expect numbers even where iOS could have sent them. The one
    /// exception is `aps.badge`, which is Apple's own field and Apple's own
    /// type; it says the same thing as `remainingCount` and either may be used.
    struct ClearedSync: Sendable {
        /// The rows that went. Empty on a clear-all — see `clearedAll`.
        let ids: Set<String>
        /// Everything went. The list is deliberately NOT sent in this case: a
        /// background APNs payload is capped at 4KB, and an inbox of a few
        /// hundred ids does not fit, so it would be truncated or dropped and
        /// leave a card on a phone with nothing coming to remove it.
        let clearedAll: Bool
        /// What the bell and the app icon should read now. The server's count,
        /// not one derived from what this device happened to be holding.
        ///
        /// Optional because absent has to mean "the server did not say".
        /// Defaulting it to zero reads a payload that mentions no count as a
        /// phone with an empty inbox, and a clear of two rows out of forty
        /// would then wipe the badge and empty the bell on every *other*
        /// device the member holds. Today's backend sends both fields, so that
        /// is a branch nothing takes — which is exactly the shape that becomes
        /// the only branch the day the payload changes, silently.
        let remaining: Int?

        /// The type this payload announces itself as. Read this key first.
        static let type = "notifications_cleared"

        /// Nil for anything that is not a clear announcement.
        init?(userInfo: [AnyHashable: Any]) {
            guard userInfo["type"] as? String == Self.type else { return nil }
            let raw = (userInfo["notification_ids"] as? String) ?? ""
            ids = Set(
                raw.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
            clearedAll = (userInfo["cleared_all"] as? String) == "true"
            // No `?? 0` on the end of this chain. It was there, and it made
            // the property above a lie: `remaining` could not be nil, so the
            // "payload named no count" branch in `apply(_:)` was unreachable
            // and a clear that mentioned no count set the badge to zero —
            // the exact wipe the doc comment describes. The two fields are
            // alternatives to each other, not to zero.
            let count = (userInfo["remaining_count"] as? String).flatMap(Int.init)
            let badge = (userInfo["aps"] as? [AnyHashable: Any])
                .flatMap { $0["badge"] as? Int }
            remaining = count ?? badge
        }
    }

    /// Takes the cards off this phone that were cleared on another one.
    ///
    /// Three places have to agree afterwards: the notification centre, the
    /// inbox screen, and the number on the app icon.
    func applyCleared(_ sync: ClearedSync) async {
        await Self.removeDelivered(sync)
        alerts?.clearServerRows(ids: sync.ids)
        if sync.clearedAll { alerts?.clearAll() }
        serverAlerts?.applyCleared(
            ids: Array(sync.ids),
            clearedAll: sync.clearedAll,
            remaining: sync.remaining
        )
        // A payload that named no count is left to say nothing about the
        // badge. Everything went is the one case this can answer on its own.
        if let remaining = sync.remaining {
            try? await UNUserNotificationCenter.current().setBadgeCount(remaining)
        } else if sync.clearedAll {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    /// Synchronises the native app-icon badge with the durable inbox count.
    /// The server's APNs payload supplies this while the app is backgrounded;
    /// this method covers foreground loads, local guest history, and builds
    /// that predate the payload field.
    func updateApplicationBadge() {
        let count = auth.isAuthenticated
            ? (serverAlerts?.remainingCount ?? 0)
            : (alerts?.remainingCount ?? 0)
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(max(count, 0)) }
    }

    /// Pulls the delivered notifications out of the tray.
    ///
    /// `removeDeliveredNotifications(withIdentifiers:)` takes APNs *request*
    /// identifiers, which iOS minted when the alert arrived — the server has
    /// never seen them and cannot send them. So the delivered notifications
    /// are read back and matched on the `notification_id` their own payload
    /// carried, which is the id the server does know.
    private static func removeDelivered(_ sync: ClearedSync) async {
        let centre = UNUserNotificationCenter.current()
        guard !sync.clearedAll else {
            // Everything of Calibre's, because the payload cannot carry the
            // list. This app's notification centre holds only Calibre's own.
            centre.removeAllDeliveredNotifications()
            return
        }
        let delivered = await centre.deliveredNotifications()
        let requests = delivered.compactMap { notification -> String? in
            let carried = notification.request.content.userInfo["notification_id"] as? String
            guard let carried, sync.ids.contains(carried) else { return nil }
            return notification.request.identifier
        }
        guard !requests.isEmpty else { return }
        centre.removeDeliveredNotifications(withIdentifiers: requests)
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
            notificationID: userInfo["notification_id"] as? String,
            kind: userInfo["kind"] as? String,
            listingID: userInfo["listing_id"] as? String,
            listingStatus: userInfo["listing_status"] as? String
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
    func open(
        route: String,
        kind: String? = nil,
        listingID: String? = nil,
        listingStatus: String? = nil
    ) {
        guard let router else {
            pendingRoute = route
            pendingKind = kind
            pendingListingID = listingID
            pendingListingStatus = listingStatus
            return
        }
        if Self.isSellerModeration(kind: kind, status: listingStatus),
           let listingID = listingID ?? Self.listingID(from: route) {
            router.openSellerListing(id: listingID)
            return
        }
        // An unparseable route opens the inbox rather than doing nothing: the
        // notification is there either way, and a shipped build has no way of
        // knowing what the server started sending after it.
        router.open(Self.route(from: route) ?? .alerts)
    }

    /// Drains a cold-start route once the shell has attached the router.
    func drainPendingRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        let kind = pendingKind
        let listingID = pendingListingID
        let listingStatus = pendingListingStatus
        pendingKind = nil
        pendingListingID = nil
        pendingListingStatus = nil
        open(route: route, kind: kind, listingID: listingID, listingStatus: listingStatus)
    }

    /// Approval keeps using the public buyer route because the listing is
    /// live. Every decision that leaves it unavailable opens the owner's copy
    /// in Sell, where the reason and editable fields are present.
    static func isSellerModeration(kind: String?, status: String?) -> Bool {
        switch kind?.lowercased() {
        case "listing_needs_more_info", "listing_needs_changes", "listing_rejected", "listing_taken_down":
            return true
        default:
            return status == "draft" || status == "rejected" || status == "archived"
        }
    }

    private static func listingID(from route: String) -> String? {
        let parts = route.split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.first == "listing", parts.count > 1 else { return nil }
        return parts[1]
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
        // Both spellings are live. The customer reply push now sends
        // `support/<conversation id>`; it used to send the bare word, and a
        // build that only knew one of the two either drops the id or drops
        // the tap.
        case "support": return id.map { .supportThread($0) } ?? .supportChat
        case "thread": return id.map { .messageThread($0) }
        case "messages": return .messages
        case "account": return id == "settings" ? .accountSettings : nil
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
        let userInfo = notification.request.content.userInfo
        // A clear announcement is not something to show. It should never reach
        // here — it carries no alert — but a banner saying a notification was
        // removed is the one outcome worth being sure of.
        if let sync = PushCoordinator.ClearedSync(userInfo: userInfo) {
            Task { @MainActor in await applyCleared(sync) }
            completionHandler([])
            return
        }
        let decoded = PushCoordinator.decode(userInfo: userInfo, id: notification.request.identifier)
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
    static weak var coordinator: PushCoordinator? {
        didSet {
            guard let coordinator, let token = pendingDeviceToken else { return }
            pendingDeviceToken = nil
            coordinator.didRegister(deviceToken: token)
        }
    }
    /// UIKit may deliver a token before the SwiftUI root has attached its
    /// coordinator. Retain that callback until the live root is ready.
    private static var pendingDeviceToken: Data?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            if let coordinator = Self.coordinator {
                coordinator.didRegister(deviceToken: deviceToken)
            } else {
                Self.pendingDeviceToken = deviceToken
            }
        }
    }

    /// The silent half of push: a payload with `content-available` and no
    /// alert, which is how one device tells the others that the member cleared
    /// something. It arrives here and nowhere else — it shows nothing, so
    /// there is no banner to present and no tap to receive.
    ///
    /// Needs the `remote-notification` background mode, declared in
    /// `project.yml`; without it iOS delivers this only while the app is
    /// already in the foreground, which is the one case it is least needed.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let sync = PushCoordinator.ClearedSync(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await Self.coordinator?.applyCleared(sync)
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        #if !targetEnvironment(simulator)
        Observability.log(.warning, "APNs device registration failed")
        #endif
    }
}
