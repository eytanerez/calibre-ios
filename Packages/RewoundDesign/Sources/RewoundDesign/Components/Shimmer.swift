import SwiftUI

/// Warm shimmer sweep for skeleton loading states. Apply to placeholder
/// shapes while content loads. Respects Reduce Motion (static fill).
public struct Shimmer: ViewModifier {
    /// The sweep clips to the shape it is standing in for, so a skeleton that
    /// is a listing card has to be able to say so. Defaulting to `box` keeps
    /// every existing `shimmer()` drawing exactly the corner it drew before.
    let radius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public init(radius: CGFloat = Radius.box) {
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.calibre.secondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.calibre.accent.opacity(0.7), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .clipped()
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

public extension View {
    func shimmer(radius: CGFloat = Radius.box) -> some View {
        modifier(Shimmer(radius: radius))
    }
}

/// Ready-made skeleton for a listing-card slot.
public struct ListingCardSkeleton: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Matches `ListingCard`'s photo well, which is the card tier —
            // the sweep clips to the same corner or the skeleton is a
            // different shape from the thing it is standing in for.
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .aspectRatio(1, contentMode: .fit)
                .shimmer(radius: Radius.card)
            VStack(alignment: .leading, spacing: 3) {
                Rectangle().frame(width: 70, height: 10).shimmer()
                Rectangle().frame(width: 120, height: 14).shimmer()
                Rectangle().frame(width: 86, height: 10).shimmer()
                HStack {
                    Rectangle().frame(width: 60, height: 18).shimmer()
                    Spacer(minLength: 0)
                    Rectangle().frame(width: 28, height: 10).shimmer()
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 2)
        }
        // The skeleton is a stack of bare shapes, so VoiceOver reads nothing
        // at all while a screen loads — silence that is indistinguishable
        // from an empty shelf. One label on the card, not five on the bars.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Skeleton", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.l) {
        ListingCardSkeleton().frame(width: 160)
        ListingCardSkeleton().frame(width: 160)
    }
    .padding()
    .background(Color.calibre.background)
}
