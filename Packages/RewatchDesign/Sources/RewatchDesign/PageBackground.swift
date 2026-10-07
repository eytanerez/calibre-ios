import SwiftUI

public extension View {
    /// The sanctioned page ground: the background token, edge to edge. Use
    /// this on a screen's root instead of `.background(Color.rewatch.background)`;
    /// anything smaller than a screen takes the plain token.
    ///
    /// It laid a paper-grain tile over that token at 0.035 opacity until
    /// 2026-08-30, when Eytan took the grain out of all three surfaces. The
    /// modifier stays, and stays the only sanctioned page ground: it is the
    /// one place a screen's ground is decided, every screen root in the app
    /// goes through it, and keeping it is what lets the ground change again in
    /// one edit rather than once per screen. The `PaperGrain` view it used to
    /// reach for, and the tile that view loaded, are gone from the package —
    /// `DesignSystemContractTests.testPaperGrainIsNotBundled` is what keeps
    /// the tile from coming quietly back in a resource declaration.
    func rewatchPageBackground() -> some View {
        background {
            Color.rewatch.background
                .ignoresSafeArea()
        }
    }
}

#Preview("Page ground — light") {
    VStack(alignment: .leading, spacing: Space.l) {
        Text("Submariner Date").font(RewatchType.title)
        Text("The card sits on the page.")
            .font(RewatchType.body)
        Text("Wore it every day for six years.")
            .font(RewatchType.hand)
            .foregroundStyle(Color.rewatch.mutedForeground)
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rewatch.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.border, lineWidth: 1)
            )
    }
    .padding(Space.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .rewatchPageBackground()
}

#Preview("Page ground — dark") {
    Color.clear
        .rewatchPageBackground()
        .preferredColorScheme(.dark)
}
