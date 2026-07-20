import AppKit
import SwiftUI

/// Full-screen chrome: custom timeline only (AVPlayerView controls are `.none`).
/// Shows on mouse move; hides after a short idle delay.
struct FullscreenTimelineOverlay: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            FullscreenMouseMoveCatcher {
                showControls()
            }
            .allowsHitTesting(false)

            PlaybackTimelineBar(viewModel: viewModel, controlsVisible: controlsVisible)
                // Clear the exit-fullscreen button (bottom-trailing).
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { showControls() }
        .onDisappear { hideTask?.cancel() }
    }

    private func showControls() {
        controlsVisible = true
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                controlsVisible = false
            }
        }
    }
}

/// NSHostingView that ignores hits on empty (non-control) areas so the exit button / video stay reachable.
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit == self { return nil }
        return hit
    }
}

/// Forwards mouse-moved events from the full-screen window so chrome can auto-show.
private struct FullscreenMouseMoveCatcher: NSViewRepresentable {
    var onMove: () -> Void

    func makeNSView(context: Context) -> MouseMoveView {
        let view = MouseMoveView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ nsView: MouseMoveView, context: Context) {
        nsView.onMove = onMove
    }

    final class MouseMoveView: NSView {
        var onMove: (() -> Void)?
        private var tracking: NSTrackingArea?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            updateTracking()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            updateTracking()
        }

        private func updateTracking() {
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?()
        }
    }
}
