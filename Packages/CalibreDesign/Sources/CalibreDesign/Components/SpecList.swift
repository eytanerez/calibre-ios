import SwiftUI

/// Bordered card of label/value rows — the spec/detail list used on listing
/// pages (reference, year, movement, box & papers). Muted label on the left,
/// medium-weight value on the right, hairline dividers between rows. Borders
/// define the card; no shadow at rest.
public struct SpecList: View {
    let rows: [(label: String, value: String)]
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ rows: [(label: String, value: String)]) {
        self.rows = rows
    }

    /// Whether a label and its value still fit across one row.
    ///
    /// The label takes what it needs and the value is measured on what is
    /// left, so past an accessibility size "Movement" leaves "Calibre 3135 ·
    /// Automatic" about a word of width and it breaks down the right edge a
    /// syllable at a time. Past that point the pair stacks — the same rule,
    /// and the same two shapes, the passport's spec table already ships.
    /// Below it nothing moves.
    private var sideBySide: Bool { !typeSize.isAccessibilitySize }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                specRow(rows[index])
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.calibre.border)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.calibre.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.calibre.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func specRow(_ spec: (label: String, value: String)) -> some View {
        let label = Text(spec.label)
            .font(CalibreType.body)
            .foregroundStyle(Color.calibre.mutedForeground)
        let value = Text(spec.value)
            .font(CalibreType.bodyMedium)
            .foregroundStyle(Color.calibre.foreground)

        Group {
            if sideBySide {
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    label
                    Spacer(minLength: Space.l)
                    value.multilineTextAlignment(.trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    label
                    value
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // One swipe per spec instead of two: the label and the figure are one
        // fact, and read apart the figure arrives with nothing attached to it.
        .accessibilityElement(children: .combine)
    }
}

private let demoRows: [(label: String, value: String)] = [
    ("Reference", "116610LN"),
    ("Year", "2019"),
    ("Case", "40mm · Oystersteel"),
    ("Movement", "Calibre 3135 · Automatic"),
    ("Box & papers", "Full set"),
    ("Condition", "Very Good"),
]

#Preview("Spec list — light", traits: .sizeThatFitsLayout) {
    SpecList(demoRows)
        .padding()
        .background(Color.calibre.background)
}

#Preview("Spec list — dark", traits: .sizeThatFitsLayout) {
    SpecList(demoRows)
        .padding()
        .background(Color.calibre.background)
        .preferredColorScheme(.dark)
}
