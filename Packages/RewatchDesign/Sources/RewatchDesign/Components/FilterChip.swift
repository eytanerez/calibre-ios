import SwiftUI

/// Capsule filter toggle for brand/condition/price rails. Selected chips
/// fill chocolate with cream text; unselected sit on the card surface with
/// a hairline border. Press scales 0.97 and selection plays the selection
/// haptic.
public struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let minTapHeight: CGFloat?
    let action: () -> Void

    /// - Parameter minTapHeight: Grows the tap target to this height around
    ///   the drawn capsule, which stays the same size. Nil (the default, for
    ///   the dense rails in the filter sheet) keeps the target the capsule.
    ///   Pass `Space.touchTarget` where a row of chips is the page's control.
    public init(
        _ title: String,
        isSelected: Bool,
        minTapHeight: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.minTapHeight = minTapHeight
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.shared.play(.selection)
            action()
        } label: {
            Text(title)
                .font(RewatchType.label)
                .foregroundStyle(
                    isSelected ? Color.rewatch.primaryForeground : Color.rewatch.foreground
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.rewatch.primary : Color.rewatch.card, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.rewatch.border,
                            lineWidth: 1
                        )
                )
                .modifier(ChipTapHeight(minHeight: minTapHeight))
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.easeFast, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The grown tap target, when one was asked for; nothing at all otherwise,
/// so a chip in a dense rail lays out exactly as it always has.
private struct ChipTapHeight: ViewModifier {
    let minHeight: CGFloat?

    func body(content: Content) -> some View {
        if let minHeight {
            content
                .frame(minHeight: minHeight)
                .contentShape(Rectangle())
        } else {
            content
        }
    }
}

/// Horizontal chip scroller with soft fade masks at both edges so the rail
/// reads as continuable without a hard clip. Drop `FilterChip`s (or any
/// capsule content) inside.
public struct ChipRail<Content: View>: View {
    let content: Content
    private let fadeWidth: CGFloat = 16

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                content
            }
            .padding(.horizontal, fadeWidth)
            .padding(.vertical, 2)
        }
        // A rail whose chips already fit must not rubber-band sideways —
        // inside a vertical scroll view that reads as the whole page sliding.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .mask {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
                Rectangle()
                LinearGradient(
                    colors: [.black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: fadeWidth)
            }
        }
    }
}

private struct FilterChipPreviewHost: View {
    @State private var selected: Set<String> = ["Rolex"]
    private let brands = ["Rolex", "Omega", "Patek Philippe", "Cartier", "Tudor", "Audemars Piguet"]

    var body: some View {
        ChipRail {
            ForEach(brands, id: \.self) { brand in
                FilterChip(brand, isSelected: selected.contains(brand)) {
                    if selected.contains(brand) {
                        selected.remove(brand)
                    } else {
                        selected.insert(brand)
                    }
                }
            }
        }
        .padding(.vertical)
        .background(Color.rewatch.background)
    }
}

#Preview("Filter chips — light", traits: .sizeThatFitsLayout) {
    FilterChipPreviewHost()
}

#Preview("Filter chips — dark", traits: .sizeThatFitsLayout) {
    FilterChipPreviewHost()
        .preferredColorScheme(.dark)
}
