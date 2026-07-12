import CalibreDesign
import CalibreKit
import SwiftUI

/// Placeholder root for the Discover tab — the swipe deck arrives with P4.
/// Carries the one demo action that proves the guest gate end to end: "Save"
/// runs through `session.require`, so a guest sees the auth sheet and the
/// action replays after sign-in.
struct DiscoverScreen: View {
    @Environment(AuthSession.self) private var session
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(spacing: Space.xl) {
            EmptyState(
                icon: "rectangle.stack",
                title: "The deck is being assembled",
                message: "Swipe through the market one watch at a time when the Discover build lands."
            )

            Button {
                Haptics.shared.play(.press)
                session.require("Sign in to save this watch") {
                    Haptics.shared.play(.save)
                    toasts.show(
                        title: "Saved",
                        message: "We'll keep an eye on this one for you.",
                        tone: .success
                    )
                }
            } label: {
                Label("Save this watch", systemImage: "heart")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.secondary, fullWidth: true))
            .padding(.horizontal, Space.xxl)
            .accessibilityHint("Demonstrates the sign-in gate for guests")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
    }
}
