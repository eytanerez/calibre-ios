import SwiftUI

/// Live countdown capsule for offer expiry and auction-style deadlines.
/// Shows "23h 14m", tightens to "14m 22s" inside the final hour (with a
/// warning tint), and settles on "Expired". Plays the warning haptic once
/// the moment it hits zero while on screen.
public struct CountdownChip: View {
    let target: Date
    @State private var firedWarning = false

    public init(until target: Date) {
        self.target = target
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = target.timeIntervalSince(context.date)
            let expired = remaining <= 0

            HStack(spacing: 5) {
                Image(systemName: expired ? "clock.badge.xmark" : "clock")
                    .font(.system(size: 11, weight: .medium))
                Text(text(remaining: remaining))
                    .font(CalibreType.label)
                    .monospacedDigit()
            }
            .foregroundStyle(tint(remaining: remaining))
            .padding(.horizontal, Space.m)
            .padding(.vertical, 5)
            .background(tint(remaining: remaining).opacity(0.12), in: Capsule())
            .onChange(of: expired) { _, nowExpired in
                if nowExpired && !firedWarning {
                    firedWarning = true
                    Haptics.shared.play(.warning)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(expired ? "Expired" : "Expires in \(text(remaining: remaining))")
        }
    }

    private func text(remaining: TimeInterval) -> String {
        guard remaining > 0 else { return "Expired" }
        let total = Int(remaining.rounded(.up))
        if total >= 86_400 {
            return "\(total / 86_400)d \((total % 86_400) / 3_600)h"
        }
        if total >= 3_600 {
            return "\(total / 3_600)h \((total % 3_600) / 60)m"
        }
        return "\(total / 60)m \(total % 60)s"
    }

    private func tint(remaining: TimeInterval) -> Color {
        if remaining <= 0 { return Color.calibre.mutedForeground }
        // Final hour shares the StatusBadge warning tint — one warm amber, not a new color.
        if remaining < 3_600 { return StatusBadge.Tone.warning.tint }
        return Color.calibre.accentForeground
    }
}

#Preview("Countdown — light", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.m) {
        CountdownChip(until: .now.addingTimeInterval(23 * 3_600 + 14 * 60))
        CountdownChip(until: .now.addingTimeInterval(14 * 60 + 22))
        CountdownChip(until: .now.addingTimeInterval(-60))
    }
    .padding()
    .background(Color.calibre.background)
}

#Preview("Countdown — dark", traits: .sizeThatFitsLayout) {
    HStack(spacing: Space.m) {
        CountdownChip(until: .now.addingTimeInterval(23 * 3_600 + 14 * 60))
        CountdownChip(until: .now.addingTimeInterval(14 * 60 + 22))
        CountdownChip(until: .now.addingTimeInterval(-60))
    }
    .padding()
    .background(Color.calibre.background)
    .preferredColorScheme(.dark)
}
