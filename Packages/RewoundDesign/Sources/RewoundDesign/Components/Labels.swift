import SwiftUI

/// The single sanctioned uppercase element — a quiet tracked-out label.
/// Use sparingly: card brand lines, section kickers.
public struct Eyebrow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    let color: Color

    /// 0.18em at 11pt, and it has to stay 0.18em. Frozen at 1.98 the letters
    /// crowd back together as the type grows, which is the one thing an
    /// eyebrow cannot afford. Seeded from the documented base, so at the
    /// default size this is exactly 1.98 and the label is untouched.
    @ScaledMetric(relativeTo: .caption2) private var tracking: CGFloat = RewoundType.eyebrowTracking

    public init(_ text: String, color: Color = Color.rewound.mutedForeground) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        // Uppercased for the eye only. Baked into the string, "GBP" and "REF"
        // reach VoiceOver as capitals and get spelled out letter by letter;
        // as a display case the spoken text stays the words that were passed
        // in, and the drawn label is identical either way.
        Text(text)
            .font(RewoundType.eyebrow)
            .tracking(typeSize.isAccessibilitySize ? 0 : tracking)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(color)
            .textCase(.uppercase)
    }
}

/// Floating condition pill — frosted, sits on listing imagery.
public struct ConditionPill: View {
    let condition: String

    public init(_ condition: String) {
        self.condition = condition
    }

    public var body: some View {
        Text(condition)
            .font(RewoundType.caption)
            .foregroundStyle(Color.rewound.foreground)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 5)
            .background(Color.rewound.background.opacity(0.95), in: Capsule())
    }
}

/// The watcher count as it rides on a listing photograph: same frosted plate
/// the condition pill sits on, top-right corner. It used to share the price's
/// row underneath the photo, where it competed with the one number on the card
/// that may never be lost.
public struct WatcherPill: View {
    let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        Label("\(count)", systemImage: "eye")
            .labelStyle(.titleAndIcon)
            .font(RewoundType.caption)
            .foregroundStyle(Color.rewound.foreground)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 4)
            .background(Color.rewound.background.opacity(0.95), in: Capsule())
            .accessibilityElement(children: .ignore)
            // The eye carries the meaning and is not spoken, so without this
            // the card ends on a bare number.
            .accessibilityLabel("\(count) watching")
    }
}

/// "In cart", as it rides on a listing photograph.
///
/// Bottom-left, on the same frosted plate the condition and watcher pills use,
/// because the card's text block below the photo is measured to the point
/// (`ListingCardAlignmentTests`) and a row that renders for some cards and not
/// others is exactly what used to put two prices on two different lines. An
/// overlay on the photo costs no height at all.
///
/// The bag glyph carries the meaning for anyone reading it at a glance and the
/// word carries it for everyone else — Eytan's ask was that the card *say* it,
/// not only mark it.
public struct InCartPill: View {
    public init() {}

    public var body: some View {
        Label("In cart", systemImage: "bag.fill")
            .labelStyle(.titleAndIcon)
            .font(RewoundType.caption)
            .foregroundStyle(Color.rewound.primary)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 4)
            .background(Color.rewound.background.opacity(0.95), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("In your cart")
    }
}

/// Status badge tinted by semantic tone. Plain human words, no system codes.
public struct StatusBadge: View {
    public enum Tone {
        case neutral, info, success, warning, danger

        var tint: Color {
            switch self {
            case .neutral: Color.rewound.mutedForeground
            case .info: Color.rewound.primary
            case .success: Color.rewound.success
            // Was a raw sRGB literal — the one tone in this switch with no
            // dynamic provider behind it, so a "Reserved" badge stayed a
            // light-tuned amber on the dark page while its four siblings
            // moved, and Increase Contrast had nothing to reach. The palette
            // now carries the token the other four already had.
            case .warning: Color.rewound.warning
            case .danger: Color.rewound.destructive
            }
        }
    }

    let text: String
    let tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(RewoundType.label)
            .foregroundStyle(tone.tint)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 4)
            .background(tone.tint.opacity(0.12), in: Capsule())
    }
}

#Preview("Labels", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: Space.l) {
        Eyebrow("Rolex · 2019")
        ConditionPill("Like New")
        HStack(spacing: Space.s) {
            StatusBadge("Live", tone: .success)
            StatusBadge("Pending review", tone: .info)
            StatusBadge("Waiting on you", tone: .warning)
            StatusBadge("Declined", tone: .danger)
        }
    }
    .padding()
    .background(Color.rewound.background)
}
