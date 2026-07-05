import SwiftUI

struct TagToggleChip: View {
    let tag: Tag
    let isActive: Bool
    /// Video count for this tag under the currently active filters (excluding the tag filter
    /// itself). Omit to hide the count entirely.
    var count: Int? = nil
    let onToggle: (_ isAdding: Bool) -> Void

    // Tag chips truncate to a single line, so hovering reveals the full name in a small
    // popover that escapes the tag card / drawer clipping bounds. The popover is only offered
    // when the name is actually truncated (see `isTruncated`), so it never just duplicates a
    // name that already fits.
    @State private var isHovering = false
    @State private var visibleTextWidth: CGFloat = 0
    @State private var fullTextWidth: CGFloat = 0

    private var isTruncated: Bool {
        fullTextWidth > visibleTextWidth + 1
    }

    var body: some View {
        Button {
            onToggle(!isActive)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(isActive ? Color.white : Color.appTextSecondary)
                Text(tag.name)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? Color.white : Color.appTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // Measure the rendered (constrained) width...
                    .background(widthReader($visibleTextWidth))
                    // ...against the full intrinsic width of an identical hidden copy.
                    .background(
                        Text(tag.name)
                            .font(.caption)
                            .fontWeight(isActive ? .semibold : .regular)
                            .fixedSize()
                            .hidden()
                            .background(widthReader($fullTextWidth))
                    )
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(isActive ? Color.white.opacity(0.75) : Color.appTextTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.appAccent : Color.appSurface.opacity(0.6))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(
            isPresented: Binding(
                get: { isHovering && isTruncated },
                set: { newValue in if !newValue { isHovering = false } }
            ),
            arrowEdge: .top
        ) {
            // Compact, pill-height overlay showing the complete (untruncated) tag name.
            Text(tag.name)
                .font(.caption)
                .foregroundStyle(Color.appTextPrimary)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }

    /// Reports the rendered width of the view it backs into `width` (kept current on resize).
    private func widthReader(_ width: Binding<CGFloat>) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width.wrappedValue = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newValue in
                    width.wrappedValue = newValue
                }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (
        size: CGSize, positions: [CGPoint]
    ) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
