import SwiftUI

/// Work in progress. The only mark that loops, because looping is the thing it
/// is saying: the work has not finished. Every other mark fires once and stops
/// — a loop is decoration, a one-shot is confirmation.
struct BalanceWheelMark: View {
    private var stillness = MarkStillness()
    @State private var swing: Double = 0

    let size: CGFloat

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        wheel
            .rotationEffect(.degrees(swing * MarkMotion.amplitude.degrees))
            .markCanvas(size)
            .onAppear(perform: start)
            .accessibilityHidden(true)
    }

    private var wheel: some View {
        Self.rim.stroke(Color.calibre.primary, style: MarkGrid.style)
    }

    static var rim: Path {
        Path { path in
            // Rim, and the staff concentric inside it.
            path.addEllipse(in: CGRect(x: 16, y: 16, width: 88, height: 88))
            path.addEllipse(in: CGRect(x: 50, y: 50, width: 20, height: 20))

            // Arms out of the staff to the rim. They stop at the staff rather
            // than running through it: crossing diameters make a crosshair,
            // and a balance is not built that way.
            for angle in arms {
                path.move(to: markPoint(MarkGrid.centre, 10, angle))
                path.addLine(to: markPoint(MarkGrid.centre, 44, angle))
            }
        }
    }

    static let arms: [Angle] = [.degrees(90), .degrees(210), .degrees(330)]

    /// Brought up to amplitude first, then beating. Starting straight into the
    /// swing looks like the frame was dropped; the wind-up is what makes it
    /// look like something was set in motion.
    private func start() {
        guard !stillness.isRequested else { return }
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: MarkMotion.oscillateWindUp)) {
            swing = 1
        } completion: {
            withAnimation(.easeInOut(duration: MarkMotion.beat).repeatForever(autoreverses: true)) {
                swing = -1
            }
        }
    }
}

#Preview("balanceWheel", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.xl) {
        CalibreMark.balanceWheel()
        CalibreMark.balanceWheel(size: 44)
    }
    .padding(Space.xl)
    .calibrePageBackground()
}
