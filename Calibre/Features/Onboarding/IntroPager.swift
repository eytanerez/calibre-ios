import CalibreDesign
import SwiftUI

/// First-launch introduction — three quiet panels of serif and cream, no
/// photography. Swipe or continue through; skip is always one tap away.
struct IntroPager: View {
    let onFinish: () -> Void

    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Panel {
        let icons: [String]
        let headline: String
        let line: String
    }

    private let panels: [Panel] = [
        Panel(
            icons: ["checkmark.shield", "sparkle.magnifyingglass", "checkmark.seal"],
            headline: "Every watch,\nauthenticated.",
            line: "Each piece is inspected in hand by our watchmakers before it ever reaches you."
        ),
        Panel(
            icons: ["arrow.left.arrow.right", "creditcard", "shippingbox"],
            headline: "Buy and sell\nwith confidence.",
            line: "Offers, payment, and insured shipping are handled end to end, so nothing is left to chance."
        ),
        Panel(
            icons: ["bell", "chart.line.uptrend.xyaxis", "heart"],
            headline: "The market,\nin your pocket.",
            line: "Follow the pieces you care about and act the moment the price is right."
        ),
    ]

    private var isLastPage: Bool { page == panels.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow("Calibre", color: Color.calibre.mutedForeground)
                Spacer()
                Button("Skip") {
                    finish()
                }
                .buttonStyle(.calibreGhost)
                .foregroundStyle(Color.calibre.mutedForeground)
                .accessibilityHint("Skips the introduction")
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, Space.s)

            TabView(selection: $page) {
                ForEach(panels.indices, id: \.self) { index in
                    IntroPanelView(
                        icons: panels[index].icons,
                        headline: panels[index].headline,
                        line: panels[index].line
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageDots
                .padding(.bottom, Space.xxl)

            Button {
                if isLastPage {
                    finish()
                } else {
                    Haptics.shared.play(.press)
                    withAnimation(Motion.easeMedium) { page += 1 }
                }
            } label: {
                Text(isLastPage ? "Get started" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.calibre(.primary, fullWidth: true))
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.l)
            .animation(nil, value: page)
        }
        .background(Color.calibre.background.ignoresSafeArea())
    }

    private func finish() {
        Haptics.shared.play(.press)
        onFinish()
    }

    private var pageDots: some View {
        HStack(spacing: Space.s) {
            ForEach(panels.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.calibre.primary : Color.calibre.borderBright)
                    .frame(width: index == page ? 18 : 6, height: 6)
                    .animation(reduceMotion ? nil : Motion.easeMedium, value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(panels.count)")
    }
}

/// One intro panel: a trio of icon-tile motifs, a Playfair headline, one
/// body line. Elements fade up in a slow stagger; plain crossfade under
/// Reduce Motion.
private struct IntroPanelView: View {
    let icons: [String]
    let headline: String
    let line: String

    var body: some View {
        VStack(spacing: Space.xl) {
            Spacer()

            HStack(spacing: Space.m) {
                ForEach(icons, id: \.self) { icon in
                    IconTile(systemName: icon)
                }
            }
            .accessibilityHidden(true)
            .introFadeUp(index: 0)

            Text(headline)
                .font(CalibreType.display)
                .foregroundStyle(Color.calibre.foreground)
                .multilineTextAlignment(.center)
                .introFadeUp(index: 1)

            Text(line)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .introFadeUp(index: 2)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Space.xxl)
        .frame(maxWidth: .infinity)
    }
}

/// The intro's 420ms fade-up entrance with a gentle stagger. Falls back to
/// a plain crossfade when Reduce Motion is on.
private struct IntroFadeUp: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                withAnimation(Motion.easeSlow.delay(Double(index) * 0.07)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func introFadeUp(index: Int) -> some View {
        modifier(IntroFadeUp(index: index))
    }
}
