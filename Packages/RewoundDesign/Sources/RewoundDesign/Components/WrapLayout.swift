import SwiftUI

/// Lays its children out left to right and starts a new line when the next
/// one would not fit, which `HStack` does not do.
///
/// For short runs of chips and facts whose count and widths change with the
/// data: a condition card's part chips, a listing card's facts, a row of
/// answers. A horizontal scroller hides whatever falls past the edge and an
/// `HStack` squeezes it; this keeps every item whole and visible.
///
/// No child is ever proposed more than the full line: one wider than that (a
/// long phrase at an accessibility text size) is given the line to itself and
/// wraps inside it, rather than running off the edge.
public struct WrapLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = Space.s, lineSpacing: CGFloat = Space.s) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for item in line.items {
                // Items on one line share its first baseline where they have
                // one, so a pill and the words after it read as one line.
                let offset = line.baseline - item.baseline
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + offset),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
        let baseline: CGFloat
    }

    private struct Line {
        var items: [Item] = []
        var width: CGFloat = 0
        var baseline: CGFloat = 0
        var descent: CGFloat = 0

        var height: CGFloat { baseline + descent }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let subview = subviews[index]
            let ideal = subview.sizeThatFits(.unspecified)
            let size = ideal.width > maxWidth
                ? subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                : ideal
            let dimensions = subview.dimensions(in: ProposedViewSize(size))
            let baseline = dimensions[VerticalAlignment.firstTextBaseline]
            let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty, needed > maxWidth {
                lines.append(current)
                current = Line()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.items.append(Item(index: index, size: size, baseline: baseline))
            current.baseline = max(current.baseline, baseline)
            current.descent = max(current.descent, size.height - baseline)
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }
}
