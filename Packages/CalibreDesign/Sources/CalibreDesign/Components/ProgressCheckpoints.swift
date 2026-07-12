import SwiftUI

/// Horizontal order tracker — the 5-checkpoint rail (placed → authenticated
/// → delivered). Dots joined by a hairline rail; completed segments fill
/// chocolate with a slow ease, the current dot pulses quietly (static under
/// Reduce Motion), captions sit under each dot.
public struct ProgressCheckpoints: View {
    let steps: [String]
    let currentIndex: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private let dotSize: CGFloat = 12

    /// `currentIndex` is the step in progress; steps before it are complete.
    /// An index past the last step marks the whole journey complete.
    public init(steps: [String], currentIndex: Int) {
        self.steps = steps
        self.currentIndex = currentIndex
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(steps.indices, id: \.self) { index in
                VStack(spacing: Space.s) {
                    dot(at: index)
                    Text(steps[index])
                        .font(CalibreType.caption)
                        .foregroundStyle(
                            index <= currentIndex
                                ? Color.calibre.foreground
                                : Color.calibre.mutedForeground
                        )
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) { rail }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.ease(0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Order progress")
        .accessibilityValue(accessibilityText)
    }

    /// The connecting rail: full-width hairline plus the animated chocolate fill.
    private var rail: some View {
        GeometryReader { geometry in
            let inset = geometry.size.width / CGFloat(max(steps.count, 1) * 2)
            let usable = max(geometry.size.width - inset * 2, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.calibre.border)
                    .frame(width: usable, height: 2)
                Capsule()
                    .fill(Color.calibre.primary)
                    .frame(width: usable * completedFraction, height: 2)
                    .animation(Motion.easeSlow, value: currentIndex)
            }
            .offset(x: inset, y: (dotSize - 2) / 2)
        }
        .frame(height: dotSize)
    }

    @ViewBuilder
    private func dot(at index: Int) -> some View {
        if index < currentIndex {
            Circle()
                .fill(Color.calibre.primary)
                .frame(width: dotSize, height: dotSize)
        } else if index == currentIndex {
            Circle()
                .fill(Color.calibre.primary)
                .frame(width: dotSize, height: dotSize)
                .opacity(reduceMotion ? 1 : (pulsing ? 1 : 0.6))
        } else {
            Circle()
                .fill(Color.calibre.card)
                .strokeBorder(Color.calibre.borderBright, lineWidth: 1.5)
                .frame(width: dotSize, height: dotSize)
        }
    }

    private var completedFraction: CGFloat {
        guard steps.count > 1 else { return 0 }
        let clamped = min(max(currentIndex, 0), steps.count - 1)
        return CGFloat(clamped) / CGFloat(steps.count - 1)
    }

    private var accessibilityText: String {
        guard steps.indices.contains(currentIndex) else {
            return currentIndex >= steps.count ? "Complete" : "Not started"
        }
        return "Step \(currentIndex + 1) of \(steps.count): \(steps[currentIndex])"
    }
}

private let demoSteps = ["Placed", "In transit", "Verified", "Shipped", "Delivered"]

#Preview("Checkpoints — light", traits: .sizeThatFitsLayout) {
    ProgressCheckpoints(steps: demoSteps, currentIndex: 2)
        .padding()
        .background(Color.calibre.background)
}

#Preview("Checkpoints — dark", traits: .sizeThatFitsLayout) {
    ProgressCheckpoints(steps: demoSteps, currentIndex: 2)
        .padding()
        .background(Color.calibre.background)
        .preferredColorScheme(.dark)
}
