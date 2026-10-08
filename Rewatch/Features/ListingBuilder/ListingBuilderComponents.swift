import RewatchDesign
import RewatchKit
import SwiftUI

// MARK: - Motion in the site's register

extension Animation {
    /// The site's eased rise: cubic-bezier(0.22, 1, 0.36, 1), 460 ms.
    static var builderRise: Animation { Motion.ease(0.46) }
}

/// An answer rising into place, staggered by position (the site's `lb-rise`).
/// Under Reduce Motion it simply appears.
struct BuilderRise: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.builderRise.delay(Double(min(index, 8)) * 0.045)) { shown = true }
                }
            }
    }
}

extension View {
    func builderRise(_ index: Int = 0) -> some View {
        modifier(BuilderRise(index: index))
    }
}

/// A copper line drawn under something just written, left to right, which
/// then fades (the site's `lb-inked`): "this was just added". Plays when
/// `stamp` changes; nothing under Reduce Motion.
struct InkUnderline: ViewModifier {
    let stamp: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.rewatch.primary)
                        .frame(width: proxy.size.width * drawn, height: 1.5)
                        .opacity(opacity)
                        .offset(y: proxy.size.height + 3)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: stamp, initial: true) { _, stamp in
                guard stamp != nil, !reduceMotion else { return }
                drawn = 0
                opacity = 1
                withAnimation(Motion.ease(0.63).delay(0.12)) { drawn = 1 }
                withAnimation(.easeOut(duration: 0.6).delay(0.9)) { opacity = 0 }
            }
    }
}

extension View {
    func inkUnderline(_ stamp: String?) -> some View {
        modifier(InkUnderline(stamp: stamp))
    }
}

// MARK: - Money that rolls

/// A server figure that rolls to its new value rather than jumping (the
/// site's `Rolling`), whole dollars when whole and cents when it has them.
struct RollingMoney: View {
    let value: Decimal?
    var font: Font = RewatchType.bodyMedium
    var prefix = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let value {
                Text(prefix + PriceFormatter.format(value))
                    .contentTransition(.numericText(value: NSDecimalNumber(decimal: value).doubleValue))
            } else {
                Text("\u{2014}")
                    .foregroundStyle(Color.rewatch.mutedForeground)
            }
        }
        .font(font)
        .monospacedDigit()
        .animation(reduceMotion ? nil : Motion.ease(0.65), value: value)
    }
}

// MARK: - Choices

/// One answer in a list of answers: a bordered row that fills copper when
/// chosen, with its check popping in (the site's `ChoiceRow`).
struct BuilderChoiceRow: View {
    let label: String
    var detail: String?
    let selected: Bool
    var index = 0
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.play(.selection)
            action()
        } label: {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(RewatchType.bodySemiBold)
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .font(RewatchType.label)
                            .foregroundStyle(Color.rewatch.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                BuilderCheck(on: selected)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .frame(minHeight: Space.touchTarget + 8)
            .background(
                selected ? Color.rewatch.accent.opacity(0.6) : Color.rewatch.card,
                in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(selected ? Color.rewatch.primary : Color.rewatch.border, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.easeFast, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .builderRise(index)
    }
}

/// The round check that pops in on a chosen answer.
struct BuilderCheck: View {
    let on: Bool
    var size: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(on ? Color.clear : Color.rewatch.borderBright, lineWidth: 1)
            if on {
                Circle().fill(Color.rewatch.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(Color.rewatch.primaryForeground)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(on && !reduceMotion ? 1 : 1)
        .transition(.scale)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55), value: on)
        .accessibilityHidden(true)
    }
}

/// A tile that toggles (Box, Papers, Booklets).
struct BuilderToggleTile: View {
    let label: String
    let on: Bool
    var index = 0
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.shared.play(.selection)
            action()
        } label: {
            VStack(alignment: .leading) {
                HStack {
                    Spacer()
                    BuilderCheck(on: on)
                }
                Spacer(minLength: Space.m)
                Text(label)
                    .font(RewatchType.bodySemiBold)
                    .foregroundStyle(Color.rewatch.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.m + 2)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                on ? Color.rewatch.accent.opacity(0.6) : Color.rewatch.card,
                in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(on ? Color.rewatch.primary : Color.rewatch.border, lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(PressableStyle())
        .animation(Motion.easeFast, value: on)
        .accessibilityLabel(label)
        .accessibilityValue(on ? "Included" : "Not included")
        .accessibilityAddTraits(on ? .isSelected : [])
        .builderRise(index)
    }
}

// MARK: - Fields

/// The builder's text box: the site's field, card ground, warm border, copper
/// when focused.
struct BuilderTextBox<Accessory: View>: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect = false
    var submitLabel: SubmitLabel = .next
    var invalid = false
    var focused: Bool
    var onSubmit: () -> Void = {}
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Space.s) {
            accessory()
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.rewatch.placeholder))
                .font(RewatchType.body)
                .foregroundStyle(Color.rewatch.foreground)
                .tint(Color.rewatch.primary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrect)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 50)
        .background(Color.rewatch.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(
                    invalid ? Color.rewatch.destructive : (focused ? Color.rewatch.primary : Color.rewatch.border),
                    lineWidth: focused || invalid ? 1.5 : 1
                )
        )
        .animation(Motion.easeFast, value: focused)
    }
}

extension BuilderTextBox where Accessory == EmptyView {
    init(
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences,
        autocorrect: Bool = false,
        submitLabel: SubmitLabel = .next,
        invalid: Bool = false,
        focused: Bool,
        onSubmit: @escaping () -> Void = {}
    ) {
        self.init(
            placeholder: placeholder,
            text: text,
            keyboard: keyboard,
            capitalization: capitalization,
            autocorrect: autocorrect,
            submitLabel: submitLabel,
            invalid: invalid,
            focused: focused,
            onSubmit: onSubmit,
            accessory: { EmptyView() }
        )
    }
}

/// A field's label: semibold, with "(optional)" in the quieter weight.
struct BuilderFieldLabel: View {
    let text: String
    var optional = false

    var body: some View {
        (Text(text).font(RewatchType.bodySemiBold).foregroundColor(Color.rewatch.foreground)
            + Text(optional ? " (optional)" : "").font(RewatchType.body).foregroundColor(Color.rewatch.mutedForeground))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A short fact from the catalog, as a chip with a check.
struct BuilderSpecChip: View {
    let text: String
    var index = 0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.rewatch.primary)
            Text(text)
                .font(RewatchType.label)
                .foregroundStyle(Color.rewatch.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.rewatch.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.rewatch.border, lineWidth: 1))
        .builderRise(index)
    }
}

/// A callout in the site's tinted band: copper border, soft ground.
struct BuilderNote<Content: View>: View {
    var emphasized = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .background(
                emphasized ? Color.rewatch.accent.opacity(0.55) : Color.rewatch.card,
                in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                    .strokeBorder(emphasized ? Color.rewatch.primary.opacity(0.4) : Color.rewatch.border, lineWidth: 1)
            )
    }
}
