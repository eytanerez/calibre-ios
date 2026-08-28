import SwiftUI

/// Centered empty state for feeds, saved lists, and search results with no
/// matches: icon tile, a serif one-liner, muted supporting copy, an optional
/// handwritten aside, and an optional CTA. Generous air — never cramped into
/// a corner.
public struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    /// A person talking, not a second instruction.
    ///
    /// The message above it says what this screen is for; an aside is
    /// somebody leaning in afterwards — "Even the one you never take off". It
    /// is written in the hand and it is always optional, because most empty
    /// states have nothing to add and a room full of asides stops sounding
    /// like anyone. Never put the instruction here: an aside that has to be
    /// read is not an aside.
    let aside: String?
    let actionTitle: String?
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        aside: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.aside = aside
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Space.l) {
            IconTile(systemName: icon)

            VStack(spacing: Space.s) {
                Text(title)
                    .font(CalibreType.sectionTitle)
                    .foregroundStyle(Color.calibre.foreground)
                Text(message)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.mutedForeground)

                if let aside {
                    // Secondary foreground rather than muted: the hand is
                    // decorative styling of real content, and thinning its
                    // contrast to make it look inkier is how it stops being
                    // readable for the people who need it most.
                    Text(aside)
                        .font(CalibreType.hand)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .padding(.top, Space.xs)
                }
            }
            .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.calibrePrimary)
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
    .background(Color.calibre.background)
}

#Preview("Empty state — dark", traits: .sizeThatFitsLayout) {
    EmptyState(
        icon: "heart",
        title: "Nothing saved yet",
        message: "Watches you save appear here so you can compare and act when the price is right.",
        actionTitle: "Browse the market",
        action: {}
    )
    .background(Color.calibre.background)
    .preferredColorScheme(.dark)
}
