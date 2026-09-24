import Network
import RewoundDesign
import SwiftUI

/// Whether the phone can reach the internet, for the whole app.
///
/// Offline, every request fails in milliseconds and each screen found out on
/// its own: some sections drew from what was cached, others showed their own
/// "couldn't load", and nothing on the page said why (Eytan, 2026-09-23:
/// "some of the page will load and others wont"). One monitor makes it one
/// fact: a bar under the beta bar says the phone is offline, every failed
/// load says so too (`\.isOffline`), and each of them retries itself when the
/// connection returns (`\.reconnectCount`).
@MainActor
@Observable
final class Connectivity {
    /// Starts true: a phone that launches online would otherwise flash the
    /// offline bar for the instant before the first path update lands.
    private(set) var isOnline = true
    /// Ticks on each offline → online change.
    private(set) var reconnects = 0
    /// True for a moment after the connection returns, so the bar can say so.
    private(set) var justReconnected = false

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var settle: Task<Void, Never>?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.shoprewound.connectivity"))
    }

    deinit {
        monitor.cancel()
    }

    /// Internal so the transitions can be tested without a network to lose.
    func update(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        settle?.cancel()
        guard online else {
            justReconnected = false
            return
        }
        reconnects += 1
        justReconnected = true
        settle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.justReconnected = false
        }
    }
}

/// The bar that says the phone is offline, and then that it is back.
///
/// It sits in the same stack as the beta bar, above each tab's navigation
/// stack, so it is on every screen and never covers one: while it shows, the
/// page sits below it.
struct ConnectionBar: View {
    @Environment(Connectivity.self) private var connectivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if !connectivity.isOnline {
                band(
                    icon: "wifi.slash",
                    title: "You're offline",
                    detail: "Rewound will load again when you're back.",
                    tint: Color.rewound.foreground,
                    ink: Color.rewound.background
                )
            } else if connectivity.justReconnected {
                band(
                    icon: "checkmark",
                    title: "Back online",
                    detail: "Loading what you missed.",
                    tint: Color.rewound.success,
                    ink: Color.rewound.primaryForeground
                )
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: connectivity.isOnline)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: connectivity.justReconnected)
    }

    private func band(icon: String, title: String, detail: String, tint: Color, ink: Color) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(RewoundType.bodySemiBold)
            Text(detail)
                .font(RewoundType.caption)
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
