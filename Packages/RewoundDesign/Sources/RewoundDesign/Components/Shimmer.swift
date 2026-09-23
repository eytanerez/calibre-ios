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
            .foregroundStyle(Color.rewound.secondary)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.rewound.accent.opacity(0.7), .clear],
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

/// A skeleton made of the real view: the content redacted to placeholder
/// shapes, with the sweep running over those shapes only.
///
/// Hand-drawn skeletons (a 140×20 bar for a title, three lines for a card)
/// drift from the views they stand in for, and every drift is a jump when the
/// content lands (Eytan, 2026-09-23: "the skeleton doesnt match up anymore").
/// Drawing the real view with stand-in values makes the two the same shape by
/// construction — the same fonts, the same reserved lines, the same frames.
public struct SkeletonShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public init() {}

    public func body(content: Content) -> some View {
        let shapes = content.redacted(reason: .placeholder)
        shapes
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, Color.rewound.accent.opacity(0.7), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    // Only over the placeholder shapes, never over the page
                    // between them.
                    .mask { shapes }
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                            phase = 1
                        }
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

public extension View {
    /// Draws this view as its own loading skeleton. See `SkeletonShimmer`.
    func skeleton() -> some View {
        modifier(SkeletonShimmer())
    }
}

/// Ready-made skeleton for a listing-card slot: a real `ListingCard` with
/// stand-in values, so it is exactly the height of the card that replaces it.
public struct ListingCardSkeleton: View {
    private let reservesReasonLine: Bool

    /// `reservesReasonLine` matches a lane whose cards carry a "why this one"
    /// line, which is one more line of card than a plain lane's.
    public init(reservesReasonLine: Bool = false) {
        self.reservesReasonLine = reservesReasonLine
    }

    public var body: some View {
        ListingCard(
            model: ListingCardModel(
                id: "skeleton",
                brand: "Brand",
                year: "2024",
                title: "Watch model",
                reference: "Ref. 000000",
                priceText: "$00,000",
                reservesReasonLine: reservesReasonLine
            )
        ) { _ in
            Color.clear
        }
        .skeleton()
    }
}

#Preview("Skeleton", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.l) {
        ListingCardSkeleton().frame(width: 160)
        ListingCardSkeleton().frame(width: 160)
    }
    .padding()
    .background(Color.rewound.background)
}
