import CalibreDesign
import SwiftUI

/// A one-time explainer shown the first time a visitor opens Discover —
/// swiping is not a familiar marketplace pattern, so the deck introduces
/// itself before the first gesture rather than assuming it's obvious.
struct DiscoverIntroOverlay: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.calibre.shadowTint.opacity(0.5).ignoresSafeArea()

            VStack(spacing: Space.xl) {
                HStack(spacing: Space.l) {
                    swipeGlyph(icon: "xmark", label: "Pass", tint: Color.calibre.mutedForeground)
                    swipeGlyph(icon: "heart.fill", label: "Save", tint: Color.calibre.success)
                }

                VStack(spacing: Space.s) {
                    Text("Swipe to discover")
                        .font(CalibreType.title)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.center)
                    Text("Swipe right to save a watch, left to pass. Tap any card to see the full listing.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Start swiping") {
                    finish()
                }
                .buttonStyle(.calibre(.primary, fullWidth: true))
            }
            .padding(Space.xxl)
            .frame(maxWidth: 360)
            .background(Color.calibre.card, in: RoundedRectangle(cornerRadius: Radius.overlay, style: .continuous))
            .calibreShadow(.modal)
            .padding(.horizontal, Space.xxl)
            .scaleEffect(shown ? 1 : 0.96)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.easeSlow) {
                shown = true
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func swipeGlyph(icon: String, label: String, tint: Color) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Color.calibre.accent, in: Circle())
            Text(label)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
    }

    private func finish() {
        Haptics.shared.play(.press)
        withAnimation(Motion.easeMedium) {
            shown = false
        }
        // Let the dismiss animation land before tearing down the cover.
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.16)) {
            onFinish()
        }
    }
}
