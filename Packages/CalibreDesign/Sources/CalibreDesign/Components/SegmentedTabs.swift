import SwiftUI

/// Brand segmented control for switching between sibling views (Offers /
/// Orders / Saved). Equal-width text segments over a hairline baseline, and a
/// copper rule that wipes in under the selected label; selection plays the
/// selection haptic. Generic over any `Hashable` selection value.
///
/// One tab treatment for the whole product — this is the same rule the site
/// header, the sell tab bar and the seller shop's four sub-tabs draw
/// (CALIBRE_FINAL_PUSH_CONTRACTS.md §5, as amended by the round-2 review):
///
/// - **Every label reads at full strength.** Dimming the inactive ones made
///   the whole bar look disabled rather than making one of them look current,
///   which is exactly the complaint the review raised against the web nav. The
///   rule is the only thing that says where you are, so the weight does not
///   change either — a semibold-vs-medium swap also re-measures the label,
///   which would make the rule change width as it moved.
/// - **The rule is sized to the word, not to the hit area,** and sits ~2pt
///   under the text box rather than down at the container's edge.
/// - **It wipes in from the leading edge:** the transform is the only thing
///   animated. Fading it in makes it appear at full length and merely darken,
///   which is not a slide — the web version was corrected for the same reason.
public struct SegmentedTabs<Selection: Hashable>: View {
    @Binding var selection: Selection
    let items: [(value: Selection, label: String)]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Selection>, items: [(value: Selection, label: String)]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Equal-width segments cut an accessibility-size label down to
                // a word; stacked, every tab reads whole. Only sizes above the
                // accessibility threshold take this branch — at every default
                // size the row below ships exactly as drawn.
                VStack(spacing: 0) {
                    ForEach(items, id: \.value) { item in
                        segment(for: item.value, label: item.label)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(items, id: \.value) { item in
                        segment(for: item.value, label: item.label)
                    }
                }
            }
        }
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.calibre.border)
                .frame(height: 1)
        }
    }

    private func segment(for value: Selection, label: String) -> some View {
        // Stacked, the selected tab is marked down its leading edge: a
        // full-width bar under one row of a list reads as a divider, not as
        // "you are here". False at every default size.
        let stacked = typeSize.isAccessibilitySize
        let isSelected = value == selection
        return Button {
            guard value != selection else { return }
            Haptics.shared.play(.selection)
            withAnimation(Motion.easeMedium) {
                selection = value
            }
        } label: {
            Text(label)
                .font(CalibreType.bodyMedium)
                .foregroundStyle(Color.calibre.foreground)
                // The overlay hangs off the Text, so the rule measures the
                // word. Hung off the frame below it would measure the segment.
                .overlay(alignment: .bottom) {
                    if !stacked { TabUnderline(isSelected: isSelected, reduceMotion: reduceMotion) }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: Space.touchTarget,
                    alignment: stacked ? .leading : .center
                )
                .overlay(alignment: .leading) {
                    if stacked { TabLeadingRule(isSelected: isSelected, reduceMotion: reduceMotion) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        // The copper rule is the only visible mark of the current tab, and
        // VoiceOver cannot see it: without this trait it reads all six of
        // these screens' tabs identically.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The copper rule under a selected tab label: 2pt, rounded ends, sitting 2pt
/// below the text box, wiping in from the leading edge on the brand curve.
///
/// It is always in the tree and always full width — only its x-scale changes —
/// because that is what makes the wipe a transform rather than an insertion,
/// and it is why nothing here animates opacity.
public struct TabUnderline: View {
    let isSelected: Bool
    let reduceMotion: Bool

    public init(isSelected: Bool, reduceMotion: Bool) {
        self.isSelected = isSelected
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        Capsule()
            .fill(Color.calibre.primary)
            .frame(height: 2)
            .scaleEffect(x: isSelected ? 1 : 0, anchor: .leading)
            // 2pt of thickness plus 2pt of air: the rule's top edge lands 2pt
            // under the text box, not at the bottom of the 44pt hit area.
            .offset(y: 4)
            // A wipe becomes an instant state change under Reduce Motion. The
            // explicit animation also wins over the ambient `withAnimation`
            // the segment's button starts, which is what lets it be nil here.
            .animation(reduceMotion ? nil : Motion.easeMedium, value: isSelected)
            .accessibilityHidden(true)
    }
}

/// The stacked (accessibility-size) variant: the same rule stood on its
/// leading edge, wiping down from the top.
public struct TabLeadingRule: View {
    let isSelected: Bool
    let reduceMotion: Bool

    public init(isSelected: Bool, reduceMotion: Bool) {
        self.isSelected = isSelected
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        Capsule()
            .fill(Color.calibre.primary)
            .frame(width: 2)
            .scaleEffect(y: isSelected ? 1 : 0, anchor: .top)
            .animation(reduceMotion ? nil : Motion.easeMedium, value: isSelected)
            .accessibilityHidden(true)
    }
}

private struct SegmentedTabsPreviewHost: View {
    @State private var tab = "Offers"

    var body: some View {
        VStack(spacing: Space.xl) {
            SegmentedTabs(
                selection: $tab,
                items: [("Offers", "Offers"), ("Orders", "Orders"), ("Saved", "Saved")]
            )
            Text(tab)
                .font(CalibreType.body)
                .foregroundStyle(Color.calibre.mutedForeground)
        }
        .padding()
        .background(Color.calibre.background)
    }
}

#Preview("Segmented tabs — light", traits: .sizeThatFitsLayout) {
    SegmentedTabsPreviewHost()
}

#Preview("Segmented tabs — dark", traits: .sizeThatFitsLayout) {
    SegmentedTabsPreviewHost()
        .preferredColorScheme(.dark)
}
