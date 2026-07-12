import SwiftUI

/// The brand search input — secondary fill, magnifier, quiet placeholder,
/// clear button. Focus brightens the border and adds the 11% primary glow
/// ring; no cold blue focus states.
public struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState private var focused: Bool

    public init(text: Binding<String>, placeholder: String = "Search watches") {
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.calibre.mutedForeground)

            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.calibre.placeholder)
            )
            .font(CalibreType.body)
            .foregroundStyle(Color.calibre.foreground)
            .tint(Color.calibre.primary)
            .focused($focused)
            .submitLabel(.search)
            .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.calibre.placeholder)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(minHeight: Space.touchTarget)
        .background(
            Color.calibre.secondary,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(
                    focused ? Color.calibre.borderBright : Color.calibre.border,
                    lineWidth: 1
                )
        )
        .overlay {
            // Focus ring: primary at 11% — a glow, not an outline.
            RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                .strokeBorder(Color.calibre.primary.opacity(0.11), lineWidth: 3)
                .padding(-3)
                .opacity(focused ? 1 : 0)
        }
        .animation(Motion.easeFast, value: focused)
        .animation(Motion.easeFast, value: text.isEmpty)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

private struct SearchFieldPreviewHost: View {
    @State private var query = ""
    @State private var filled = "Submariner 116610LN"

    var body: some View {
        VStack(spacing: Space.l) {
            SearchField(text: $query)
            SearchField(text: $filled)
        }
        .padding()
        .background(Color.calibre.background)
    }
}

#Preview("Search field — light", traits: .sizeThatFitsLayout) {
    SearchFieldPreviewHost()
}

#Preview("Search field — dark", traits: .sizeThatFitsLayout) {
    SearchFieldPreviewHost()
        .preferredColorScheme(.dark)
}
