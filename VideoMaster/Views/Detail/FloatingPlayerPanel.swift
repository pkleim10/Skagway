import SwiftUI

/// The single resizable, movable player surface. Positioned within the content area overlay;
/// Compact snaps to the top-right inspector footprint, otherwise the panel floats freely.
/// The lower-left handle resizes (top + right edges stay pinned). The title bar drags to reposition.
/// Size and position are persisted to `viewModel` on release.
struct FloatingPlayerPanel: View {
    let video: Video
    @Bindable var viewModel: LibraryViewModel
    /// Size of the content area this panel floats in (from the caller's GeometryReader).
    let available: CGSize

    @State private var dragSize: CGSize?
    @State private var dragStartSize: CGSize?
    /// Live center point during title-bar or resize drag. Nil outside a drag.
    @State private var dragCenter: CGPoint?
    /// Center snapshot at the start of any drag, used to compute the delta.
    @State private var dragStartCenter: CGPoint?

    /// The title bar (drag) and size-control buttons only show while the mouse is over the
    /// panel, fading out ~1s after it leaves (the resize handle stays always visible).
    @State private var controlsVisible = false
    @State private var controlsHideTask: Task<Void, Never>?

    private let minSize = CGSize(width: 240, height: 140)
    private let outerPadding: CGFloat = 12

    // MARK: - Size helpers

    private var compactSize: CGSize {
        let detailWidth = CGFloat(viewModel.browsingLayout.detailColumnWidth(for: viewModel.viewMode))
        // Matches the Inspector's user-adjustable, persisted hero height exactly (see
        // `LibraryViewModel.inspectorHeroHeight`), so Compact always snaps to whatever footprint
        // the user has actually set the hero to, not an independently-recomputed guess. Prefers
        // the live drag value (if the hero's resize handle is actively being dragged) so an
        // already-open compact player tracks the resize in realtime instead of only snapping to
        // the new size once the drag ends.
        let heroHeight = viewModel.inspectorHeroLiveHeight ?? viewModel.inspectorHeroHeight
        let w = min(max(detailWidth - 24, minSize.width), maxSize.width)
        let h = min(max(heroHeight + 4, minSize.height), maxSize.height)
        return CGSize(width: w, height: h)
    }

    private var maxSize: CGSize {
        CGSize(width: max(minSize.width, available.width - outerPadding * 2),
               height: max(minSize.height, available.height - outerPadding * 2))
    }

    private func clampSize(_ s: CGSize) -> CGSize {
        CGSize(width: min(max(s.width, minSize.width), maxSize.width),
               height: min(max(s.height, minSize.height), maxSize.height))
    }

    private var size: CGSize {
        if let dragSize { return dragSize }
        if viewModel.playerSizeIsCompact { return compactSize }
        return clampSize(viewModel.playerFloatingSize)
    }

    // MARK: - Position helpers

    /// Full frame size of the panel including its outer padding on all sides.
    private var totalSize: CGSize {
        CGSize(width: size.width + 2 * outerPadding, height: size.height + 2 * outerPadding)
    }

    /// Clamp a proposed center point so the entire panel stays within the available area.
    private func clampCenter(_ c: CGPoint, totalW: CGFloat, totalH: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(c.x, totalW / 2), available.width  - totalW / 2),
            y: min(max(c.y, totalH / 2), available.height - totalH / 2)
        )
    }

    /// Default center for the current mode: top-right for Compact, centered for S/M/L.
    private var defaultCenter: CGPoint {
        let tw = totalSize.width; let th = totalSize.height
        if viewModel.playerSizeIsCompact {
            return CGPoint(x: available.width - tw / 2, y: th / 2)
        }
        return CGPoint(x: available.width / 2, y: available.height / 2)
    }

    /// Committed center from the ViewModel (or the mode default), clamped to current bounds.
    private var baseCenter: CGPoint {
        if viewModel.playerSizeIsCompact { return defaultCenter }
        let tw = totalSize.width; let th = totalSize.height
        let raw = viewModel.playerFloatingPosition ?? defaultCenter
        return clampCenter(raw, totalW: tw, totalH: th)
    }

    /// Effective center used for positioning: live drag value if dragging, otherwise the base.
    private var effectiveCenter: CGPoint {
        dragCenter ?? baseCenter
    }

    // MARK: - Body

    var body: some View {
        Color.clear
            .overlay {
                panelContent
                    .position(effectiveCenter)
            }
    }

    // MARK: - Panel content

    private var panelContent: some View {
        OverlayInlinePlayerView(video: video, viewModel: viewModel, controlsVisible: controlsVisible)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                sizeControls
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
            }
            .overlay(alignment: .bottomLeading)  { resizeHandle }
            .overlay(alignment: .top)            {
                titleBarDragArea
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
            }
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
            .padding(outerPadding)
            .onHover { hovering in
                controlsHideTask?.cancel()
                if hovering {
                    controlsHideTask = nil
                    withAnimation(.easeInOut(duration: 0.15)) { controlsVisible = true }
                } else {
                    controlsHideTask = Task {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
                    }
                }
            }
    }

    // MARK: - Title bar drag

    /// Transparent 30 pt (25% larger than the original 24pt) overlay on the header; drag moves
    /// the panel. Only hit-testable while `controlsVisible` (see `panelContent`), which also means
    /// it's never active unless the mouse is already over the panel to begin with.
    private var titleBarDragArea: some View {
        Color.clear
            .frame(height: 30 + outerPadding)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartCenter == nil {
                            dragStartCenter = baseCenter   // snapshot before exiting compact
                            if viewModel.playerSizeIsCompact {
                                // Freeze the current (compact) size as the new floating size so
                                // dragging doesn't also cause a visual resize jump.
                                viewModel.playerFloatingSize = size
                                viewModel.playerSizeIsCompact = false
                                viewModel.playerLastWasFullScreen = false
                            }
                        }
                        let tw = totalSize.width; let th = totalSize.height
                        let proposed = CGPoint(
                            x: dragStartCenter!.x + value.translation.width,
                            y: dragStartCenter!.y + value.translation.height
                        )
                        dragCenter = clampCenter(proposed, totalW: tw, totalH: th)
                    }
                    .onEnded { _ in
                        if let c = dragCenter { viewModel.playerFloatingPosition = c }
                        dragCenter = nil
                        dragStartCenter = nil
                    }
            )
            .help("Drag to move")
    }

    // MARK: - Size controls

    /// The three semantic size states; everything in between (a manual drag) is the resize
    /// handle's job — Windowed just recalls whatever size/position that last produced.
    private var sizeControls: some View {
        HStack(spacing: 4) {
            iconButton("camera.viewfinder", help: "Make thumbnail from current frame (⌥⌘M)") {
                viewModel.playback.makeThumbnailFromCurrentFrame()
            }
            iconButton("rectangle", help: "Compact (follows the inspector width) (⌃⌘C)") {
                viewModel.playerSizeIsCompact = true
                viewModel.playerLastWasFullScreen = false
                viewModel.playerFloatingPosition = nil   // compact always anchors top-right
            }
            iconButton("macwindow", help: "Windowed — last used size (⌃⌘W)") {
                viewModel.playerSizeIsCompact = false
                viewModel.playerLastWasFullScreen = false
            }
            iconButton("arrow.up.left.and.arrow.down.right", help: "Full screen (⌃⌘F)") {
                viewModel.isPlayerFullScreen = true
            }
        }
        .padding(8)
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                // 14pt vs. the original .caption2 (~11pt) — 25% larger, matching the drag bar.
                .font(.system(size: 14, weight: .semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appTextSecondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.appSurface.opacity(0.85), in: Capsule())
        .help(help)
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.appTextSecondary)
            .padding(6)
            .background(Color.appSurface.opacity(0.85), in: Circle())
            .padding(8)
            .contentShape(Rectangle())
            .gesture(
                // Global coordinate space avoids feedback: the handle moves as the panel resizes.
                // Round to whole points to avoid sub-pixel thrash of the live-resizing player layer.
                // Center is updated each frame to maintain the top-right corner of the panel.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartSize == nil {
                            dragStartSize = size
                            dragStartCenter = effectiveCenter   // snapshot before exiting compact
                            viewModel.playerSizeIsCompact = false
                            viewModel.playerLastWasFullScreen = false
                        }
                        let baseSize   = dragStartSize!
                        let startCtr   = dragStartCenter!
                        let proposed   = CGSize(
                            width:  (baseSize.width  - value.translation.width ).rounded(),
                            height: (baseSize.height + value.translation.height).rounded()
                        )
                        let newSize   = clampSize(proposed)
                        let newTotalW = newSize.width  + 2 * outerPadding
                        let newTotalH = newSize.height + 2 * outerPadding
                        let baseTotalW = baseSize.width  + 2 * outerPadding
                        let baseTotalH = baseSize.height + 2 * outerPadding
                        // Keep the top-right corner fixed while dragging the bottom-left handle.
                        let topRightX = startCtr.x + baseTotalW / 2
                        let topRightY = startCtr.y - baseTotalH / 2
                        let newCtr    = CGPoint(x: topRightX - newTotalW / 2,
                                                y: topRightY + newTotalH / 2)
                        dragSize   = newSize
                        dragCenter = clampCenter(newCtr, totalW: newTotalW, totalH: newTotalH)
                    }
                    .onEnded { _ in
                        if let s = dragSize   { viewModel.playerFloatingSize     = s }
                        if let c = dragCenter { viewModel.playerFloatingPosition = c }
                        dragSize        = nil; dragStartSize   = nil
                        dragCenter      = nil; dragStartCenter  = nil
                    }
            )
            .help("Drag to resize")
    }
}
