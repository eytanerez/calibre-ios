import SwiftUI

/// 40pt warm-beige square holding a small SF Symbol — the anchor of trust
/// rows, feature lists, and empty states. Accent fill, accent-foreground
/// icon; never a loud brand fill.
public struct IconTile: View {
    let systemName: String

    public init(systemName: String) {
        self.systemName = systemName
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.calibre.accentForeground)
            .frame(width: 40, height: 40)
            .background(
                Color.calibre.accent,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
    }
}

#Preview("Icon tiles — light", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.m) {
        IconTile(systemName: "checkmark.shield")
        IconTile(systemName: "shippingbox")
        IconTile(systemName: "creditcard")
        IconTile(systemName: "arrow.uturn.left")
    }
    .padding()
    .background(Color.calibre.background)
}

#Preview("Icon tiles — dark", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.m) {
        IconTile(systemName: "checkmark.shield")
        IconTile(systemName: "shippingbox")
        IconTile(systemName: "creditcard")
        IconTile(systemName: "arrow.uturn.left")
    }
    .padding()
    .background(Color.calibre.background)
    .preferredColorScheme(.dark)
}
