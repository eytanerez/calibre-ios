import SwiftUI

/// The single sanctioned uppercase element — a quiet tracked-out label.
/// Use sparingly: card brand lines, section kickers.
public struct Eyebrow: View {
    let text: String
    let color: Color

    /// 0.18em at 11pt, and it has to stay 0.18em. Frozen at 1.98 the letters
    /// crowd back together as the type grows, which is the one thing an
    /// eyebrow cannot afford. Seeded from the documented base, so at the
    /// default size this is exactly 1.98 and the label is untouched.
    @ScaledMetric(relativeTo: .caption2) private var tracking: CGFloat = CalibreType.eyebrowTracking

    public init(_ text: String, color: Color = Color.calibre.mutedForeground) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        // Uppercased for the eye only. Baked into the string, "GBP" and "REF"
        // reach VoiceOver as capitals and get spelled out letter by letter;
        // as a display case the spoken text stays the words that were passed
        // in, and the drawn label is identical either way.
        Text(text)
            .font(CalibreType.eyebrow)
            .tracking(tracking)
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
            .font(CalibreType.caption)
            .foregroundStyle(Color.calibre.foreground)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 5)
            .background(Color.calibre.background.opacity(0.95), in: Capsule())
    }
}

/// Status badge tinted by semantic tone. Plain human words, no system codes.
public struct StatusBadge: View {
    public enum Tone {
        case neutral, info, success, warning, danger

        var tint: Color {
            switch self {
            case .neutral: Color.calibre.mutedForeground
            case .info: Color.calibre.primary
            case .success: Color.calibre.success
            case .warning: Color(red: 0.72, green: 0.48, blue: 0.11)
            case .danger: Color.calibre.destructive
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
            .font(CalibreType.label)
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
    .background(Color.calibre.background)
}
