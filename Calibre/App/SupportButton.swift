import CalibreDesign
import SwiftUI

/// The "talk to us" affordance — a quiet circular button in the bottom-right
/// of every browsing surface.
///
/// It's attached per tab rather than to the whole shell so it stays above the
/// tab bar, and so anything presented as a cover — the listing wizard,
/// checkout, the sign-in gate — hides it automatically. Those are the moments
/// where a floating button would be a distraction rather than a help.
struct SupportButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            Haptics.shared.play(.press)
            router.push(.supportChat)
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.calibre.primaryForeground)
                .frame(width: 52, height: 52)
                .background(Color.calibre.primary, in: Circle())
                .shadow(color: Color.calibre.shadowTint.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Message support")
    }
}

extension View {
    /// Floats `SupportButton` over a tab's content.
    func supportButtonOverlay() -> some View {
        overlay(alignment: .bottomTrailing) {
            SupportButton()
                .padding(.trailing, Space.margin)
                .padding(.bottom, Space.margin)
        }
    }
}
