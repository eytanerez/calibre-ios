import SwiftUI

/// A small (?) beside a label that explains it, in a bubble, when tapped.
///
/// For the facts and fields people get stuck on (a reference number, a grade,
/// a photo angle) and nowhere else: a (?) beside something that explains
/// itself is noise.
///
/// **A bubble on iPhone, not a sheet.** `.popover` on its own becomes a sheet
/// in a compact width; `.presentationCompactAdaptation(.popover)` keeps it the
/// small bubble whose arrow points at the thing it explains, and a tap
/// anywhere outside it closes it.
///
/// **Drawn small, grabbed large.** The glyph grows with Dynamic Type, and its
/// hit area is widened to `Space.touchTarget` without taking any layout space
/// (`a11yExpandTarget`), so the label it sits beside does not move to make
/// room for it. Mind that helper's rule: two of these closer than the growth
/// share the overlap, and the later one wins it.
///
/// **Plain, never glass.** The button style is `.plain`. A bordered or glass
/// style draws a capsule round a 15pt glyph on iOS 26, and a button inside a
/// toolbar already wears the bar's glass, so anything more would be a button
/// drawn inside a button. The bubble's ground is the card token, set with
/// `presentationBackground` so it REPLACES the system's glass rather than
/// sitting on top of it: an explanation is content, and content does not go
/// on glass (see `RewoundGlass`).
///
/// **VoiceOver hears the question, not a glyph.** `label` is required and is
/// what the (?) asks, "What is a reference number?", so a screen-reader user
/// knows what will be explained before they open it.
public struct InfoHint<Explanation: View>: View {
    private let label: String
    private let explanation: Explanation

    @State private var isPresented = false
    /// Sized to sit beside a 13 to 15pt label, and scaled with it.
    @ScaledMetric(relativeTo: .subheadline) private var glyphSize: CGFloat = 15
    /// The bubble's width. It grows with the reader's text size so a sentence
    /// keeps a readable measure, up to `maxBubbleWidth`.
    @ScaledMetric(relativeTo: .body) private var bubbleWidth: CGFloat = 280

    /// Wide enough for a sentence at the largest text sizes, and narrow enough
    /// to leave the popover its margins on the narrowest supported iPhone
    /// (375pt).
    static var maxBubbleWidth: CGFloat { 320 }

    /// - Parameters:
    ///   - label: What VoiceOver says for the (?): the question it answers,
    ///     such as "What is a reference number?".
    ///   - explanation: What the bubble shows.
    public init(_ label: String, @ViewBuilder explanation: () -> Explanation) {
        self.label = label
        self.explanation = explanation()
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: glyphSize, weight: .regular))
                // Copper while its bubble is open, so it is plain which (?)
                // the bubble belongs to.
                .foregroundStyle(isPresented ? Color.rewound.primary : Color.rewound.mutedForeground)
        }
        .buttonStyle(.plain)
        .a11yExpandTarget(currentSize: glyphSize)
        .accessibilityLabel(label)
        .popover(isPresented: $isPresented) {
            InfoHintBubble(width: min(bubbleWidth, Self.maxBubbleWidth)) {
                explanation
            }
        }
    }
}

public extension InfoHint where Explanation == InfoHintText {
    /// A (?) whose bubble holds one plain explanation.
    ///
    /// - Parameters:
    ///   - label: The question VoiceOver says for the (?).
    ///   - message: The explanation.
    init(_ label: String, message: String) {
        self.init(label) { InfoHintText(message) }
    }
}

/// The explanation in a bubble when it is a sentence or two of prose.
public struct InfoHintText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(RewoundType.body)
            .foregroundStyle(Color.rewound.foreground)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The popover's content: a fixed measure, as tall as what it holds, and
/// scrollable when that is taller than the room the popover is given, which at
/// the largest text sizes a longer explanation can be. Without the scroll view
/// the bottom of it would be cut off with no way to reach it.
private struct InfoHintBubble<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: Content

    @State private var contentHeight: CGFloat?

    var body: some View {
        ScrollView(.vertical) {
            content
                .padding(Space.l)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: contentHeight)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color.rewound.card)
    }
}

#Preview("Info hint", traits: .sizeThatFitsLayout) {
    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
        Text("Reference")
            .font(RewoundType.body)
            .foregroundStyle(Color.rewound.primary)
        InfoHint(
            "What is a reference number?",
            message: "The maker's model number for this exact version of the watch."
        )
    }
    .padding(Space.xxl)
    .background(Color.rewound.background)
}
