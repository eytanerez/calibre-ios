import SwiftUI

/// Capsule filter toggle for brand/condition/price rails. Selected chips
/// fill chocolate with cream text; unselected sit on the card surface with
/// a hairline border. Press scales 0.97 and selection plays the selection
/// haptic.
public struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button {
            Haptics.shared.play(.selection)
            action()
        } label: {
            Text(title)
                .font(CalibreType.label)
                .foregroundStyle(
                    isSelected ? Color.calibre.primaryForeground : Color.calibre.foreground
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.calibre.primary : Color.calibre.card, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.calibre.border,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.easeFast, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        .background(Color.calibre.background)
    }
}

#Preview("Filter chips — light", traits: .sizeThatFitsLayout) {
    FilterChipPreviewHost()
}

#Preview("Filter chips — dark", traits: .sizeThatFitsLayout) {
    FilterChipPreviewHost()
        .preferredColorScheme(.dark)
}
