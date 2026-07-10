import SwiftUI

/// Full tag name shown above a truncated chip on hover. Hit-testing is off so the chip
/// underneath stays clickable — unlike `.popover`, which steals the mouse. Includes a
/// downward arrow (popover-style tail) pointing at the chip.
struct TruncatedTagNameTip: View {
    let name: String
    var font: Font = .caption

    private let fill = Color.appSurface
    private let stroke = Color.appTextTertiary.opacity(0.35)

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .font(font)
                .foregroundStyle(Color.appTextPrimary)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )

            // Popover-style tail pointing down at the chip. Fill covers the bubble's bottom
            // stroke; side strokes only (no top edge) so it reads as one continuous bubble.
            PopoverTail()
                .fill(fill)
                .frame(width: 14, height: 8)
                .overlay {
                    PopoverTailSides()
                        .stroke(stroke, lineWidth: 1)
                }
                .offset(y: -1)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .allowsHitTesting(false)
    }
}

/// Downward-pointing triangle used as the tip's popover-style arrow fill.
private struct PopoverTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Only the two slanted edges of the tail — omitting the top edge so it doesn't draw a
/// line across where the triangle meets the bubble.
private struct PopoverTailSides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct TagToggleChip: View {
    let tag: Tag
    let isActive: Bool
    /// Video count for this tag under the currently active filters (excluding the tag filter
    /// itself). Omit to hide the count entirely.
    var count: Int? = nil
    let onToggle: (_ isAdding: Bool) -> Void

    // Tag chips truncate to a single line. When truncated, hover shows the full name in a
    // click-through tip (not `.popover`, which stole the click and blocked selection).
    @State private var isHovering = false
    @State private var visibleTextWidth: CGFloat = 0
    @State private var fullTextWidth: CGFloat = 0

    private var isTruncated: Bool {
        fullTextWidth > visibleTextWidth + 1
    }

    private var showTip: Bool { isHovering && isTruncated }

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .overlay(alignment: .top) {
            if showTip {
                TruncatedTagNameTip(name: tag.name)
                    // Sit just above the chip (bubble + tail); tip ignores hits so the Button still receives clicks.
                    .offset(y: -36)
            }
        }
        .zIndex(showTip ? 100 : 0)
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
