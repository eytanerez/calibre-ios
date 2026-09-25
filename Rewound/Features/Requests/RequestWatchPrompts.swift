import RewoundDesign
import SwiftUI

// MARK: - Home

/// Home's way into a request, set just above the end of the page, and the
/// results grid's under "No watches match".
///
/// The site says this at the foot of the buy grid in the same words. Here it
/// is the design system's tappable band, the construction the seller
/// dashboard uses for its own "go and do this" notices: a title that names
/// the action, a sentence that says why, and a chevron.
struct RequestWatchBand: View {
    /// Under "No watches match" the question has already been answered, so
    /// that band drops it and keeps only what a request does.
    var message = "Can't find what you're looking for? Tell us the reference and our dealers will source it."
    let action: () -> Void

    var body: some View {
        CalloutBand(
            icon: "sparkle.magnifyingglass",
            title: "Request a watch",
            message: message,
            action: {
                Haptics.shared.play(.press)
                action()
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the request form")
        .padding(.horizontal, Space.margin)
    }
}

// MARK: - Results grid

/// The results grid's way into a request: a small glass capsule that floats in
/// at the bottom once somebody has scrolled past the first screen of watches,
/// which is when "it isn't here" starts to be the likely answer.
struct RequestWatchCapsule: View {
    let action: () -> Void

    /// What the grid reserves under its last row so that row, and the
    /// next-page placeholder, can scroll clear of the capsule: its height and
    /// the gap it floats at.
    static let clearance: CGFloat = Space.touchTarget + Space.m

    var body: some View {
        Button {
            Haptics.shared.play(.press)
            action()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.rewound.primary)
                Text(title)
                    .font(RewoundType.label)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: Space.touchTarget)
            .rewoundGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Can't find it? Request a watch")
        .accessibilityHint("Opens the request form")
    }

    /// One line in two weights of ink: the question quieter than the action.
    private var title: AttributedString {
        var question = AttributedString("Can't find it? ")
        question.foregroundColor = Color.rewound.secondaryForeground
        var request = AttributedString("Request a watch")
        request.foregroundColor = Color.rewound.foreground
        return question + request
    }
}

/// Where the reader is in the grid, as far as the capsule cares. Read from
/// `onScrollGeometryChange`, which only reports a change of zone, so a scroll
/// costs nothing until a threshold is crossed.
///
/// The capsule comes in past about one screen of watches, or at the end of the
/// grid, whichever is first: a brand with six watches never scrolls a whole
/// screen, and the end of a short grid is where "it isn't here" is plainest.
/// A grid that fits on the screen is already at its end, so it shows the
/// capsule from the start.
///
/// The show and hide lines are apart on purpose: shown past about a screen,
/// hidden only once the reader is back near the top. A single line would make
/// the capsule flicker in and out as someone scrolled around it.
enum RequestPromptZone: Equatable {
    /// Near the top: the capsule is hidden.
    case top
    /// Between the two lines: the capsule keeps whatever it was doing.
    case between
    /// Past about a screen of results, or at the end of them: the capsule is
    /// shown.
    case deep

    /// How close to the end of the grid counts as having reached it: about
    /// the text block of the last row of cards.
    static let endReach: CGFloat = 120

    static func zone(offset: CGFloat, viewport: CGFloat, distanceToEnd: CGFloat) -> RequestPromptZone {
        guard viewport > 0 else { return .top }
        if offset > viewport * 0.9 || distanceToEnd <= endReach { return .deep }
        if offset < viewport * 0.3 { return .top }
        return .between
    }

    /// Reads the zone off a scroll view's geometry.
    ///
    /// `containerSize` is only the part of the scroll view between its insets
    /// (below the navigation bar, above the tab bar and a brand page's rail),
    /// while `contentOffset` counts from above the top inset. So the offset
    /// from the top of the content adds that inset back, and the distance
    /// left to the end is what the content has beyond the visible part. The
    /// first version measured the end against the whole frame, which put it
    /// about a rail and a tab bar's height further down than the scroll view
    /// can go: a six-watch brand page never reached it.
    static func zone(_ geometry: ScrollGeometry) -> RequestPromptZone {
        let offset = geometry.contentOffset.y + geometry.contentInsets.top
        let viewport = geometry.containerSize.height
        return zone(
            offset: offset,
            viewport: viewport,
            distanceToEnd: geometry.contentSize.height - viewport - offset
        )
    }

    /// The capsule's next state, given the one it is in.
    func shows(whenCurrently showing: Bool) -> Bool {
        switch self {
        case .top: false
        case .between: showing
        case .deep: true
        }
    }
}
