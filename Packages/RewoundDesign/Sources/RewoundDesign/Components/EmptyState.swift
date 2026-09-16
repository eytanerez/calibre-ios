import SwiftUI

/// Centered empty state for feeds, saved lists, and search results with no
/// matches: icon tile, a serif one-liner, muted supporting copy, and an
/// optional CTA. Generous air — never cramped into a corner.
public struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    let aside: String?

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
        self.aside = aside
    }

    public var body: some View {
        VStack(spacing: Space.l) {
            IconTile(systemName: icon)

            VStack(spacing: Space.s) {
                Text(title)
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                Text(message)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            .multilineTextAlignment(.center)

            if let aside, !aside.isEmpty {
                Text(aside)
                    .font(RewoundType.hand)
                    .foregroundStyle(Color.rewound.foreground.opacity(0.85))
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
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
