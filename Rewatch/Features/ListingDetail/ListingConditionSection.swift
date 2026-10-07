import RewatchDesign
import RewatchKit
import SwiftUI

// MARK: - The Condition section

/// The listing's Condition section (contracts, 2026-09-30, Part C), top to
/// bottom: the heading with the grade guide behind a button, the overall
/// grade, the parts set against it, the seller's history answers, and what
/// happens if the watch is not as described.
///
/// Every claim here is the seller's, checked by WPB Watch Co before the watch
/// ships (Eytan's ruling 1): nothing says the grade came from an inspection,
/// because a watch reaches the bench only after it sells. There is no
/// inspection-photos block; the gallery at the top of the page is the photos.
///
/// The page names "WPB Watch Co in West Palm Beach, Florida" in the
/// authentication band above this section, so everything here uses the short
/// name.
struct ListingConditionSection: View {
    let listing: Listing
    @Binding var showsGuide: Bool

    private var breakdown: ConditionBreakdown { ConditionBreakdown(listing: listing) }
    private var historyRows: [ListingDetailRow] { ListingHistoryWords.rows(for: listing) }

    /// Whether there is anything to show at all: a grade, a graded part, or a
    /// history answer. A listing with none of them has no section.
    static func hasContent(_ listing: Listing) -> Bool {
        let breakdown = ConditionBreakdown(listing: listing)
        return breakdown.overall != nil
            || breakdown.shape != .noParts
            || !ListingHistoryWords.rows(for: listing).isEmpty
    }

    var body: some View {
        let breakdown = breakdown
        VStack(alignment: .leading, spacing: Space.l) {
            header

            if showsGuide {
                ConditionGradeGuide(highlighted: breakdown.overall)
                    .transition(.opacity)
            }

            if let overall = breakdown.overall {
                OverallGradeCard(grade: overall, note: breakdown.overallNote)
            }

            ConditionPartsView(breakdown: breakdown)

            if !historyRows.isEmpty {
                historySection
            }

            ConditionAssuranceCard()
        }
    }

    /// "Condition", and the guide button on the right (the ruling of
    /// 2026-09-29 stands: shut by default, "View grade guide" / "Hide grade
    /// guide").
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("Condition")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                Haptics.shared.play(.selection)
                withAnimation(Motion.easeFast) { showsGuide.toggle() }
            } label: {
                Text(showsGuide ? "Hide grade guide" : "View grade guide")
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.foreground)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.xs + 2)
                    .background(Color.rewatch.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.rewatch.borderBright, lineWidth: 1))
                    .fixedSize()
            }
            .buttonStyle(PressableStyle())
            .a11yExpandTarget(currentSize: 32)
            .accessibilityValue(showsGuide ? "Expanded" : "Collapsed")
        }
    }

    /// The seller's three answers and the box-and-papers phrase, as the
    /// details table draws a row.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("History")
                .font(RewatchType.serif(.semiBold, 18, relativeTo: .title3))
                .foregroundStyle(Color.rewatch.foreground)
                .accessibilityAddTraits(.isHeader)
            Text("From the seller. WPB Watch Co checks it before it ships.")
                .font(RewatchType.caption)
                .foregroundStyle(Color.rewatch.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            ListingDetailsTable(rows: historyRows)
                .padding(.top, Space.xs)
        }
    }
}

// MARK: - The grade guide

/// The five grades as a card of rows: the grade, how to check for it on the
/// right, and the grade's sentence beneath. The row for this watch's overall
/// grade is tinted.
struct ConditionGradeGuide: View {
    /// This watch's overall grade, or nil when it has none.
    let highlighted: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let definitions = ConditionGrades.definitions
        VStack(spacing: 0) {
            ForEach(Array(definitions.enumerated()), id: \.element.grade) { index, definition in
                row(definition)
                if index < definitions.count - 1 {
                    Rectangle()
                        .fill(Color.rewatch.border)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.rewatch.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewatch.borderBright, lineWidth: 1)
        )
    }

    private func row(_ definition: ConditionGradeDefinition) -> some View {
        let isThisWatch = GradeScale.same(definition.grade, highlighted)
        return VStack(alignment: .leading, spacing: Space.xs) {
            // The check line sits on the right of the grade until an
            // accessibility size, where it goes under the grade rather than
            // leaving either a word of width.
            if typeSize.isAccessibilitySize {
                gradeName(definition)
                checkLine(definition)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    gradeName(definition)
                    Spacer(minLength: Space.s)
                    checkLine(definition)
                        .multilineTextAlignment(.trailing)
                }
            }
            Text(definition.description)
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .background(isThisWatch ? Color.rewatch.success.opacity(0.10) : Color.clear)
        // One swipe per grade: the grade, how it is checked, what it means,
        // and whether it is this watch's.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                definition.grade,
                isThisWatch ? "this watch's grade" : nil,
                definition.check,
                definition.description,
            ]
            .compactMap { $0 }
            .joined(separator: ". ")
        )
    }

    private func gradeName(_ definition: ConditionGradeDefinition) -> some View {
        Text(definition.grade)
            .font(RewatchType.bodySemiBold)
            .foregroundStyle(Color.rewatch.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func checkLine(_ definition: ConditionGradeDefinition) -> some View {
        Text(definition.check)
            .font(RewatchType.caption)
            .foregroundStyle(Color.rewatch.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - The overall grade

/// "Overall grade" with the grade as a pill, its sentence, the seller's note
/// on the whole watch, and whose grade it is.
struct OverallGradeCard: View {
    let grade: String
    let note: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Eyebrow("Overall grade")
                        StatusBadge(grade, tone: .success)
                    }
                } else {
                    HStack(alignment: .center, spacing: Space.m) {
                        Eyebrow("Overall grade")
                        Spacer(minLength: Space.s)
                        StatusBadge(grade, tone: .success)
                            .fixedSize()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Overall grade, \(grade)")

            if let sentence = GradeScale.definition(for: grade)?.description {
                Text(sentence)
                    .font(RewatchType.body)
                    .foregroundStyle(Color.rewatch.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note {
                SellerNoteLine(lead: "Seller's note:", note: note)
            }

            Rectangle()
                .fill(Color.rewatch.border)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.rewatch.primary)
                    .accessibilityHidden(true)
                Text("Graded by the seller. WPB Watch Co checks it before it ships.")
                    .font(RewatchType.label)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .conditionCardSurface()
    }
}

// MARK: - The parts

/// The seven part grades against the overall grade, in whichever of the
/// contract's shapes this listing takes.
struct ConditionPartsView: View {
    let breakdown: ConditionBreakdown

    var body: some View {
        switch breakdown.shape {
        case .noParts:
            EmptyView()
        case .allMatch(let parts):
            allMatch(parts)
        case .differ(let differing, _):
            worthKnowing(differing)
        case .noOverall(let parts):
            // A listing made before the overall grade was asked: every graded
            // part as a plain row, and never an overall made up from them.
            plainList(parts)
        }
    }

    private func plainList(_ parts: [ConditionBreakdown.Part]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                ConditionGradeRow(label: part.label, grade: part.grade, note: part.note) {
                    StatusBadge(part.grade, tone: .success)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)

                if index < parts.count - 1 {
                    Rectangle()
                        .fill(Color.rewatch.borderBright)
                        .frame(height: 1)
                }
            }
        }
        .conditionCardSurface()
    }

    private func allMatch(_ parts: [ConditionBreakdown.Part]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("All parts match the overall grade")
                .font(RewatchType.bodySemiBold)
                .foregroundStyle(Color.rewatch.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            WrapLayout(spacing: Space.s, lineSpacing: Space.s) {
                ForEach(parts) { part in
                    MatchedPartChip(label: part.label)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(parts.map(\.label).joined(separator: ", "))

            noteLines(breakdown.lineNotes)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .conditionCardSurface()
    }

    private func worthKnowing(_ differing: [ConditionBreakdown.Part]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Worth knowing")
                .font(RewatchType.serif(.semiBold, 18, relativeTo: .title3))
                .foregroundStyle(Color.rewatch.foreground)
                .accessibilityAddTraits(.isHeader)

            ForEach(differing) { part in
                DifferingPartCard(part: part, direction: breakdown.direction(of: part))
            }

            if let line = breakdown.matchingLine {
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.rewatch.success)
                            .accessibilityHidden(true)
                        Text(line)
                            .font(RewatchType.body)
                            .foregroundStyle(Color.rewatch.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    noteLines(breakdown.lineNotes)
                }
                .padding(.horizontal, Space.l)
                .padding(.vertical, Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .conditionCardSurface()
            }
        }
    }

    @ViewBuilder
    private func noteLines(_ parts: [ConditionBreakdown.Part]) -> some View {
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(parts) { part in
                    if let note = part.note {
                        SellerNoteLine(lead: ConditionBreakdown.noteLead(part), note: note)
                    }
                }
            }
        }
    }
}

/// One part graded apart from the whole: its name with an info mark, its grade
/// as a pill (warning tint when worse than the overall grade, neutral when
/// better), and the seller's note beneath.
private struct DifferingPartCard: View {
    let part: ConditionBreakdown.Part
    let direction: ConditionBreakdown.Direction

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tone: StatusBadge.Tone { direction == .worse ? .warning : .neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.s) {
                        name
                        StatusBadge(part.grade, tone: tone)
                    }
                } else {
                    HStack(alignment: .center, spacing: Space.m) {
                        name
                        Spacer(minLength: Space.s)
                        StatusBadge(part.grade, tone: tone)
                            .fixedSize()
                    }
                }
            }
            if let note = part.note {
                Text(note)
                    .font(RewatchType.body)
                    .foregroundStyle(Color.rewatch.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rewatch.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(
                    direction == .worse ? Color.rewatch.warning.opacity(0.45) : Color.rewatch.borderBright,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ["\(part.label), graded \(part.grade)", part.note.map { "The seller says: \($0)" }]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
    }

    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(direction == .worse ? Color.rewatch.warning : Color.rewatch.mutedForeground)
            Text(part.label)
                .font(RewatchType.bodySemiBold)
                .foregroundStyle(Color.rewatch.foreground)
        }
    }
}

/// A part that matches the overall grade, as a small chip with a check.
private struct MatchedPartChip: View {
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.rewatch.success)
            Text(label)
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.foreground)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 6)
        .background(Color.rewatch.secondary, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.rewatch.border, lineWidth: 1))
    }
}

/// "**Seller's note, Case:** light hairlines on the lugs". The lead is bold
/// and the seller's words follow in the body face.
struct SellerNoteLine: View {
    let lead: String
    let note: String

    var body: some View {
        Text(attributed)
            .font(RewatchType.label)
            .foregroundStyle(Color.rewatch.secondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var head = AttributedString(lead)
        head.font = RewatchType.sans(.semiBold, 13, relativeTo: .footnote)
        head.foregroundColor = Color.rewatch.foreground
        return head + AttributedString(" \(note)")
    }
}

// MARK: - The assurance card

/// The warm card that closes the section: what WPB Watch Co does before the
/// watch ships, and what happens if it is not as described.
struct ConditionAssuranceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Checked against these grades before it ships")
                .font(RewatchType.bodySemiBold)
                .foregroundStyle(Color.rewatch.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("WPB Watch Co checks every grade against the watch before it reaches you. If it is not as described, it is settled before it ships: a partial refund if you keep it, or it goes back to the seller.")
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.rewatch.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewatch.primary.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared surface

private extension View {
    /// The section's card: the card token, the box radius, the firm border the
    /// details table beside it uses.
    func conditionCardSurface() -> some View {
        background(Color.rewatch.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(Color.rewatch.borderBright, lineWidth: 1)
            )
    }
}
