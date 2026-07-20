import AppKit
import SwiftUI

/// Full-screen transport visibility: show on pointer activity, hide after idle —
/// but **never** while the pointer is over the timeline strip.
@MainActor
final class FullscreenChromeController {
    private(set) var isVisible = true
    /// True while the cursor is inside the timeline hosting view’s frame.
    private(set) var isPointerOverTimeline = false

    private var hideTask: Task<Void, Never>?
    private let idleNanoseconds: UInt64 = 2_500_000_000

    var onVisibilityChange: ((Bool) -> Void)?

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        onVisibilityChange = nil
    }

    /// Pointer moved/dragged somewhere in the fullscreen window.
    func pointerMoved(overTimeline: Bool) {
        isPointerOverTimeline = overTimeline
        reveal()
        if overTimeline {
            // Stay up indefinitely while hovering the transport (no idle hide).
            cancelHideTimer()
        } else {
            scheduleHide()
        }
    }

    /// Pointer left the timeline strip for the video (or exited the window).
    func pointerLeftTimeline() {
        isPointerOverTimeline = false
        if isVisible {
            scheduleHide()
        }
    }

    func reveal() {
        let wasHidden = !isVisible
        isVisible = true
        if wasHidden {
            onVisibilityChange?(true)
        }
    }

    private func scheduleHide() {
        cancelHideTimer()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: idleNanoseconds)
            guard !Task.isCancelled else { return }
            // Final checks — don’t hide under the cursor or after a late reveal.
            guard !self.isPointerOverTimeline else {
                return
            }
            guard self.isVisible else { return }
            self.isVisible = false
            self.onVisibilityChange?(false)
        }
    }

    private func cancelHideTimer() {
        hideTask?.cancel()
        hideTask = nil
    }
}

/// Full-screen chrome: custom timeline only (`AVPlayerView` controls are `.none`).
struct FullscreenTimelineOverlay: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        PlaybackTimelineBar(viewModel: viewModel, controlsVisible: true)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}
