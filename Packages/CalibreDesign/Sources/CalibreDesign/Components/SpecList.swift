import SwiftUI

/// Bordered card of label/value rows — the spec/detail list used on listing
/// pages (reference, year, movement, box & papers). Muted label on the left,
/// medium-weight value on the right, hairline dividers between rows. Borders
/// define the card; no shadow at rest.
public struct SpecList: View {
    let rows: [(label: String, value: String)]

    public init(_ rows: [(label: String, value: String)]) {
        self.rows = rows
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: Space.l) {
                    Text(rows[index].label)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                    Spacer(minLength: Space.l)
                    Text(rows[index].value)
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                        .multilineTextAlignment(.trailing)
                }
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
