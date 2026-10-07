import RewoundDesign
import SwiftUI

/// The grading scale at a glance, for a seller choosing a grade.
///
/// Eytan, 2026-10-06: the scale has to be easy to find while grading, "maybe
/// just a popup explaining it, with a button for a detailed explanation." The
/// sheet opens at the medium detent on the five grades, each with the one
/// sentence the listing page prints beside it (`ConditionGrades`, copied from
/// the site). "Detailed explanation" grows the same sheet to full height and
/// adds what each grade looks like on a watch and how to check for it, so the
/// long version is the scale itself, not a page with the scale somewhere down
/// it.
///
/// Standalone, so the redesigned listing form can present it from wherever
/// its Condition section ends up: `.sheet(isPresented:) { GradeScaleSheet() }`.
struct GradeScaleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var detent: PresentationDetent
    @State private var showsDetail: Bool
    /// How tall the list of grades is, measured, so the first detent can be
    /// exactly tall enough to show all of it with the button beneath.
    @State private var listHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .title2) private var chromeHeight: CGFloat = 150


    /// The at-a-glance height: every grade and the button, no scrolling.
    /// The medium detent until the list has been measured; where the fit is
    /// taller than the screen allows, the system clamps it and the list
    /// scrolls inside it, so nothing is ever cut off.
    private var glance: PresentationDetent {
        listHeight > 0 ? .height(listHeight + chromeHeight) : .medium
    }

    /// - Parameter startsDetailed: Open straight on the detailed explanation,
    ///   at full height, for a caller whose reader asked for the long version.
    init(startsDetailed: Bool = false) {
        _detent = State(initialValue: startsDetailed ? .large : .medium)
        _showsDetail = State(initialValue: startsDetailed)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.rewound.borderBright)
                .frame(width: 36, height: 5)
                .padding(.top, Space.s)
                .padding(.bottom, Space.m)
                .accessibilityHidden(true)

            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(spacing: 0) {
                        let definitions = ConditionGrades.definitions
                        ForEach(Array(definitions.enumerated()), id: \.element.grade) { index, definition in
                            GradeScaleRow(position: index + 1, definition: definition, showsDetail: showsDetail)
                            if index < definitions.count - 1 {
                                Rectangle().fill(Color.rewound.border).frame(height: 1)
                            }
                        }
                    }
                    .background(Color.rewound.card)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                            .strokeBorder(Color.rewound.border, lineWidth: 1)
                    )

                    if showsDetail {
                        Text(SellFieldHelp.grades)
                            .font(RewoundType.label)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.l)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    if !showsDetail { listHeight = height }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        // Pinned under the list, so the long version is one tap away at the
        // medium detent too, without scrolling for the button.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showsDetail {
                Button("Detailed explanation") {
                    withAnimation(Motion.easeFast) {
                        showsDetail = true
                        detent = .large
                    }
                }
                .buttonStyle(.rewound(.secondary, fullWidth: true))
                .accessibilityHint("Shows what each grade looks like on a watch, and how to check for it.")
                .accessibilityIdentifier("gradeScale.detail")
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s)
                .padding(.bottom, Space.l)
                .background(Color.rewound.card)
            }
        }
        .presentationDetents([glance, .large], selection: $detent)
        // Follow the measurement while the sheet sits at its first detent.
        .onChange(of: listHeight) {
            if detent != .large { detent = glance }
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.rewound.card)
        .presentationCornerRadius(Radius.panel)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("Condition grades")
                .font(RewoundType.sectionTitle)
                .foregroundStyle(Color.rewound.foreground)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .frame(width: Space.touchTarget, height: Space.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close condition grades")
            .accessibilityIdentifier("gradeScale.close")
        }
        .padding(.leading, Space.margin)
        .padding(.trailing, Space.margin - Space.m)
        .padding(.bottom, Space.s)
    }
}

/// One grade: its place on the scale, the word, and the sentence; with the
/// detail on, what it looks like and how to check for it as well.
private struct GradeScaleRow: View {
    let position: Int
    let definition: ConditionGradeDefinition
    let showsDetail: Bool

    @ScaledMetric(relativeTo: .footnote) private var badgeSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text("\(position)")
                .font(RewoundType.sans(.semiBold, 11, relativeTo: .caption2))
                .monospacedDigit()
                .foregroundStyle(Color.rewound.mutedForeground)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(Color.rewound.secondary))

            VStack(alignment: .leading, spacing: 2) {
                Text(definition.grade)
                    .font(RewoundType.bodySemiBold)
                    .foregroundStyle(Color.rewound.foreground)
                Text(definition.description)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                if showsDetail {
                    Text(definition.points)
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.xs)
                    Text(definition.check)
                        .font(RewoundType.label)
                        .foregroundStyle(Color.rewound.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        // One swipe per grade: its place, the word and what it means.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["Grade \(position) of \(ConditionGrades.definitions.count): \(definition.grade).", definition.description]
        if showsDetail {
            parts += [definition.points, "\(definition.check)."]
        }
        return parts.joined(separator: " ")
    }
}

#Preview("Grade scale") {
    Color.rewound.background
        .sheet(isPresented: .constant(true)) { GradeScaleSheet() }
}
