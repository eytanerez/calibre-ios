import SwiftUI

/// Quiet trust/info band — "Authenticated by Calibre", buyer protection,
/// shipping notes. Accent-at-40% fill with a hairline border, a small tile
/// holding a brand-colored icon, and body copy. Pass an action to make the
/// band tappable (adds a chevron and press feedback).
public struct CalloutBand: View {
    let icon: String
    let title: String?
    let message: String
    let action: (() -> Void)?

    public init(
        icon: String,
        title: String? = nil,
        message: String,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { band }
                .buttonStyle(PressableStyle())
        } else {
            band
        }
    }

    private var band: some View {
        HStack(alignment: title == nil ? .center : .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calibre.primary)
                .frame(width: 32, height: 32)
                .background(
                    Color.calibre.card,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                }
                Text(message)
                    .font(title == nil ? CalibreType.body : CalibreType.label)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(Space.l)
        .background(
            Color.calibre.accent.opacity(0.4),
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }
}

#Preview("Callout band — light", traits: .sizeThatFitsLayout) {
    VStack(spacing: Space.m) {
        CalloutBand(
            icon: "checkmark.shield",
            title: "Authenticated by Calibre",
            message: "Every watch is inspected by our in-house watchmakers before it ships to you.",
            action: {}
        )
        CalloutBand(
            icon: "shippingbox",
            message: "Fully insured shipping — signature required on delivery."
        )
    }
    .padding()
    .background(Color.calibre.background)
}

#Preview("Callout band — dark", traits: .sizeThatFitsLayout) {
    CalloutBand(
        icon: "checkmark.shield",
        title: "Authenticated by Calibre",
        message: "Every watch is inspected by our in-house watchmakers before it ships to you.",
        action: {}
    )
    .padding()
    .background(Color.calibre.background)
    .preferredColorScheme(.dark)
}
