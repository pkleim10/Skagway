import AppKit
import SwiftUI

/// Drives the `NSScrollView` backing the grid or list in response to `LibraryViewModel.scrollCommand`
/// (top / bottom / page up / page down). Operates directly on the clip view so it works identically for
/// the SwiftUI `ScrollView` (grid) and the `Table`'s scroll view (list), independent of selection — this
/// keeps the existing fast scrollbar "rip" untouched while adding explicit jump controls.
struct ScrollCommandHandler: NSViewRepresentable {
    enum Mode { case grid, list }
    let command: LibraryViewModel.ScrollCommand?
    let mode: Mode

    final class Coordinator {
        var lastToken: Int = 0
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        // Adopt the current token so a freshly mounted handler (e.g. after a grid/list switch) does not
        // replay the most recent command on appear.
        c.lastToken = command?.token ?? 0
        return c
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let command, command.token != context.coordinator.lastToken else { return }
        context.coordinator.lastToken = command.token
        let kind = command.kind
        let mode = self.mode
        // Defer so any pending layout (version bump, column changes) settles before we read viewport metrics.
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, let scrollView = Self.locateScrollView(from: nsView, mode: mode) else { return }
            Self.apply(kind, to: scrollView)
        }
    }

    // MARK: - Scrolling

    private static func apply(_ kind: LibraryViewModel.ScrollCommand.Kind, to scrollView: NSScrollView) {
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let clipH = clip.bounds.height
        let docHeight = scrollView.documentView?.bounds.height ?? clipH
        // With a top content inset (e.g. content scrolling under the titlebar) the true top scroll position
        // is `-insets.top`, not 0 — scrolling to 0 stops a fraction of a row short. Account for insets at
        // both ends, and size a page off the *visible* height (clip minus insets).
        let minY = -insets.top
        let maxY = max(minY, docHeight + insets.bottom - clipH)
        let visibleH = max(0, clipH - insets.top - insets.bottom)
        // Overlap ~one row's worth so content at the seam stays visible across a page jump.
        let page = visibleH * 0.9
        var y = clip.bounds.origin.y

        switch kind {
        case .top: y = minY
        case .bottom: y = maxY
        case .pageUp: y = max(minY, y - page)
        case .pageDown: y = min(maxY, y + page)
        case .toRow(let index, let total):
            // Map row → document fraction using the *actual* document height (robust to per-cell height
            // variance), then center it. Clamped to the scrollable range.
            let rowTop = (CGFloat(index) / CGFloat(max(1, total))) * docHeight
            y = min(maxY, max(minY, rowTop - visibleH / 2))
        case .retile:
            // Keep the current offset; the nudge-and-restore below forces a re-tile in place.
            break
        }

        let target = NSPoint(x: clip.bounds.origin.x, y: y)
        clip.scroll(to: target)
        scrollView.reflectScrolledClipView(clip)

        // A `.toRow` re-anchor (detail-pane playback exit) or `.retile` (fullscreen exit) often lands on the
        // offset the clip already held, so no bounds-changed fires — and an `NSScrollView` that was frozen
        // or occluded by the fullscreen player never re-tiles, leaving the `LazyVGrid` showing blank cells
        // until the user scrolls. Force a 1pt nudge-and-restore across two runloop ticks so each step posts
        // a bounds-changed notification and the grid re-instantiates its visible cells. Net visible position
        // is unchanged (the bump is sub-row, so the re-tiled region matches the target).
        switch kind {
        case .toRow, .retile:
            let bump = NSPoint(x: target.x, y: target.y > minY ? target.y - 1 : target.y + 1)
            DispatchQueue.main.async { [weak scrollView, weak clip] in
                guard let scrollView, let clip else { return }
                clip.scroll(to: bump)
                scrollView.reflectScrolledClipView(clip)
                DispatchQueue.main.async { [weak scrollView, weak clip] in
                    guard let scrollView, let clip else { return }
                    clip.scroll(to: target)
                    scrollView.reflectScrolledClipView(clip)
                }
            }
        default:
            break
        }
    }

    // MARK: - Locating the scroll view

    private static func locateScrollView(from view: NSView, mode: Mode) -> NSScrollView? {
        switch mode {
        case .grid:
            // The handler sits inside the grid's scroll document; walk up to the enclosing scroll view.
            var current: NSView? = view.superview
            while let v = current {
                if let sv = v as? NSScrollView { return sv }
                current = v.superview
            }
            return nil
        case .list:
            // The handler is a sibling of the Table; find the table with the most rows (the video list,
            // not the sidebar) and use its enclosing scroll view.
            guard let content = view.window?.contentView else { return nil }
            return tableWithMostRows(in: content)?.enclosingScrollView
        }
    }

    private static func tableWithMostRows(in view: NSView) -> NSTableView? {
        var best: NSTableView?
        var bestRows = -1
        func search(_ v: NSView) {
            if let tv = v as? NSTableView, tv.numberOfRows > bestRows {
                best = tv
                bestRows = tv.numberOfRows
            }
            for sub in v.subviews { search(sub) }
        }
        search(view)
        return best
    }
}
