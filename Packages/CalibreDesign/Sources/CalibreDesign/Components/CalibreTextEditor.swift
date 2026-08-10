import SwiftUI

/// The multiline sibling of `CalibreTextField` — same label, card fill,
/// hairline border, focus ring and inline error, so a notes box never looks
/// like it came from a different app than the field above it.
///
/// Long-form entry is still a form field; the only differences are height and
/// that capitalisation defaults to sentences.
public struct CalibreTextEditor: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let minHeight: CGFloat
    /// Shows a live "123/2000" counter when set.
    let characterLimit: Int?

    @FocusState private var focused: Bool

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        error: String? = nil,
        minHeight: CGFloat = 120,
        characterLimit: Int? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.error = error
        self.minHeight = minHeight
        self.characterLimit = characterLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.placeholder)
                        .padding(.horizontal, Space.m + 5)
                        .padding(.vertical, Space.m + 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .tint(Color.calibre.primary)
                    .textInputAutocapitalization(.sentences)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(Space.m)
            }
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                Color.calibre.card,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                    .strokeBorder(ringColor.opacity(0.11), lineWidth: 3)
                    .padding(-3)
                    .opacity(focused ? 1 : 0)
            }

            HStack(alignment: .top) {
                if let error {
                    Text(error)
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.destructive)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if let characterLimit {
                    Text("\(text.count)/\(characterLimit)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                }
            }
        }
        .animation(Motion.easeFast, value: error)
        .animation(Motion.easeFast, value: focused)
    }

    private var borderColor: Color {
        if error != nil { return Color.calibre.destructive }
        return focused ? Color.calibre.borderBright : Color.calibre.border
    }

    private var ringColor: Color {
        error != nil ? Color.calibre.destructive : Color.calibre.primary
    }
}
