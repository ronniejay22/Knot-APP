//
//  FlowLayout.swift
//  Knot
//
//  Created on February 7, 2026.
//  Step 3.3: Reusable flow/wrap layout for chip grids.
//  Used by InterestsView, DislikesView, and VibesView.
//

import SwiftUI

/// A custom `Layout` that arranges subviews in a wrapping flow,
/// similar to CSS `flex-wrap: wrap`. Items are placed left-to-right
/// and wrap to the next row when they exceed the available width.
///
/// Usage:
/// ```swift
/// FlowLayout(spacing: 8) {
///     ForEach(items) { item in
///         ChipView(text: item.name)
///     }
/// }
/// ```
struct FlowLayout: Layout {
    /// Horizontal spacing between items in the same row.
    var horizontalSpacing: CGFloat = 8

    /// Vertical spacing between rows.
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let result = computeLayout(
            subviews: subviews,
            containerWidth: proposal.width ?? .infinity
        )
        return result.totalSize
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = computeLayout(
            subviews: subviews,
            containerWidth: bounds.width
        )

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    // MARK: - Layout Computation

    private struct LayoutResult {
        var positions: [CGPoint]
        var sizes: [CGSize]
        var totalSize: CGSize
    }

    private func computeLayout(
        subviews: Subviews,
        containerWidth: CGFloat
    ) -> LayoutResult {
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            // Wrap to next row if this item doesn't fit
            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
            maxWidth = max(maxWidth, currentX - horizontalSpacing)
        }

        let totalHeight = currentY + rowHeight
        return LayoutResult(
            positions: positions,
            sizes: sizes,
            totalSize: CGSize(width: maxWidth, height: totalHeight)
        )
    }
}
