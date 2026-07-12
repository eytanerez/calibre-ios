import SwiftUI

/// Warm shimmer sweep for skeleton loading states. Apply to placeholder
/// shapes while content loads. Respects Reduce Motion (static fill).
public struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

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
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

public extension View {
    func shimmer() -> some View {
        modifier(Shimmer())
    }
}

/// Ready-made skeleton for a listing-card slot.
public struct ListingCardSkeleton: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Rectangle()
                .aspectRatio(1, contentMode: .fit)
                .shimmer()
            Rectangle().frame(width: 70, height: 10).shimmer()
            Rectangle().frame(width: 120, height: 14).shimmer()
            Rectangle().frame(width: 60, height: 18).shimmer()
        }
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
