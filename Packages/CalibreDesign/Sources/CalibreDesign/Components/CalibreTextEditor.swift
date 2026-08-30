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
                // The editor below carries `label` as its own accessible name,
                // so leaving this reachable would say it twice.
                .accessibilityHidden(true)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(CalibreType.body)
                        .foregroundStyle(Color.calibre.placeholder)
                        .padding(.horizontal, Space.m + 5)
                        .padding(.vertical, Space.m + 8)
                        .allowsHitTesting(false)
                        // Drawn behind the editor, not inside it: reachable, it
                        // reads as a second element saying the prompt again.
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .tint(Color.calibre.primary)
                    .textInputAutocapitalization(.sentences)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(Space.m)
                    // A bare `TextEditor` has no title of its own, so without
                    // this it is announced as "text field" and nothing else —
                    // the same name `CalibreTextField` gives its own entry.
                    .accessibilityLabel(label)
                    .accessibilityHint(error ?? "")
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
                RoundedRectangle(cornerRadius: Radius.focusRing, style: .continuous)
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
                        // "123/2000" is read out as a date. Spelling it out
                        // costs no pixels and stays its own element, so it
                        // never displaces what the editor itself says.
                        .accessibilityLabel("\(text.count) of \(characterLimit) characters")
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
