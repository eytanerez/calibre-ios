import SwiftUI

/// Brand segmented control for switching between sibling views (Offers /
/// Orders / Saved). Equal-width text segments over a hairline baseline with
/// a sliding chocolate underline; selection plays the selection haptic.
/// Generic over any `Hashable` selection value.
public struct SegmentedTabs<Selection: Hashable>: View {
    @Binding var selection: Selection
    let items: [(value: Selection, label: String)]
    @Namespace private var underlineNamespace

    public init(selection: Binding<Selection>, items: [(value: Selection, label: String)]) {
        self._selection = selection
        self.items = items
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                segment(for: item.value, label: item.label)
            }
        }
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.calibre.border)
                .frame(height: 1)
        }
    }

    private func segment(for value: Selection, label: String) -> some View {
        Button {
            guard value != selection else { return }
            Haptics.shared.play(.selection)
            withAnimation(Motion.easeMedium) {
                selection = value
            }
        } label: {
            Text(label)
                .font(value == selection ? CalibreType.bodySemiBold : CalibreType.bodyMedium)
                .foregroundStyle(
                    value == selection ? Color.calibre.foreground : Color.calibre.mutedForeground
                )
                .frame(maxWidth: .infinity, minHeight: Space.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .bottom) {
            if value == selection {
                Rectangle()
                    .fill(Color.calibre.primary)
                    .frame(height: 2)
                    .matchedGeometryEffect(id: "underline", in: underlineNamespace)
            }
        }
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
