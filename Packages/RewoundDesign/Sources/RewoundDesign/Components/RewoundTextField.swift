import SwiftUI

/// What a field is *for* — drives the keyboard, autofill contentType,
/// capitalisation and autocorrect in one place so no call site has to
/// remember the four modifiers that make an input behave natively.
public enum CalibreFieldKind: Sendable, Equatable {
    case plain
    case sentence
    case email
    /// Sign-in identifier that accepts either — email keyboard, username autofill.
    case emailOrUsername
    case password
    case newPassword
    case oneTimeCode
    case fullName
    case givenName
    case familyName
    case username
    case phone
    /// Whole numbers — year, quantity, count.
    case integer
    /// Fractional numbers — weight, dimensions.
    case decimal
    /// Prices and offers.
    case money
    case postalCode
    case addressLine1
    case addressLine2
    case city
    case state
    /// Two-letter ISO code — every country field in the app stores "US", not
    /// "United States", so this uppercases as you type.
    case country
    case url
    /// Reference and serial numbers: uppercase, never autocorrected.
    case reference

    var keyboardType: UIKeyboardType {
        switch self {
        case .email, .emailOrUsername: .emailAddress
        case .phone: .phonePad
        case .integer, .oneTimeCode: .numberPad
        case .decimal, .money: .decimalPad
        // Alphanumeric so non-US postal codes stay typable, but digits first.
        case .postalCode: .numbersAndPunctuation
        case .url: .URL
        case .username, .reference: .asciiCapable
        default: .default
        }
    }

    var contentType: UITextContentType? {
        switch self {
        case .email: .emailAddress
        case .emailOrUsername: .username
        case .password: .password
        // Strong-password autofill throws up a system overlay that swallows
        // scripted typing, so UI-test runs opt out of it.
        case .newPassword: Self.suppressesStrongPasswordAutofill ? nil : .newPassword
        case .oneTimeCode: .oneTimeCode
        case .fullName: .name
        case .givenName: .givenName
        case .familyName: .familyName
        case .username: .username
        case .phone: .telephoneNumber
        case .postalCode: .postalCode
        case .addressLine1: .streetAddressLine1
        case .addressLine2: .streetAddressLine2
        case .city: .addressCity
        case .state: .addressState
        case .country: .countryName
        case .url: .URL
        default: nil
        }
    }

    var autocapitalization: TextInputAutocapitalization {
        switch self {
        case .sentence: .sentences
        case .fullName, .givenName, .familyName, .city, .state,
             .addressLine1, .addressLine2: .words
        case .reference, .country: .characters
        case .email, .emailOrUsername, .username, .password, .newPassword,
             .url, .phone, .integer, .decimal, .money, .postalCode,
             .oneTimeCode: .never
        case .plain: .sentences
        }
    }

    var disablesAutocorrection: Bool {
        switch self {
        case .plain, .sentence: false
        default: true
        }
    }

    /// Password kinds mask their entry unless the caller says otherwise.
    var prefersSecureEntry: Bool {
        self == .password || self == .newPassword
    }

    private static var suppressesStrongPasswordAutofill: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uiTesting")
        #else
        return false
        #endif
    }
}

/// Labeled form field — the brand input for checkout, listing details, and
/// auth. Card fill with a hairline border that brightens on focus (plus the
/// 11% primary glow); an inline error line appears gently in 160ms and turns
/// the border destructive. `kind` sets the keyboard, autofill and
/// capitalisation; password kinds render a secure entry with a reveal toggle.
/// Use `accessory` for trailing add-ons (units, "Ref." lookups).
public struct CalibreTextField<Accessory: View>: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let error: String?
    let kind: CalibreFieldKind
    let isSecure: Bool
    let accessory: Accessory

    @FocusState private var focused: Bool
    @State private var revealed = false

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        error: String? = nil,
        kind: CalibreFieldKind = .plain,
        isSecure: Bool? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.error = error
        self.kind = kind
        self.isSecure = isSecure ?? kind.prefersSecureEntry
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(label)
                .font(CalibreType.label)
                .foregroundStyle(Color.calibre.secondaryForeground)
                // The field below carries `label` as its own accessible name, so
                // leaving this reachable would say it twice.
                .accessibilityHidden(true)

            HStack(spacing: Space.s) {
                field
                    .font(CalibreType.body)
                    .foregroundStyle(Color.calibre.foreground)
                    .tint(Color.calibre.primary)
                    .focused($focused)
                    // `TextField("", …)` has no title, so without this the field's
                    // name falls back to the prompt — and 43 call sites pass no
                    // placeholder at all. The rotor, Full Keyboard Access and
                    // Voice Control all address the field directly and get this.
                    .accessibilityLabel(label)
                    .accessibilityHint(error ?? "")

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
                    // No hit-region expansion here, on purpose. This glyph sits
                    // `Space.s` from the secure field with nothing clipping
                    // between them, so a 44pt region would reach back over the
                    // field — and a stray tap there lands on a password entry.
                    // Widening this target needs a layout change, not a
                    // hit-region trick.
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
                RoundedRectangle(cornerRadius: Radius.focusRing, style: .continuous)
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
        let entry = Group {
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

        // `.plain` sets nothing so a call site can still configure the input
        // from the outside — modifiers applied here would outrank theirs,
        // being closer to the leaf.
        if kind == .plain {
            entry
        } else {
            entry
                .keyboardType(kind.keyboardType)
                .textContentType(kind.contentType)
                .textInputAutocapitalization(kind.autocapitalization)
                .autocorrectionDisabled(kind.disablesAutocorrection)
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
        kind: CalibreFieldKind = .plain,
        isSecure: Bool? = nil
    ) {
        self.init(
            label,
            text: text,
            placeholder: placeholder,
            error: error,
            kind: kind,
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
