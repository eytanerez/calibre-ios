import SwiftUI

/// Star rating in two voices. Display mode renders small chocolate stars
/// with partial fills for seller ratings on cards and profiles. Input mode
/// is the 1–5 review control: tap or drag across the stars, a quiet label
/// (Poor → Excellent) names the current value, and each change plays the
/// selection haptic.
public struct StarRating: View {
    private enum Mode {
        case display(Double)
        case input(Binding<Int>)
    }

    private let mode: Mode
    private let starSize: CGFloat

    private static let labels = ["Poor", "Fair", "Good", "Very Good", "Excellent"]

    /// Read-only stars, e.g. `StarRating(rating: 4.5)` next to a review count.
    public init(rating: Double, starSize: CGFloat = 13) {
        self.mode = .display(rating)
        self.starSize = starSize
    }

    /// Interactive 1–5 picker for the review flow. `selection` of 0 means
    /// "not yet rated".
    public init(selection: Binding<Int>, starSize: CGFloat = 28) {
        self.mode = .input(selection)
        self.starSize = starSize
    }

    public var body: some View {
        switch mode {
        case .display(let rating):
            displayStars(rating: rating)
        case .input(let selection):
            inputStars(selection: selection)
        }
    }

    // MARK: Display

    private func displayStars(rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                partialStar(fraction: min(max(rating - Double(index), 0), 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rated \(rating.formatted(.number.precision(.fractionLength(0...1)))) out of 5")
    }

    private func partialStar(fraction: Double) -> some View {
        Image(systemName: "star.fill")
            .font(.system(size: starSize))
            .foregroundStyle(Color.calibre.border)
            .overlay {
                Image(systemName: "star.fill")
                    .font(.system(size: starSize))
                    .foregroundStyle(Color.calibre.primary)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle()
                                .frame(width: geometry.size.width * fraction)
                        }
                    }
            }
    }

    // MARK: Input

    private func inputStars(selection: Binding<Int>) -> some View {
        let spacing = Space.s
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: spacing) {
                ForEach(1...5, id: \.self) { index in
                    Image(systemName: index <= selection.wrappedValue ? "star.fill" : "star")
                        .font(.system(size: starSize, weight: .light))
                        .foregroundStyle(
                            index <= selection.wrappedValue
                                ? Color.calibre.primary
                                : Color.calibre.borderBright
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let stepWidth = starSize + spacing
                        let index = Int(gesture.location.x / stepWidth) + 1
                        let clamped = min(max(index, 1), 5)
                        if clamped != selection.wrappedValue {
                            selection.wrappedValue = clamped
                            Haptics.shared.play(.selection)
                        }
                    }
            )

            Text(selection.wrappedValue > 0 ? Self.labels[selection.wrappedValue - 1] : "Tap to rate")
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(
            selection.wrappedValue > 0
                ? "\(selection.wrappedValue) out of 5, \(Self.labels[selection.wrappedValue - 1])"
                : "Not rated"
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection.wrappedValue = min(selection.wrappedValue + 1, 5)
            case .decrement: selection.wrappedValue = max(selection.wrappedValue - 1, 1)
            @unknown default: break
            }
        }
    }
}

private struct StarRatingPreviewHost: View {
    @State private var rating = 4

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(spacing: Space.s) {
                StarRating(rating: 4.5)
                Text("4.5 · 128 reviews")
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            StarRating(selection: $rating)
        }
        .padding()
        .background(Color.calibre.background)
    }
}

#Preview("Star rating — light", traits: .sizeThatFitsLayout) {
    StarRatingPreviewHost()
}

#Preview("Star rating — dark", traits: .sizeThatFitsLayout) {
    StarRatingPreviewHost()
        .preferredColorScheme(.dark)
}
