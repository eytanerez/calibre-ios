import SwiftUI

/// Centered empty state for feeds, saved lists, and search results with no
/// matches: icon tile, a serif one-liner, muted supporting copy, and an
/// optional CTA. Generous air — never cramped into a corner.
///
/// A state built with `retry:` is a load that failed. Its button is a
/// `RetryButton` — it shows that it is trying — and while the phone is offline
/// the state says so instead of its own words, because "couldn't load" with no
/// reason is how a half-loaded page reads as broken. It also retries itself
/// when the connection comes back.
public struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let retry: (() async -> Void)?
    let aside: String?

    @Environment(\.isOffline) private var isOffline

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        aside: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.retry = nil
        self.aside = aside
    }

    /// A failed load, and the retry that shows it is working.
    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String = "Try again",
        aside: String? = nil,
        retry: @escaping () async -> Void
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = nil
        self.retry = retry
        self.aside = aside
    }

    /// Offline is the reason, so offline is what a failed load says.
    private var showsOffline: Bool { retry != nil && isOffline }

    public var body: some View {
        VStack(spacing: Space.l) {
            IconTile(systemName: showsOffline ? "wifi.slash" : icon)

            VStack(spacing: Space.s) {
                Text(showsOffline ? "You're offline" : title)
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                Text(
                    showsOffline
                        ? "Nothing new can load without a connection. This fills in by itself when you're back online."
                        : message
                )
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            .multilineTextAlignment(.center)
            .animation(.easeOut(duration: 0.2), value: showsOffline)

            if let aside, !aside.isEmpty {
                Text(aside)
                    .font(RewoundType.hand)
                    .foregroundStyle(Color.rewound.foreground.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            if let retry {
                RetryButton(actionTitle ?? "Try again", action: retry)
                    .padding(.top, Space.s)
            } else if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.rewoundPrimary)
                    .padding(.top, Space.s)
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.vertical, Space.xxl * 2)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Empty state — light", traits: .sizeThatFitsLayout) {
    EmptyState(
        icon: "heart",
        title: "Nothing saved yet",
        message: "Watches you save appear here so you can compare and act when the price is right.",
        actionTitle: "Browse the market",
        action: {}
    )
    .background(Color.rewound.background)
}

#Preview("Empty state — dark", traits: .sizeThatFitsLayout) {
    EmptyState(
        icon: "heart",
        title: "Nothing saved yet",
        message: "Watches you save appear here so you can compare and act when the price is right.",
        actionTitle: "Browse the market",
        action: {}
    )
    .background(Color.rewound.background)
    .preferredColorScheme(.dark)
}
