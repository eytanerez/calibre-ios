import RewoundDesign
import RewoundKit
import SwiftUI

// MARK: - The seller's own words

/// What a listing's description says, once the block the sell form used to
/// generate has been taken off it.
///
/// The description is the seller's notes and nothing else now: brand, model,
/// reference, the eight grades, the year and the three inclusion answers are
/// columns, and the spec sheet comes off `listing.specs`. A one-off migration
/// strips the generated block from rows that already carry it; this does the
/// same for a row that migration has not reached, so the app never shows a wall
/// of `Key: Value` lines where a sentence belongs.
///
/// **Only the keys the form generated are dropped, and nothing else.** The
/// version of this that shipped before split every line on its first colon and
/// treated anything with a plausible label as a spec — which silently deleted a
/// seller's own sentence the moment it contained a colon. "Serviced 2025: full
/// service" was a spec row called "Serviced 2025" and was gone from the notes.
/// A closed list cannot do that.
struct SellerNotes {
    let text: String

    /// The keys `listingDescription()` wrote, lowercased. A dealer's own
    /// `Movement: Automatic` is not on this list and is kept, because their
    /// description is theirs.
    private static let generatedKeys: Set<String> = [
        "brand", "model", "reference", "reference number",
        "case material", "dial", "case size", "movement", "caliber", "calibre",
        "bracelet", "thickness", "lug width", "water resistance",
        "condition", "case condition", "dial condition", "crystal condition",
        "bezel condition", "bracelet condition", "clasp condition",
        "caseback condition", "overall condition",
        "year of manufacture", "box", "papers", "booklets",
        "marketplace status",
    ]

    private static let notesKey = "seller notes"

    init(_ description: String?) {
        var kept: [String] = []
        for rawLine in (description ?? "").components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                // A blank line inside kept prose is the author's paragraph
                // break; leading ones would just indent the notes down the page.
                if !kept.isEmpty { kept.append("") }
                continue
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon])
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                if Self.generatedKeys.contains(key) {
                    continue
                }
                if key == Self.notesKey {
                    let value = String(line[line.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { kept.append(value) }
                    continue
                }
            }
            kept.append(line)
        }
        self.text = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Quick spec row

/// The three at-a-glance tiles under the buy box: Condition / Year / Box & papers.
struct QuickSpecRow: View {
    let listing: Listing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Three tiles across a phone give each about a third of the width. At
        // an accessibility size a third holds two or three characters, so
        // "Full set" was arriving as "Fu…" — past that point the tiles stack
        // full width instead.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.m) {
                tiles
            }
        } else {
            HStack(spacing: Space.m) {
                tiles
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        tile("Condition", listing.condition?.overall ?? "—")
        tile("Year", listing.productionYear.map(String.init) ?? "—")
        tile("Box & papers", boxPapersText)
    }

    private var boxPapersText: String {
        if listing.boxIncluded != nil || listing.papersIncluded != nil || listing.bookletsIncluded != nil {
            switch (listing.boxIncluded == true, listing.papersIncluded == true) {
            case (true, true): return "Full set"
            case (true, false): return "Box only"
            case (false, true): return "Papers only"
            case (false, false): return "Watch only"
            }
        }
        return switch listing.boxPapers {
        case true: "Full set"
        case false: "Watch only"
        default: "—"
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            // "Box & papers" fits on one line at the default size and needs a
            // second before it will fit at any larger one, so the limit lifts
            // only above the accessibility threshold. Gated rather than deleted:
            // dropping it outright left the default layout resting on a hand
            // measurement (~73pt of text in a ~96pt tile on a 375pt screen) with
            // no floor under it, so a longer localized label would silently wrap
            // the tile and grow the row for everyone.
            Text(label)
                .font(RewoundType.caption)
                .foregroundStyle(Color.rewound.mutedForeground)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            // Two-word values ("Very Good", "Like New") need room to wrap —
            // a single line with only an 0.8 scale factor was clipping them.
            Text(value)
                .font(RewoundType.bodyMedium)
                .foregroundStyle(Color.rewound.foreground)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.m)
        .background(
            Color.rewound.secondary.opacity(0.6),
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Condition grading

/// Per-part condition as status badges in a spec-list-styled card.
struct ConditionGradingCard: View {
    let condition: ListingCondition

    /// All eight parts, in the order the sell form asks for them — with the
    /// overall grade first, because that is the one a buyer reads as the
    /// summary. A part the seller left blank is simply not a row: nothing
    /// here is filled in from a grade that belongs to something else.
    private var rows: [(label: String, value: String)] {
        [
            ("Overall", condition.overall),
            ("Case", condition.caseCondition),
            ("Dial", condition.dial),
            ("Bezel", condition.bezel),
            ("Crystal", condition.crystal),
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
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.mutedForeground)
                    Spacer(minLength: Space.l)
                    StatusBadge(rows[index].value, tone: Self.tone(for: rows[index].value))
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Color.rewound.border)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.rewound.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
    }

    // One tone for every grade, deliberately: distinct colors per grade read
    // as if they meant something (a stoplight, a ranking) rather than just
    // labeling a fact about the watch.
    static func tone(for grade: String) -> StatusBadge.Tone {
        .success
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
                    HStack(spacing: Space.xs) {
                        Text("@\(seller.username)")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                        // A verified business is behind this listing — that is
                        // the whole of what the badge claims.
                        if seller.isVerifiedDealer == true {
                            DealerBadge(compact: true)
                        }
                    }
                    if let reputation = seller.reputation {
                        Text(reputation.salesCount == 1 ? "1 sale on Rewound" : "\(reputation.salesCount) sales on Rewound")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }
                }

                Spacer()

                if let reputation = seller.reputation, let average = reputation.averageRating,
                   reputation.ratingCount > 0 {
                    HStack(spacing: Space.xs) {
                        StarRating(rating: average)
                        Text("(\(reputation.ratingCount))")
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.rewound.mutedForeground)
            }
            .padding(Space.l)
            .background(Color.rewound.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewound.border, lineWidth: 1)
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
                    Text("Every watch sold on Rewound travels to the authentication center before it travels to you. Nothing ships buyer-direct.")
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.secondaryForeground)
                        .lineSpacing(5)

                    infoRow(
                        icon: "checkmark.shield",
                        title: "Authenticated by a specialist partner",
                        message: "Movement, case, dial, and papers are examined against the reference's factory specification by a third-party authentication partner, under a 72-hour commitment from arrival to verdict."
                    )
                    infoRow(
                        icon: "clock.badge.checkmark",
                        title: "Condition verified",
                        message: "The listing's condition grading is confirmed part by part. If anything doesn't match, the sale doesn't proceed."
                    )
                    infoRow(
                        icon: "wrench.and.screwdriver",
                        title: "1-year mechanical warranty",
                        message: "Every watch that passes authentication includes a one-year mechanical warranty in Rewound's name."
                    )
                    infoRow(
                        icon: "shippingbox",
                        title: "Insured on every leg",
                        message: "Every label on every leg requires a direct signature and is insured for the full sale price."
                    )

                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("If something is wrong")
                            .font(RewoundType.bodyMedium)
                            .foregroundStyle(Color.rewound.foreground)
                        Text("If a watch is found to be counterfeit, authentication costs you nothing, you're refunded in full including the card fee, and the watch is destroyed — it cannot legally be returned to anyone.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If a watch is genuine but not as described, your Rewound contact treats it as urgent and settles it case by case — either a partial refund, or the watch goes back.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("If authentication runs past its commitment, you hear from your Rewound contact before you have to ask.")
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    .font(RewoundType.bodyMedium)
                    .foregroundStyle(Color.rewound.foreground)
                Text(message)
                    .font(RewoundType.label)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .lineSpacing(3)
            }
        }
    }
}
