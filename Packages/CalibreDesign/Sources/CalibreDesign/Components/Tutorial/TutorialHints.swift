import SwiftUI

/// The looping "do this" hint drawn over a spotlit control. Motion is a slow,
/// calm loop — never a bounce — and collapses to a single static glyph under
/// Reduce Motion so the instruction is never hidden behind animation.
struct TutorialHintView: View {
    let hint: TutorialHint
    /// Target rect in the overlay's coordinate space.
    let rect: CGRect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        Group {
            switch hint {
            case .none:
                EmptyView()
            case .tap, .longPress:
                pulseRing
            case .swipe(let edge), .drag(let edge):
                travellingFinger(edge: edge)
            case .type:
                caret
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(loop) { animate = true }
        }
    }

    private var loop: Animation {
        .easeInOut(duration: hint == .longPress ? 1.1 : 0.9).repeatForever(autoreverses: true)
    }

    // MARK: - Tap / long-press

    private var pulseRing: some View {
        ZStack {
            Circle()
                .stroke(Color.calibre.primaryForeground.opacity(0.9), lineWidth: 2)
                .frame(width: 30, height: 30)
                .scaleEffect(animate ? 1.9 : 0.9)
                .opacity(animate ? 0 : 0.9)
            Circle()
                .fill(Color.calibre.primaryForeground.opacity(0.9))
                .frame(width: 16, height: 16)
                .scaleEffect(animate ? 0.85 : 1)
        }
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Swipe / drag

    private func travellingFinger(edge: TutorialEdge) -> some View {
        // Travel a short distance from centre toward the edge, fading out,
        // looping — reads as "push this way".
        let travel: CGFloat = 34
        let offset = CGSize(
            width: edge.unit.width * travel,
            height: edge.unit.height * travel
        )
        return ZStack {
            Circle()
                .fill(Color.calibre.primaryForeground.opacity(0.92))
                .frame(width: 20, height: 20)
            Image(systemName: edge.arrowSymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.calibre.primary)
        }
        .offset(
            x: animate ? offset.width : 0,
            y: animate ? offset.height : 0
        )
        .opacity(animate ? 0.15 : 1)
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: - Typing

    private var caret: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.calibre.primaryForeground.opacity(0.9))
            .frame(width: 2, height: min(rect.height * 0.5, 22))
            .opacity(animate ? 0.15 : 1)
            .position(x: rect.minX + 10, y: rect.midY)
    }
}

/// A calm pulsing ring hugging the cutout so the eye lands on the spotlit
/// control. Static under Reduce Motion.
struct TutorialSpotlightRing: View {
    let rect: CGRect
    let cutout: TutorialCutout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        shape
            .stroke(Color.calibre.primaryForeground.opacity(reduceMotion ? 0.55 : 0.7), lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .scaleEffect(pulse ? 1.04 : 1)
            .opacity(pulse ? 0.35 : 0.85)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }

    private var shape: AnyShape {
        switch cutout {
        case .circle:
            AnyShape(Circle())
        case .capsule:
            AnyShape(Capsule())
        case .roundedRect(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        case .rect:
            AnyShape(Rectangle())
        }
    }
}
