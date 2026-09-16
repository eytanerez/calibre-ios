import SwiftUI

/// The multiline sibling of `RewoundTextField` — same label, card fill,
/// hairline border, focus ring and inline error, so a notes box never looks
/// like it came from a different app than the field above it.
///
/// Long-form entry is still a form field; the only differences are height and
/// that capitalisation defaults to sentences.
public struct RewoundTextEditor: View {
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
                .font(RewoundType.label)
                .foregroundStyle(Color.rewound.secondaryForeground)
                // The editor below carries `label` as its own accessible name,
                // so leaving this reachable would say it twice.
                .accessibilityHidden(true)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(RewoundType.body)
                        .foregroundStyle(Color.rewound.placeholder)
                        .padding(.horizontal, Space.m + 5)
                        .padding(.vertical, Space.m + 8)
                        .allowsHitTesting(false)
                        // Drawn behind the editor, not inside it: reachable, it
                        // reads as a second element saying the prompt again.
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .font(RewoundType.body)
                    .foregroundStyle(Color.rewound.foreground)
                    .tint(Color.rewound.primary)
                    .textInputAutocapitalization(.sentences)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(Space.m)
                    // A bare `TextEditor` has no title of its own, so without
                    // this it is announced as "text field" and nothing else —
                    // the same name `RewoundTextField` gives its own entry.
                    .accessibilityLabel(label)
                    .accessibilityHint(error ?? "")
            }
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                Color.rewound.card,
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
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.destructive)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if let characterLimit {
                    Text("\(text.count)/\(characterLimit)")
                        .font(RewoundType.caption)
                        .foregroundStyle(Color.rewound.mutedForeground)
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
        if error != nil { return Color.rewound.destructive }
        return focused ? Color.rewound.borderBright : Color.rewound.border
    }

    private var ringColor: Color {
        error != nil ? Color.rewound.destructive : Color.rewound.primary
    }
}
