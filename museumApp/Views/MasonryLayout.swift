import SwiftUI

/// A Pinterest-style layout: as many columns as fit, and each item goes into whichever
/// column is currently shortest, so cards of different heights pack together without gaps.
struct MasonryLayout: Layout {
    var minimumColumnWidth: CGFloat = 220
    var columnSpacing: CGFloat = 16
    var rowSpacing: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        return CGSize(width: width, height: arrange(in: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(in: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, arrangement.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let columns = Self.columnCount(for: width, minimumColumnWidth: minimumColumnWidth, spacing: columnSpacing)
        let columnWidth = Self.columnWidth(for: width, columns: columns, spacing: columnSpacing)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
        return Self.frames(itemHeights: heights, columns: columns, columnWidth: columnWidth, columnSpacing: columnSpacing, rowSpacing: rowSpacing)
    }

    // MARK: Placement math

    static func columnCount(for width: CGFloat, minimumColumnWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        return max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
    }

    static func columnWidth(for width: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 1)
    }

    /// Puts each item, in order, at the top of the shortest column (the leftmost wins a tie).
    static func frames(
        itemHeights: [CGFloat], columns: Int, columnWidth: CGFloat, columnSpacing: CGFloat, rowSpacing: CGFloat
    ) -> (frames: [CGRect], height: CGFloat) {
        var columnHeights = [CGFloat](repeating: 0, count: max(columns, 1))
        var frames: [CGRect] = []
        for height in itemHeights {
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            frames.append(CGRect(
                x: CGFloat(column) * (columnWidth + columnSpacing),
                y: columnHeights[column],
                width: columnWidth,
                height: height
            ))
            columnHeights[column] += height + rowSpacing
        }
        // The last item in each column doesn't need spacing after it.
        let tallest = columnHeights.max() ?? 0
        return (frames, itemHeights.isEmpty ? 0 : tallest - rowSpacing)
    }
}
