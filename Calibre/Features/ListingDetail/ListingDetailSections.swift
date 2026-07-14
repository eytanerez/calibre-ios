import CalibreDesign
import CalibreKit
import SwiftUI

// MARK: - Description parsing

/// Sellers write descriptions as "Label: Value" lines with occasional free
/// text. The labeled lines feed the spec list; the rest become seller notes.
struct ParsedDescription {
    let specs: [(label: String, value: String)]
    let notes: String

    /// Labels already shown elsewhere on the PDP (buy box, spec list header,
    /// condition card) — parsed lines with these labels are dropped.
    private static let excludedLabels: Set<String> = [
        "brand", "model", "reference", "reference number",
        "year", "year of manufacture", "production year",
        "marketplace status", "box & papers", "box and papers",
        "condition", "overall condition", "crystal condition", "bezel condition",
        "bracelet condition", "clasp condition", "caseback condition",
        "case condition", "dial condition",
    ]

    init(_ text: String?) {
        var specs: [(label: String, value: String)] = []
        var noteLines: [String] = []

        for rawLine in (text ?? "").components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let colon = line.firstIndex(of: ":") {
                let label = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                let plausibleLabel = !label.isEmpty && label.count <= 32 && !value.isEmpty
                if plausibleLabel {
                    if !Self.excludedLabels.contains(label.lowercased()) {
                        specs.append((label, value))
                    }
                    continue
                }
            }
            noteLines.append(line)
        }

        self.specs = specs
        self.notes = noteLines.joined(separator: "\n\n")
    }
}

// MARK: - Quick spec row

/// The three at-a-glance tiles under the buy box: Condition / Year / Box & papers.
struct QuickSpecRow: View {
    let listing: Listing

    var body: some View {
        HStack(spacing: Space.m) {
            tile("Condition", listing.condition?.overall ?? "—")
            tile("Year", listing.productionYear.map(String.init) ?? "—")
            tile("Box & papers", boxPapersText)
        }
    }

    private var boxPapersText: String {
        switch listing.boxPapers {
        case true: "Full set"
        case false: "Watch only"
        default: "—"
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(CalibreType.caption)
                .foregroundStyle(Color.calibre.mutedForeground)
                .lineLimit(1)
            // Two-word values ("Very Good", "Like New") need room to wrap —
            // a single line with only an 0.8 scale factor was clipping them.
            Text(value)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.m)
        .background(
            Color.calibre.secondary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Condition grading

/// Per-part condition as status badges in a spec-list-styled card.
struct ConditionGradingCard: View {
    let condition: ListingCondition

    private var rows: [(label: String, value: String)] {
        [
            ("Overall", condition.overall),
            ("Crystal", condition.crystal),
            ("Bezel", condition.bezel),
            ("Bracelet", condition.bracelet),
            ("Clasp", condition.clasp),
            ("Caseback", condition.caseback),
        ].compactMap { label, value in
            value.map { (label, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Space.l) {
                    Text(rows[index].label)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.mutedForeground)
                    Spacer(minLength: Space.l)
                    StatusBadge(rows[index].value, tone: Self.tone(for: rows[index].value))
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

    static func tone(for grade: String) -> StatusBadge.Tone {
        switch grade.lowercased() {
        case "new", "like new": .success
        case "very good": .info
        case "good": .neutral
        case "worn": .warning
        default: .neutral
        }
    }
}

// MARK: - Seller card

/// The seller strip: monogram, username, sales count, star rating. Tapping
/// opens the storefront.
struct SellerCard: View {
    let seller: ListingSeller
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                AvatarInitial(name: seller.username, size: .m)

                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(seller.username)")
                        .font(CalibreType.bodyMedium)
                        .foregroundStyle(Color.calibre.foreground)
                    if let reputation = seller.reputation {
                        Text(reputation.salesCount == 1 ? "1 sale on Calibre" : "\(reputation.salesCount) sales on Calibre")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }

                Spacer()

                if let reputation = seller.reputation, let average = reputation.averageRating,
                   reputation.ratingCount > 0 {
                    HStack(spacing: Space.xs) {
                        StarRating(rating: average)
                        Text("(\(reputation.ratingCount))")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.calibre.mutedForeground)
            }
            .padding(Space.l)
            .background(Color.calibre.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.calibre.border, lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Seller \(seller.username). View storefront.")
    }
}

// MARK: - Authentication info sheet

/// Static editorial content behind the "Inspected at our authentication
/// center" callout.
struct AuthenticationInfoSheet: View {
    var body: some View {
        SheetScaffold(title: "Inspected before it ships", detents: [.medium, .large]) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text("Every watch sold on Calibre travels to our authentication center before it travels to you. Nothing ships buyer-direct.")
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.secondaryForeground)
                        .lineSpacing(5)

                    infoRow(
                        icon: "checkmark.shield",
                        title: "Authenticated by watchmakers",
                        message: "Movement, case, dial, and papers are examined by our in-house watchmakers against the reference's factory specification."
                    )
                    infoRow(
                        icon: "clock.badge.checkmark",
                        title: "Condition verified",
                        message: "We confirm the listing's condition grading part by part. If anything doesn't match, the sale doesn't proceed."
                    )
                    infoRow(
                        icon: "shippingbox",
                        title: "Insured to your door",
                        message: "After inspection, your watch ships fully insured with a signature required on delivery."
                    )

                    Text("If a watch fails inspection, you're refunded in full — no questions, no waiting.")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .padding(.top, Space.xs)
                }
                .padding(.bottom, Space.xxl)
            }
        }
    }

    private func infoRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                Text(message)
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.mutedForeground)
                    .lineSpacing(3)
            }
        }
    }
}
