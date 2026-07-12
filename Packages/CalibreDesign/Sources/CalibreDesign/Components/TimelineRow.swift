import SwiftUI

/// One step of a negotiation timeline — offers, counters, acceptance.
/// A leading rail (dot + connecting line) anchors the sequence; the content
/// card sits trailing and primary-tinted for the buyer, leading and
/// accent-tinted for the seller. Serif amount, optional message, relative
/// time caption.
public struct TimelineRow: View {
    /// Which party this event belongs to — drives tint and alignment.
    public enum Side {
        case buyer, seller
    }

    let side: Side
    let heading: String?
    let amount: String
    let message: String?
    let date: Date
    let isFirst: Bool
    let isLast: Bool

    public init(
        side: Side,
        heading: String? = nil,
        amount: String,
        message: String? = nil,
        date: Date,
        isFirst: Bool = false,
        isLast: Bool = false
    ) {
        self.side = side
        self.heading = heading
        self.amount = amount
        self.message = message
        self.date = date
        self.isFirst = isFirst
        self.isLast = isLast
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            rail

            HStack(spacing: 0) {
                if side == .buyer {
                    Spacer(minLength: Space.xxl)
                }
                card
                if side == .seller {
                    Spacer(minLength: Space.xxl)
                }
            }
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.calibre.border)
                .frame(width: 2, height: 10)
                .opacity(isFirst ? 0 : 1)
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(Color.calibre.border)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(isLast ? 0 : 1)
        }
        .frame(width: 12)
        .padding(.bottom, isLast ? 0 : -Space.m)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let heading {
                Text(heading)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            Text(amount)
                .font(CalibreType.priceSmall)
                .foregroundStyle(Color.calibre.foreground)
            if let message {
                Text(message)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(date, format: .relative(presentation: .named))
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .padding(.top, 1)
        }
        .padding(Space.m)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
    }

    private var dotColor: Color {
        switch side {
        case .buyer: Color.calibre.primary
        case .seller: Color.calibre.accentForeground
        }
    }

    private var fill: Color {
        switch side {
        case .buyer: Color.calibre.primary.opacity(0.08)
        case .seller: Color.calibre.accent.opacity(0.5)
        }
    }

    private var stroke: Color {
        switch side {
        case .buyer: Color.calibre.primary.opacity(0.2)
        case .seller: Color.calibre.border
        }
    }
}

@MainActor
private var demoTimeline: some View {
    VStack(spacing: Space.m) {
        TimelineRow(
            side: .buyer,
            heading: "You offered",
            amount: "$11,800",
            date: .now.addingTimeInterval(-7_200),
            isFirst: true
        )
        TimelineRow(
            side: .seller,
            heading: "Seller countered",
            amount: "$12,100",
            message: "Full set with 2019 papers — this is as low as I can go.",
            date: .now.addingTimeInterval(-3_600)
        )
        TimelineRow(
            side: .buyer,
            heading: "You accepted",
            amount: "$12,100",
            date: .now.addingTimeInterval(-300),
            isLast: true
        )
    }
    .padding()
    .background(Color.calibre.background)
}

#Preview("Timeline — light", traits: .sizeThatFitsLayout) {
    demoTimeline
}

#Preview("Timeline — dark", traits: .sizeThatFitsLayout) {
    demoTimeline
        .preferredColorScheme(.dark)
}
