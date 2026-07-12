import SwiftUI

/// Labeled form field — the brand input for checkout, listing details, and
/// auth. Card fill with a hairline border that brightens on focus (plus the
/// 11% primary glow); an inline error line appears gently in 160ms and turns
/// the border destructive. `isSecure` renders a secure entry with a reveal
/// toggle. Use `accessory` for trailing add-ons (units, "Ref." lookups).
public struct CalibreTextField<Accessory: View>: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let isSecure: Bool
    let accessory: Accessory

    @FocusState private var focused: Bool
    @State private var revealed = false

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        error: String? = nil,
        isSecure: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.error = error
        self.isSecure = isSecure
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)

            HStack(spacing: Space.s) {
                field
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .tint(Color.calibre.primary)
                    .focused($focused)

                if isSecure {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.calibre.mutedForeground)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(revealed ? "Hide password" : "Show password")
                }

                accessory
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: Space.touchTarget)
            .background(
                Color.calibre.card,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .overlay {
                // Focus ring: 11% glow — destructive-tinted while in error.
                RoundedRectangle(cornerRadius: Radius.control + 3, style: .continuous)
                    .strokeBorder(ringColor.opacity(0.11), lineWidth: 3)
                    .padding(-3)
                    .opacity(focused ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if let error {
                Text(error)
                    .font(CalibreType.caption)
                    .foregroundStyle(Color.calibre.destructive)
                    .transition(.opacity.combined(with: .offset(y: -3)))
            }
        }
        .animation(Motion.easeFast, value: error)
        .animation(Motion.easeFast, value: focused)
    }

    @ViewBuilder
    private var field: some View {
        if isSecure && !revealed {
            SecureField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.calibre.placeholder)
            )
        } else {
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.calibre.placeholder)
            )
        }
    }

    private var borderColor: Color {
        if error != nil { return Color.calibre.destructive }
        return focused ? Color.calibre.borderBright : Color.calibre.border
    }

    private var ringColor: Color {
        error != nil ? Color.calibre.destructive : Color.calibre.primary
    }
}

public extension CalibreTextField where Accessory == EmptyView {
    /// Field without a trailing accessory.
    init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        error: String? = nil,
        isSecure: Bool = false
    ) {
        self.init(
            label,
            text: text,
            placeholder: placeholder,
            error: error,
            isSecure: isSecure
        ) { EmptyView() }
    }
}

private struct CalibreTextFieldPreviewHost: View {
    @State private var reference = ""
    @State private var email = "not-an-email"
    @State private var password = "hunter2!"

    var body: some View {
        VStack(spacing: Space.xl) {
            CalibreTextField(
                "Reference number",
                text: $reference,
                placeholder: "e.g. 116610LN"
            ) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.calibre.primary)
            }
            CalibreTextField(
                "Email",
                text: $email,
                placeholder: "you@example.com",
                error: "Enter a valid email address."
            )
            CalibreTextField(
                "Password",
                text: $password,
                isSecure: true
            )
        }
        .padding()
        .background(Color.calibre.background)
    }
}

#Preview("Text fields — light", traits: .sizeThatFitsLayout) {
    CalibreTextFieldPreviewHost()
}

#Preview("Text fields — dark", traits: .sizeThatFitsLayout) {
    CalibreTextFieldPreviewHost()
        .preferredColorScheme(.dark)
}
