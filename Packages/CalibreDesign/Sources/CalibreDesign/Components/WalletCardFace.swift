import SwiftUI

enum WalletCardMetrics {
    /// ISO ID-1, the proportion every payment card in the world is cut to —
    /// used as a floor rather than a fixed ratio, so a reader who has turned
    /// their text up gets a taller card instead of a clipped number.
    static let aspect: CGFloat = 85.60 / 53.98
}

/// The buyer's saved card, drawn once and used in both places it appears.
///
/// There used to be two answers to "what does a saved card look like": a row
/// with a glyph and two lines of text in settings, and a different row with a
/// radio dot at checkout. They are the same card, so this is the same drawing
/// — picked up at checkout by tapping the card itself, and managed in settings
/// by acting on the card itself. One component, two contexts.
///
/// **This is not `GuaranteeCard`, deliberately.** That one draws the *seller's*
/// card on file: its own stock that does not invert with the theme, a gold
/// contact chip, a lit top edge, a status seam along its base — a depiction of
/// an object standing behind a promise, and never charged for a sale. A wallet
/// card is a control that spends money, so it is painted in the page's own
/// tokens, it inverts with the theme, and it has no chip. Removing one of these
/// detaches a payment method; removing the other takes a seller's listings off
/// the market. They must not look alike.
public struct WalletCardFace<Footer: View>: View {
    /// The two things a saved card is ever for.
    public enum Context {
        /// Checkout: the card is the choice, and tapping it makes it.
        case select(isSelected: Bool, onSelect: () -> Void)
        /// Settings: the card is the thing, and its own controls ride on it.
        case manage
    }

    private let brand: GuaranteeCard.Brand
    private let last4: String?
    private let expiry: String?
    private let isDefault: Bool
    /// A line under the number — why this card cannot be used, or that it is
    /// being checked.
    private let note: String?
    private let noteIsProblem: Bool
    private let context: Context
    private let isDisabled: Bool
    private let footer: Footer

    public init(
        brand: GuaranteeCard.Brand,
        last4: String?,
        expiry: String?,
        isDefault: Bool = false,
        note: String? = nil,
        noteIsProblem: Bool = false,
        isDisabled: Bool = false,
        context: Context,
        @ViewBuilder footer: () -> Footer
    ) {
        self.brand = brand
        self.last4 = last4
        self.expiry = expiry
        self.isDefault = isDefault
        self.note = note
        self.noteIsProblem = noteIsProblem
        self.isDisabled = isDisabled
        self.context = context
        self.footer = footer()
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isSelected: Bool {
        if case .select(let selected, _) = context { return selected }
        return false
    }

    /// The mask is decoration; the four digits are the content. At
    /// accessibility sizes the full mask cannot share a line with them, and
    /// repeating it buys nothing — one group already says the rest is hidden.
    private var maskGroups: String {
        dynamicTypeSize.isAccessibilitySize ? "••••" : "•••• •••• ••••"
    }

    public var body: some View {
        Group {
            switch context {
            case .select(_, let onSelect):
                Button {
                    onSelect()
                } label: {
                    tile
                }
                .buttonStyle(PressableStyle())
                .disabled(isDisabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            case .manage:
                tile
                    .accessibilityElement(children: .contain)
            }
        }
        // §1 by the sorting rule, not by exemption: these render 260–360pt
        // wide, so the short edge — the face's own height at ID-1 — measures
        // 165–225pt, which is the `box` tier. It also lands within a point of
        // the 3.7%-of-width corner an ID-1 card is really cut with, so the
        // ladder and the object agree and no exemption is needed.
        .clipShape(RoundedRectangle(cornerRadius: Radius.box, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.calibre.primary : Color.calibre.border,
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .opacity(isDisabled ? 0.6 : 1)
    }

    private var tile: some View {
        VStack(spacing: 0) {
            face
            if Footer.self != EmptyView.self {
                // The card's own controls, on the card. A removal acted out on
                // the drawing is a removal of the thing being looked at.
                footer
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.calibre.card)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.calibre.border)
                            .frame(height: 1)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var face: some View {
        ZStack(alignment: .topLeading) {
            // Fixes the card proportion at ordinary type sizes. The face is
            // free to exceed it: a card that clips its own number is worse
            // than a card that grows.
            Color.clear.aspectRatio(WalletCardMetrics.aspect, contentMode: .fit)

            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .top, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        // The network in words as well as in the mark: the
                        // drawn wordmarks are decoration, and a brand nobody
                        // has drawn would otherwise arrive as a rectangle.
                        Text(brandLine)
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        if isDefault {
                            Text("DEFAULT")
                                .font(CalibreType.eyebrow)
                                .tracking(CalibreType.eyebrowTracking)
                                .foregroundStyle(Color.calibre.primary)
                                .padding(.horizontal, Space.s)
                                .padding(.vertical, 2)
                                .background(Color.calibre.primary.opacity(0.1), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.calibre.primary.opacity(0.3), lineWidth: 1))
                        }
                    }
                    Spacer(minLength: Space.s)
                    if case .select = context {
                        selectionMark
                    }
                }

                Spacer(minLength: Space.s)

                number

                HStack(alignment: .bottom, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Expires")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                        Text(expiry ?? "—")
                            .font(CalibreType.label)
                            .foregroundStyle(Color.calibre.foreground)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: Space.s)

                    CardBrandMark(
                        brand: brand,
                        height: 20,
                        ink: Color.calibre.foreground,
                        dim: Color.calibre.mutedForeground
                    )
                }

                if let note {
                    Text(note)
                        .font(CalibreType.caption)
                        .foregroundStyle(noteIsProblem ? Color.calibre.destructive : Color.calibre.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            LinearGradient(
                colors: [Color.calibre.card, Color.calibre.secondary, Color.calibre.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        // One quiet sweep of light across the face — printed, not animated.
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.44),
                    .init(color: .white.opacity(0.05), location: 0.49),
                    .init(color: .clear, location: 0.57),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }

    /// The masked number. The four digits are the only ones that exist on the
    /// client and the only ones this ever draws.
    private var number: some View {
        (
            Text(verbatim: maskGroups).foregroundStyle(Color.calibre.mutedForeground)
                + Text(verbatim: " ")
                + Text(verbatim: last4 ?? "••••").foregroundStyle(Color.calibre.foreground)
        )
        .font(.system(size: 17, weight: .medium, design: .monospaced))
        .tracking(1.7)
        // No line limit and no shrinking: at the largest type sizes the number
        // wraps and the card grows around it rather than truncating a figure.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
    }

    /// Selection, said in more than colour: a filled disc with a tick in it,
    /// the word beside it, and the `.isSelected` trait for anything not
    /// looking at pixels. A copper ring on a copper-accented page is not a
    /// strong enough signal on its own.
    @ViewBuilder
    private var selectionMark: some View {
        if isSelected {
            HStack(spacing: Space.xs) {
                Text("SELECTED")
                    .font(CalibreType.eyebrow)
                    .tracking(CalibreType.eyebrowTracking)
                    .foregroundStyle(Color.calibre.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.calibre.primaryForeground)
                    .frame(width: 20, height: 20)
                    .background(Color.calibre.primary, in: Circle())
            }
            .accessibilityHidden(true)
        } else {
            Circle()
                .strokeBorder(Color.calibre.borderBright, lineWidth: 1)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    private var brandLine: String {
        "\(brand.spokenName.capitalized) •••• \(last4 ?? "----")"
    }

    /// What a screen reader hears in place of the drawing.
    private var spoken: String {
        var parts = [brandLine.replacingOccurrences(of: "••••", with: "ending")]
        if let expiry { parts.append("expires \(expiry)") }
        if isDefault { parts.append("default card") }
        if isSelected { parts.append("selected") }
        if let note { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

/// A card with no controls on it — every checkout card, and a settings card
/// whose actions live elsewhere.
public extension WalletCardFace where Footer == EmptyView {
    init(
        brand: GuaranteeCard.Brand,
        last4: String?,
        expiry: String?,
        isDefault: Bool = false,
        note: String? = nil,
        noteIsProblem: Bool = false,
        isDisabled: Bool = false,
        context: Context
    ) {
        self.init(
            brand: brand,
            last4: last4,
            expiry: expiry,
            isDefault: isDefault,
            note: note,
            noteIsProblem: noteIsProblem,
            isDisabled: isDisabled,
            context: context,
            footer: { EmptyView() }
        )
    }
}

// MARK: - Previews

private struct WalletCardPreviewRow: View {
    @State private var selected = "a"

    var body: some View {
        VStack(spacing: Space.l) {
            WalletCardFace(
                brand: .visa,
                last4: "4242",
                expiry: "08 / 27",
                isDefault: true,
                context: .select(isSelected: selected == "a", onSelect: { selected = "a" })
            )
            WalletCardFace(
                brand: .mastercard,
                last4: "5100",
                expiry: "01 / 29",
                context: .select(isSelected: selected == "b", onSelect: { selected = "b" })
            )
            WalletCardFace(
                brand: .amex,
                last4: "0005",
                expiry: "11 / 26",
                context: .manage
            ) {
                Text("Remove")
                    .font(CalibreType.label)
                    .foregroundStyle(Color.calibre.destructive)
            }
        }
        .frame(maxWidth: 340)
    }
}

#Preview("Wallet card — light", traits: .sizeThatFitsLayout) {
    WalletCardPreviewRow()
        .padding(Space.margin)
        .background(Color.calibre.background)
}

#Preview("Wallet card — dark", traits: .sizeThatFitsLayout) {
    WalletCardPreviewRow()
        .padding(Space.margin)
        .background(Color.calibre.background)
        .preferredColorScheme(.dark)
}
