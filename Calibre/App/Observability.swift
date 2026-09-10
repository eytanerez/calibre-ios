import Foundation
import Sentry
#if canImport(UIKit)
import UIKit
#endif

/// One place that turns crash reporting, log shipping and the analytics
/// identity on — started once from `CalibreApp.init()`, mirroring
/// `admin-ios/CalibreAdmin/App/Observability.swift` so one set of keys and one
/// mental model serves every Calibre client.
///
/// ## Where a person pastes the keys
///
/// Every value is read from `Info.plist`, and every plist key is filled from an
/// xcconfig variable that XcodeGen maps in `project.yml`:
///
/// | Service | xcconfig variable | Info.plist key |
/// |---|---|---|
/// | PostHog | `CALIBRE_POSTHOG_KEY` / `CALIBRE_POSTHOG_HOST` | `CalibrePostHogKey` / `CalibrePostHogHost` |
/// | Sentry | `CALIBRE_SENTRY_DSN` | `CalibreSentryDSN` |
/// | Better Stack | `CALIBRE_BETTERSTACK_TOKEN` | `CalibreBetterStackToken` |
/// | Better Stack host | `CALIBRE_BETTERSTACK_HOST` | `CalibreBetterStackHost` |
///
/// The variables live in **`Calibre/Config/Release.xcconfig`** (the file every
/// TestFlight and archive build reads — this is the one to fill in) and
/// **`Calibre/Config/Debug.xcconfig`**. Both ship blank. A blank value is a
/// documented silent no-op: that SDK is never configured, makes no network
/// call, and cannot crash a build that shipped before the key existed. The
/// the services are independent — Sentry can be live while PostHog and
/// Better Stack stay dark, in any combination.
///
/// After editing `project.yml`, run `/opt/homebrew/bin/xcodegen generate`;
/// editing only an xcconfig needs no regeneration.
@MainActor
enum Observability {

    enum Level: String {
        case debug, info, warning, error
    }

    /// Stamped on every Sentry event and Better Stack line.
    ///
    /// Release is `"staging"` because every release build of this app —
    /// TestFlight included — talks to the calibre-server staging box (see
    /// `API_BASE_URL` in `Config/Release.xcconfig`). **That is the line below
    /// to change on the day a production backend exists**; nothing else here
    /// has an opinion about it.
    /// `nonisolated` because the log shipper stamps it on every line from
    /// whatever thread called `log`, and this type is `@MainActor`.
    #if DEBUG
    nonisolated static let environment = "development"
    #else
    nonisolated static let environment = "staging"
    #endif

    // Guarded only by `start()` being called exactly once, from the app's
    // `init()`, before anything else runs — the same shape as `isStarted` in
    // `Analytics`.
    private static var isStarted = false

    static func start() {
        guard !isStarted else { return }
        isStarted = true

        // PostHog already has a home in this app: `Analytics` owns the typed
        // event schema and configures the SDK behind it. Configuring it a
        // second time here would give one process two configurations of the
        // same shared singleton, so this hands off instead of duplicating.
        // `Analytics.start()` is itself idempotent.
        Analytics.start()

        startSentry()
        BetterStackShipper.shared.configure(
            token: infoValue("CalibreBetterStackToken"),
            host: infoValue("CalibreBetterStackHost")
        )

        log(.info, "app_launch")
    }

    /// Call when the signed-in identity changes — sign-in, session restore,
    /// sign-out — so Sentry, the log shipper and PostHog agree about who an
    /// event belongs to. `nil` clears it everywhere and is never passed to an
    /// `identify`: it becomes a reset.
    static func identify(userID: String?) {
        if let userID {
            let user = Sentry.User()
            user.userId = userID
            SentrySDK.setUser(user)
        } else {
            SentrySDK.setUser(nil)
        }
        BetterStackShipper.shared.setUserID(userID)
        // PostHog's identity is `Analytics`' business for the same reason its
        // configuration is: one owner per SDK. `sessionChanged` is idempotent
        // and handles the nil (sign-out) side as a reset.
        Analytics.sessionChanged(to: userID)
    }

    /// The app's one logging entry point. Call sites are deliberately few —
    /// app launch, sign-in success/failure, a session restore that failed —
    /// rather than routed through every layer. Ships to Better Stack when a
    /// token is configured; always echoes to the console in DEBUG so it is
    /// useful with zero keys set.
    nonisolated static func log(_ level: Level, _ message: String) {
        BetterStackShipper.shared.log(level: level, message: message)
        #if DEBUG
        print("[\(level.rawValue)] \(message)")
        #endif
    }

    // MARK: - Sentry

    private static func startSentry() {
        guard let dsn = infoValue("CalibreSentryDSN") else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.releaseName = releaseName()
            #if DEBUG
            // Debugger pauses and simulator load are not production hangs.
            options.tracesSampleRate = 0.0
            options.enableAppHangTracking = false
            #else
            // Sample loads while retaining native stack traces for UI hangs.
            // Better Stack receives operational logs; Sentry owns diagnosis.
            options.tracesSampleRate = 0.05
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 2.0
            #endif
        }
    }

    private static func releaseName() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.buycalibre.calibre"
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
        return "\(bundleID)@\(version)+\(build)"
    }

    // MARK: - Config

    /// Trims and treats an empty (unset) xcconfig value as absent — the
    /// difference between "no key yet" and "key is the empty string" does not
    /// matter to any of the services.
    private static func infoValue(_ key: String) -> String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // An xcconfig that failed to apply leaves the literal "$(CALIBRE_…)"
        // token in Info.plist; that is "no key", not a DSN. Same guard as
        // Analytics.infoValue.
        guard !raw.hasPrefix("$(") else { return nil }
        return raw.isEmpty ? nil : raw
    }
}

/// A minimal Better Stack log shipper — there is no official mobile SDK.
/// Events queue in memory and go out as one JSON array POSTed to
/// `https://in.logs.betterstack.com`, sent on a slow timer, once the queue
/// reaches its batch size, or when the app backgrounds. Sending is
/// fire-and-forget on its own `URLSession`: the calling thread never waits on
/// it, and a failed send (no network, bad token, Better Stack down) drops its
/// batch silently — a log line must never be a reason the app misbehaves.
///
/// All mutable state sits behind `lock`, so `log(level:message:)` is safe to
/// call from any thread.
final class BetterStackShipper: @unchecked Sendable {
    static let shared = BetterStackShipper()

    /// Where the batches go when no host is configured. Better Stack mints a
    /// dedicated ingesting host per source (`s<id>.<region>.betterstackdata.com`)
    /// and this shared host answers 401 to a token minted for one of those, so
    /// the host travels with the token (`CalibreBetterStackHost`). This stays
    /// only as the fallback for a token that predates per-source hosts.
    private static let legacyEndpoint = URL(string: "https://in.logs.betterstack.com")!
    private static let maxBatch = 20
    private static let flushIntervalNanoseconds: UInt64 = 10_000_000_000

    private static let appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    private static let buildNumber = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"

    // ISO8601DateFormatter is not `Sendable` (it is a class), but its reads are
    // safe to call concurrently once configured, and it is configured here,
    // before any thread touches it — `nonisolated(unsafe)` says that to the
    // compiler.
    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let lock = NSLock()
    private var token: String?
    private var endpoint: URL = BetterStackShipper.legacyEndpoint
    private var userID: String?
    private var buffer: [[String: Any]] = []
    private var flushTask: Task<Void, Never>?

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private init() {}

    /// A `nil` or empty token leaves the shipper permanently dark: `log`
    /// becomes a no-op and neither the flush loop nor the background observer
    /// ever starts, so there is no timer and no notification registration to
    /// account for when the app has no Better Stack source yet.
    ///
    /// `host` is the source's own ingesting host, with or without a scheme;
    /// blank keeps the shared fallback.
    func configure(token: String?, host: String? = nil) {
        lock.lock()
        self.token = (token?.isEmpty == false) ? token : nil
        if let url = Self.endpointURL(fromHost: host) {
            endpoint = url
        }
        let shouldStart = self.token != nil
        lock.unlock()

        guard shouldStart else { return }
        startBackgroundObserver()
        startFlushLoop()
    }

    func setUserID(_ userID: String?) {
        lock.lock()
        self.userID = userID
        lock.unlock()
    }

    func log(level: Observability.Level, message: String) {
        var drained: (token: String, events: [[String: Any]])?

        lock.lock()
        if let token {
            var event: [String: Any] = [
                "dt": Self.dateFormatter.string(from: Date()),
                "level": level.rawValue,
                "message": message,
                "app": "calibre-ios",
                "platform": "ios",
                "app_version": Self.appVersion,
                "build": Self.buildNumber,
                "environment": Observability.environment,
            ]
            if let userID {
                event["user_id"] = userID
            }
            buffer.append(event)
            if buffer.count >= Self.maxBatch {
                drained = drainLocked(token: token)
            }
        }
        lock.unlock()

        if let drained {
            send(token: drained.token, events: drained.events)
        }
    }

    /// Timer- and background-triggered flush. Safe to call with an empty buffer
    /// (a no-op) or before `configure` (no token, also a no-op).
    func flush() {
        var drained: (token: String, events: [[String: Any]])?
        lock.lock()
        if let token {
            drained = drainLocked(token: token)
        }
        lock.unlock()

        if let drained {
            send(token: drained.token, events: drained.events)
        }
    }

    /// Caller must hold `lock`. Empties the buffer and hands back what was in
    /// it — never partial, so a batch is either fully queued for send or still
    /// fully sitting in `buffer` waiting for the next flush.
    private func drainLocked(token: String) -> (token: String, events: [[String: Any]])? {
        guard !buffer.isEmpty else { return nil }
        let events = buffer
        buffer.removeAll(keepingCapacity: true)
        return (token, events)
    }

    /// `s123.us-west-2a.betterstackdata.com` or a full `https://…` URL. Blank,
    /// or an xcconfig token that never expanded, keeps the fallback.
    private static func endpointURL(fromHost host: String?) -> URL? {
        guard let raw = host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
        return URL(string: raw.hasPrefix("http") ? raw : "https://\(raw)")
    }

    private func send(token: String, events: [[String: Any]]) {
        guard let body = try? JSONSerialization.data(withJSONObject: events) else { return }
        lock.lock()
        let endpoint = self.endpoint
        lock.unlock()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        // The result is never inspected — success and failure are the same
        // outcome (nothing) from the caller's point of view.
        session.dataTask(with: request).resume()
    }

    private func startFlushLoop() {
        lock.lock()
        let alreadyRunning = flushTask != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        let task = Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.flushIntervalNanoseconds)
                self?.flush()
            }
        }
        lock.lock()
        flushTask = task
        lock.unlock()
    }

    private func startBackgroundObserver() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.flush()
        }
        #endif
    }
}
