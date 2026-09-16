import RewoundDesign
import RewoundKit
import SwiftUI

/// Where the watch is, step by step, with what is known under each one.
///
/// What this replaces was a five-dot rail carrying a single index, and an index
/// cannot say two of the things a buyer needs read off it: that a step was
/// reached and did not complete, and what is known about a step that is done.
/// The steps and their states are computed in `RewoundKit` (`Order.timeline()`)
/// where they can be tested without a screen; this draws them and decides
/// nothing.
///
/// Vertical, unlike the wizard's rail. Six steps with a line under each do not
/// fit across a phone — the horizontal rail already fell back to a stacked
/// layout for captions this long — so it starts where it was going to end up.
struct OrderTimelineView: View {
    let steps: [OrderTimelineStep]
    /// The screen's one illustrated moment, when this is where it belongs.
    let mark: AnyView?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private let dotSize: CGFloat = 12

    init(steps: [OrderTimelineStep], mark: AnyView? = nil) {
        self.steps = steps
        self.mark = mark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Text("Progress")
                    .font(RewoundType.sectionTitle)
                    .foregroundStyle(Color.rewound.foreground)
                Spacer(minLength: 0)
                if let mark { mark }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    row(step, isLast: index == steps.count - 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            .background(Color.rewound.card, in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
            )
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Motion.ease(0.9).repeatForever(autoreverses: true)) { pulsing = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(accessibilityValue)
    }

    private func row(_ step: OrderTimelineStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(spacing: 0) {
                dot(step.state)
                if !isLast {
                    Capsule()
                        .fill(step.state == .done ? Color.rewound.primary : Color.rewound.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: dotSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(step.state == .now ? RewoundType.bodySemiBold : RewoundType.body)
                    .foregroundStyle(nameColour(step.state))
                    .fixedSize(horizontal: false, vertical: true)
                if let line = step.line {
                    Text(line)
                        .font(RewoundType.caption)
                        .foregroundStyle(
                            step.state == .stopped ? Color.rewound.destructive : Color.rewound.mutedForeground
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : Space.l)
        }
    }

    private func nameColour(_ state: OrderTimelineState) -> Color {
        switch state {
        case .done, .now: Color.rewound.foreground
        case .stopped: Color.rewound.destructive
        case .later: Color.rewound.mutedForeground
        }
    }

    @ViewBuilder
    private func dot(_ state: OrderTimelineState) -> some View {
        switch state {
        case .done:
            Circle()
                .fill(Color.rewound.primary)
                .frame(width: dotSize, height: dotSize)
        case .now:
            // The pulse is the only thing separating the step in progress from
            // the ones behind it; with motion off it reads as another finished
            // dot, so a ring says "here" while standing still.
            if reduceMotion {
                Circle()
                    .fill(Color.rewound.card)
                    .strokeBorder(Color.rewound.primary, lineWidth: 3)
                    .frame(width: dotSize, height: dotSize)
            } else {
                Circle()
                    .fill(Color.rewound.primary)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(pulsing ? 1 : 0.6)
            }
        case .stopped:
            // Drawn, not hidden. A watch that did not pass reached this step
            // and stopped on it, and a rail that simply ends leaves the reader
            // to decide whether their watch is still coming.
            ZStack {
                Circle()
                    .fill(Color.rewound.destructive)
                    .frame(width: dotSize, height: dotSize)
                Rectangle()
                    .fill(Color.rewound.card)
                    .frame(width: dotSize - 5, height: 2)
            }
        case .later:
            Circle()
                .fill(Color.rewound.card)
                .strokeBorder(Color.rewound.borderBright, lineWidth: 1.5)
                .frame(width: dotSize, height: dotSize)
        }
    }

    /// Read out as the step the watch is on and what is known there, which is
    /// what the column says to a reader who can see it.
    private var accessibilityValue: String {
        let current = steps.first { $0.state == .stopped } ?? steps.first { $0.state == .now }
        guard let current else {
            return steps.last.map { "\($0.name). \($0.line ?? "")" } ?? ""
        }
        let state = current.state == .stopped ? "stopped at" : "now at"
        return [state + " " + current.name, current.line].compactMap { $0 }.joined(separator: ". ")
    }
}
