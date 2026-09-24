import SwiftUI

// MARK: - Connection, as the views see it

public extension EnvironmentValues {
    /// True while the phone has no route to the internet. Set once, at the
    /// app's root, from its connection monitor; a view that says "try again"
    /// reads it to say "you're offline" instead when that is the reason.
    @Entry var isOffline: Bool = false

    /// Ticks each time the connection comes back. A retry that is showing
    /// fires itself on the tick, so a page that failed offline reloads the
    /// moment it can, without anybody pressing anything.
    @Entry var reconnectCount: Int = 0
}

// MARK: - Retry

/// "Try again" that visibly tries.
///
/// The button it replaces started a background task and returned at once, so
/// it looked the same before, during and after a retry — and offline, where a
/// request fails in a few milliseconds, pressing it appeared to do nothing at
/// all (Eytan, 2026-09-23: "the try again button doesn't really show loading or
/// anything so it doesnt feel like the app is reacting"). This one owns the
/// work: it shows a spinner and "Trying again…" until the retry returns, and for
/// at least `minimumVisible` so a failure that comes back instantly is still
/// seen to have been attempted.
///
/// It also retries by itself when the connection comes back, unless
/// `retriesOnReconnect` is false — checkout's, where the button prices a
/// purchase or clears a payment error, and neither should happen unasked.
public struct RetryButton: View {
    private let title: String
    private let variant: RewoundButtonVariant
    private let fullWidth: Bool
    private let retriesOnReconnect: Bool
    private let action: () async -> Void

    @Environment(\.reconnectCount) private var reconnectCount
    @State private var isRetrying = false

    /// Long enough to read "Trying again…", short enough not to feel slow.
    private static let minimumVisible: Duration = .milliseconds(700)

    public init(
        _ title: String = "Try again",
        variant: RewoundButtonVariant = .primary,
        fullWidth: Bool = false,
        retriesOnReconnect: Bool = true,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.variant = variant
        self.fullWidth = fullWidth
        self.retriesOnReconnect = retriesOnReconnect
        self.action = action
    }

    public var body: some View {
        Button {
            Task { await run() }
        } label: {
            HStack(spacing: Space.s) {
                if isRetrying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(variant == .primary ? Color.rewound.primaryForeground : Color.rewound.primary)
                }
                Text(isRetrying ? "Trying again…" : title)
                    .contentTransition(.opacity)
            }
            .animation(.easeOut(duration: 0.15), value: isRetrying)
        }
        .buttonStyle(.rewound(variant, fullWidth: fullWidth))
        .disabled(isRetrying)
        .sensoryFeedback(.selection, trigger: isRetrying) { _, started in started }
        .accessibilityLabel(isRetrying ? "Trying again" : title)
        // The connection came back: try now rather than waiting to be asked.
        .onChange(of: reconnectCount) { _, _ in
            guard retriesOnReconnect else { return }
            Task { await run() }
        }
    }

    private func run() async {
        guard !isRetrying else { return }
        isRetrying = true
        let started = ContinuousClock.now
        await action()
        let elapsed = ContinuousClock.now - started
        if elapsed < Self.minimumVisible {
            try? await Task.sleep(for: Self.minimumVisible - elapsed)
        }
        isRetrying = false
    }
}
