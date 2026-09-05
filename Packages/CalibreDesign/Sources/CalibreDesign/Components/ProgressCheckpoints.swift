import SwiftUI

/// Horizontal order tracker — the 5-checkpoint rail (placed → authenticated
/// → delivered). Dots joined by a hairline rail; completed segments fill
/// chocolate with a slow ease, the current dot pulses quietly (a ring instead
/// of a pulse under Reduce Motion), captions sit under each dot — or beside
/// them, once the type is too large for five columns.
public struct ProgressCheckpoints: View {
    let steps: [String]
    let currentIndex: Int
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pulsing = false

    private let dotSize: CGFloat = 12

    /// `currentIndex` is the step in progress; steps before it are complete.
    /// An index past the last step marks the whole journey complete.
    ///
    /// `label` names the journey to VoiceOver; the listing wizard is not an
    /// order, and every rail announcing itself as one misdescribes it.
    public init(steps: [String], currentIndex: Int, label: String = "Order progress") {
        self.steps = steps
        self.currentIndex = currentIndex
        self.label = label
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stackedRail
            } else {
                // The rail turns the corner when the captions do not fit, not
                // when the type size crosses a threshold. Those are different
                // questions and only the first one is the one being asked.
                //
                // Keying the fallback off `isAccessibilitySize` alone assumed
                // the captions are short, which the previews are ("Placed",
                // "Verified") and the order screen's are not. Five columns of
                // a 402pt phone are about 72pt each, and "Shipped to
                // authentication" needs more, so at the *default* size it wrapped
                // mid-word to a stranded "n" and ran into the caption beside it:
                // "At authenticatio / n" and "Shipped to authenticatio / n"
                // touching, because the columns sit at `spacing: 0`.
                //
                // `ViewThatFits` measures the horizontal rail with its captions
                // held to one line each. If they fit, it draws exactly the rail
                // that shipped — the wizard's "Details / Photos / Price /
                // Review" is unchanged. If they do not, the stacked rail that
                // already existed for accessibility sizes takes over, which is
                // the layout long captions needed all along.
                ViewThatFits(in: .horizontal) {
                    horizontalRail
                    stackedRail
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.ease(0.9).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityText)
    }

    /// The shipped rail: five equal columns under a hairline.
    private var horizontalRail: some View {
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
                        // One line, at its natural width, and never shrunk or
                        // clipped: this is the candidate `ViewThatFits` is
                        // measuring, and a caption allowed to wrap here would
                        // always "fit" and the measurement would mean nothing.
                        .fixedSize(horizontal: true, vertical: false)
                        // Keeps neighbouring captions off each other without
                        // moving the dots: the columns stay at `spacing: 0`,
                        // which is what `rail` computes its inset from.
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(alignment: .top) { rail }
    }

    /// Above the accessibility threshold a fifth of the screen holds about two
    /// characters, so the checkpoints turn the corner: dots down the leading
    /// edge, each caption on its own full-width line. Default sizes never
    /// reach this branch and keep the horizontal rail exactly as drawn.
    private var stackedRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: Space.m) {
                    VStack(spacing: 0) {
                        dot(at: index)
                        if index < steps.count - 1 {
                            Capsule()
                                .fill(
                                    index < currentIndex
                                        ? Color.calibre.primary
                                        : Color.calibre.border
                                )
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: dotSize)

                    Text(steps[index])
                        .font(CalibreType.caption)
                        .foregroundStyle(
                            index <= currentIndex
                                ? Color.calibre.foreground
                                : Color.calibre.mutedForeground
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, index < steps.count - 1 ? Space.m : 0)
                }
            }
        }
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
            if reduceMotion {
                // The pulse is the only thing separating the step in progress
                // from the completed ones; with motion off it reads as a sixth
                // finished dot. A ring says "here" while standing still.
                // Motion on — the default — is untouched.
                Circle()
                    .fill(Color.calibre.card)
                    .strokeBorder(Color.calibre.primary, lineWidth: 3)
                    .frame(width: dotSize, height: dotSize)
            } else {
                Circle()
                    .fill(Color.calibre.primary)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(pulsing ? 1 : 0.6)
            }
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
