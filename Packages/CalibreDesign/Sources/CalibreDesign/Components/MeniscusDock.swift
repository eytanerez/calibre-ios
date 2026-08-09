import SwiftUI

// MARK: - Geometry

/// The dock outline: a rounded bar with a *socket* cut into its top edge, and
/// a bead riding in that socket. One continuous path — the notch is solved
/// parametrically rather than welded together from separate curves, so the
/// bar and bead read as one surface at every position.
///
/// The construction, per side: a shoulder circle of radius `s` is tangent to
/// the bar's top edge *and* externally tangent to the bead of radius `rb`, so
/// the distance between their centers is `s + rb`. With the bead lifted `by`
/// above the top edge, the shoulder's tangent point sits
/// `sqrt((s + rb)² - (s - by)²)` horizontally from the bead — see `reach`.
/// Subtracting those two shoulder discs is what carves the concave meniscus.
public struct MeniscusSocket: Shape {
    /// Bead center, in the shape's coordinate space.
    var beadX: CGFloat
    /// How far the bead center sits above the bar's top edge.
    var beadLift: CGFloat
    /// Shoulder radii. They differ while dragging — see `MeniscusDock`.
    var shoulderLeft: CGFloat
    var shoulderRight: CGFloat

    let beadRadius: CGFloat
    let barHeight: CGFloat
    let cornerRadius: CGFloat

    public var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get { .init(.init(beadX, beadLift), .init(shoulderLeft, shoulderRight)) }
        set {
            beadX = newValue.first.first
            beadLift = newValue.first.second
            shoulderLeft = newValue.second.first
            shoulderRight = newValue.second.second
        }
    }

    /// Horizontal distance from the bead center to where the shoulder meets
    /// the flat top edge. Zero when the circles can't reach each other, which
    /// keeps the path degenerate-but-valid rather than NaN.
    static func reach(shoulder s: CGFloat, bead rb: CGFloat, lift by: CGFloat) -> CGFloat {
        let inner = (s + rb) * (s + rb) - (s - by) * (s - by)
        return inner > 0 ? sqrt(inner) : 0
    }

    public func path(in rect: CGRect) -> Path {
        let barTop = rect.maxY - barHeight
        let corner = min(cornerRadius, barHeight / 2)
        let reachL = Self.reach(shoulder: shoulderLeft, bead: beadRadius, lift: beadLift)
        let reachR = Self.reach(shoulder: shoulderRight, bead: beadRadius, lift: beadLift)

        // Shoulder centers sit one radius *above* the top edge, tangent to it.
        let cL = CGPoint(x: beadX - reachL, y: barTop - shoulderLeft)
        let cR = CGPoint(x: beadX + reachR, y: barTop - shoulderRight)

        // Direction from each shoulder center toward the bead center. The left
        // one always lands in (-π/2, π/2), so sweeping down to π/2 is already
        // the short way round. The right one crosses the ±π branch cut once
        // the bead lifts past the shoulder radius, so lift it above π/2 first
        // — otherwise the sweep takes the long way and the shoulder renders as
        // a detached lobe.
        let thetaL = atan2(shoulderLeft - beadLift, reachL)
        var thetaR = atan2(shoulderRight - beadLift, -reachR)
        if thetaR < .pi / 2 { thetaR += 2 * .pi }

        // Where the shoulders touch the bead, seen from the bead's center.
        let beadStart = thetaL + .pi
        var beadEnd = thetaR + .pi
        while beadEnd < beadStart { beadEnd += 2 * .pi }

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: barTop + corner))
        path.addRelativeArc(
            center: CGPoint(x: rect.minX + corner, y: barTop + corner),
            radius: corner, startAngle: .radians(.pi), delta: .radians(.pi / 2)
        )
        path.addLine(to: CGPoint(x: beadX - reachL, y: barTop))
        // Left shoulder — concave, rising off the flat edge toward the bead.
        path.addRelativeArc(
            center: cL, radius: shoulderLeft,
            startAngle: .radians(.pi / 2), delta: .radians(thetaL - .pi / 2)
        )
        // Over the bead.
        path.addRelativeArc(
            center: CGPoint(x: beadX, y: barTop - beadLift), radius: beadRadius,
            startAngle: .radians(beadStart), delta: .radians(beadEnd - beadStart)
        )
        // Right shoulder — back down to the flat edge.
        path.addRelativeArc(
            center: cR, radius: shoulderRight,
            startAngle: .radians(thetaR), delta: .radians(.pi / 2 - thetaR)
        )
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: barTop))
        path.addRelativeArc(
            center: CGPoint(x: rect.maxX - corner, y: barTop + corner),
            radius: corner, startAngle: .radians(-.pi / 2), delta: .radians(.pi / 2)
        )
        path.addRelativeArc(
            center: CGPoint(x: rect.maxX - corner, y: rect.maxY - corner),
            radius: corner, startAngle: .zero, delta: .radians(.pi / 2)
        )
        path.addRelativeArc(
            center: CGPoint(x: rect.minX + corner, y: rect.maxY - corner),
            radius: corner, startAngle: .radians(.pi / 2), delta: .radians(.pi / 2)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Dock

public struct MeniscusDockItem<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String
    public let systemImage: String

    public var id: Value { value }

    public init(value: Value, label: String, systemImage: String) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
    }
}

/// Prototype dock — the bar's surface melts toward the active tab instead of
/// sliding an indicator under it. The bead is `Color.calibre.primary` at every
/// tab; it never takes on a per-tab hue.
///
/// Not wired into the app shell. Lives here so it can be evaluated in the
/// gallery against the rest of the system before anyone commits to it.
///
/// Note: the settle is a spring, which is a deliberate exception to `Motion`'s
/// ease-out-only rule — surface tension without overshoot doesn't read as
/// liquid. That exception is precisely what's under evaluation here.
public struct MeniscusDock<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [MeniscusDockItem<Value>]

    /// The bead while a finger owns it. Absent means it's resting on a tab.
    private struct Drag {
        var x: CGFloat
        var velocity: CGFloat
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: Drag?

    private let barHeight: CGFloat = 56
    private let beadRadius: CGFloat = 17
    /// Deliberately small. The bead reads as *emerged* because it's large
    /// relative to the bar, not because it floats high above it — lift it far
    /// and the neck thins into a tent instead of a meniscus.
    private let beadLift: CGFloat = 3
    private let shoulder: CGFloat = 12
    private let cornerRadius: CGFloat = 14
    private var headroom: CGFloat { beadRadius + beadLift + 4 }

    /// The widest a shoulder gets under full lean, from the coefficients below.
    private var maxShoulder: CGFloat { shoulder * 1.46 }

    public init(selection: Binding<Value>, items: [MeniscusDockItem<Value>]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        GeometryReader { proxy in
            let slots = slotCenters(in: proxy.size.width)
            let restX = slots[safe: selectedIndex] ?? proxy.size.width / 2
            let beadX = drag?.x ?? restX
            let lean = reduceMotion ? 0 : self.lean
            let magnitude = abs(lean)

            // Velocity leans the surface: the trailing shoulder draws out,
            // the leading one tightens.
            let socket = MeniscusSocket(
                beadX: beadX,
                beadLift: beadLift,
                shoulderLeft: shoulder * (1 + 0.06 * magnitude + 0.40 * lean),
                shoulderRight: shoulder * (1 + 0.06 * magnitude - 0.40 * lean),
                beadRadius: beadRadius,
                barHeight: barHeight,
                cornerRadius: cornerRadius
            )

            ZStack(alignment: .topLeading) {
                socket
                    .fill(plate)
                    .overlay { socket.stroke(rim, lineWidth: 1) }
                    .calibreShadow(.menu)

                bead(at: beadX)
                icons(slots: slots)
                activeLabel(at: beadX)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(slots: slots))
        }
        .frame(height: barHeight + headroom)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }

    // MARK: Layers

    private var plate: LinearGradient {
        LinearGradient(
            colors: [Color.calibre.card, Color.calibre.secondary],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var rim: LinearGradient {
        LinearGradient(
            colors: [Color.calibre.borderBright, Color.calibre.border],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func bead(at x: CGFloat) -> some View {
        Circle()
            .fill(Color.calibre.primary)
            .frame(width: (beadRadius - 3) * 2, height: (beadRadius - 3) * 2)
            .overlay {
                Image(systemName: items[safe: selectedIndex]?.systemImage ?? "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.calibre.primaryForeground)
            }
            .position(x: x, y: headroom - beadLift)
            .allowsHitTesting(false)
    }

    private func icons(slots: [CGFloat]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            let isSelected = item.value == selection
            Button {
                select(item.value)
            } label: {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .opacity(isSelected ? 0 : 1)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: slots[safe: index] ?? 0, y: headroom + 22)
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityShowsLargeContentViewer {
                Label(item.label, systemImage: item.systemImage)
            }
        }
    }

    private func activeLabel(at x: CGFloat) -> some View {
        Text(items[safe: selectedIndex]?.label ?? "")
            .font(CalibreType.caption)
            .foregroundStyle(Color.calibre.primary)
            .position(x: x, y: headroom + 42)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Interaction

    private var selectedIndex: Int {
        items.firstIndex { $0.value == selection } ?? 0
    }

    private var lean: CGFloat {
        guard let drag else { return 0 }
        return max(-1, min(1, drag.velocity / 1600))
    }

    /// Tab centers, inset far enough from the ends that the socket always has
    /// flat top edge to land on.
    ///
    /// The outer shoulders need `cornerRadius + maxReach` of clearance; spread
    /// items evenly across the raw width and the outer centers fall well short
    /// of that, so the socket runs off the rounded corner and leaves a spur.
    /// Solving `pad + (width - 2·pad) / 2n >= clearance` for `pad` gives the
    /// smallest inset that keeps every position legal.
    private func slotCenters(in width: CGFloat) -> [CGFloat] {
        let count = items.count
        guard count > 0 else { return [] }
        guard count > 1 else { return [width / 2] }

        let clearance = cornerRadius + MeniscusSocket.reach(
            shoulder: maxShoulder, bead: beadRadius, lift: beadLift
        )
        let n = CGFloat(count)
        let pad = max(0, (clearance - width / (2 * n)) / (1 - 1 / n))
        let inner = max(0, width - 2 * pad)
        let slot = inner / n
        return (0..<count).map { pad + slot * (CGFloat($0) + 0.5) }
    }

    /// A non-zero minimum distance leaves plain taps to the per-item buttons
    /// (which carry the accessibility traits) and claims only real drags.
    private func dragGesture(slots: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let x = min(max(value.location.x, slots.first ?? 0), slots.last ?? 0)
                drag = Drag(x: x, velocity: value.velocity.width)
                if let nearest = nearestIndex(to: x, in: slots),
                   items[safe: nearest]?.value != selection {
                    Haptics.shared.play(.selection)
                    selection = items[nearest].value
                }
            }
            .onEnded { value in
                if let nearest = nearestIndex(to: value.location.x, in: slots) {
                    select(items[nearest].value)
                }
                // Releasing the bead lets the lean relax to zero on the same
                // spring that carries it home.
                withAnimation(settle) { drag = nil }
            }
    }

    private func nearestIndex(to x: CGFloat, in slots: [CGFloat]) -> Int? {
        slots.enumerated().min { abs($0.element - x) < abs($1.element - x) }?.offset
    }

    private func select(_ value: Value) {
        guard value != selection else { return }
        Haptics.shared.play(.selection)
        withAnimation(settle) { selection = value }
    }

    private var settle: Animation {
        reduceMotion
            ? Motion.easeMedium
            : .interpolatingSpring(stiffness: 220, damping: 18)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Previews

private struct MeniscusDockPreview: View {
    @State private var tab = "home"

    var body: some View {
        VStack {
            Spacer()
            MeniscusDock(
                selection: $tab,
                items: [
                    .init(value: "home", label: "Home", systemImage: "house"),
                    .init(value: "community", label: "Community",
                          systemImage: "bubble.left.and.bubble.right"),
                    .init(value: "sell", label: "Sell", systemImage: "plus.circle.fill"),
                    .init(value: "vault", label: "Vault", systemImage: "latch.2.case"),
                    .init(value: "me", label: "Me", systemImage: "person"),
                ]
            )
            .padding(.horizontal, Space.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.calibre.background)
    }
}

#Preview("Meniscus dock — light") {
    MeniscusDockPreview()
}

#Preview("Meniscus dock — dark") {
    MeniscusDockPreview().preferredColorScheme(.dark)
}
