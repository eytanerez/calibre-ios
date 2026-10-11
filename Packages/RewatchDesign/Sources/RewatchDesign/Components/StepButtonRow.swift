import SwiftUI

/// The bottom bar of a step-by-step form: Back on the left in a third of the
/// row, Continue on the right in the other two. Going forward is the tap a
/// seller makes most, so it gets the bigger target.
///
/// Give it Back then Continue. Leave Back out (a first step, nowhere to go
/// back to) and Continue takes the whole row; it stays the same view either
/// way, so it slides into its new width instead of being swapped.
///
/// At accessibility text sizes "Continue" outgrows two thirds of a phone, so
/// the pair stacks, each the full width, rather than truncating.
public struct StepButtonRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Space.s))
            : AnyLayout(ThirdsLayout(spacing: Space.m))
        layout { content }
    }
}

/// Two children split one third / two thirds; a lone child takes the row.
struct ThirdsLayout: Layout {
    var spacing: CGFloat

    private func widths(in total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 1 else { return [total] }
        let third = max(total - spacing, 0) / 3
        return [third, third * 2]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? idealWidth(subviews)
        let height = zip(subviews, widths(in: total, count: subviews.count))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
            .max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(in: bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    /// The narrowest row that still gives each child its ideal width.
    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified).width }
        guard ideals.count > 1 else { return ideals.first ?? 0 }
        return max(ideals[0], ideals[1] / 2) * 3 + spacing
    }
}
