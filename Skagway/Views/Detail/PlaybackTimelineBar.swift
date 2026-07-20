import AppKit
import SwiftUI

/// Skagway-owned transport: the sole scrubber (AVPlayerView controls are `.none`).
struct PlaybackTimelineBar: View {
    @Bindable var viewModel: LibraryViewModel
    /// When false, the bar is faded (panel hover chrome / full-screen idle).
    var controlsVisible: Bool = true

    /// Tall hit target for the scrubber. Track sits near the *bottom* of this so chrome below stays close.
    static let scrubHitHeight: CGFloat = 28
    /// Row under the scrubber: play / skip / speed (does not steal scrubber width).
    static let transportControlsHeight: CGFloat = 24
    /// Total bar height = full-width scrubber + controls underneath.
    static let barHeight: CGFloat = scrubHitHeight + transportControlsHeight
    /// Vertical center of the thin scrubber line within `scrubHitHeight` (near the bottom).
    static let trackCenterYFromBottom: CGFloat = 6

    private static let previewWidth: CGFloat = 160
    /// Public so fullscreen chrome can reserve vertical room above the bar.
    static let scrubPreviewHeight: CGFloat = 90
    private static let previewHeight: CGFloat = scrubPreviewHeight

    @State private var isDragging = false
    @State private var dragSeconds: Double = 0
    @State private var wasPlayingBeforeDrag = false
    /// Playhead when a scrub click/drag began — restored if the click turns into a double-click bookmark.
    @State private var playheadBeforeScrub: Double?
    /// Set by double-click-to-bookmark so the scrub gesture doesn’t commit a seek to the pointer.
    @State private var suppressSeekCommit = false

    /// Scrub-hover preview (frame at pointer time), not bookmark popovers.
    @State private var hoverFraction: CGFloat?
    @State private var hoverSeconds: Double?
    @State private var hoverPreview: NSImage?
    @State private var hoverRequestID = 0
    /// Track frame in the bar’s coordinate space (for preview placement above the scrubber).
    @State private var trackFrame: CGRect = .zero

    private var playback: InlinePlaybackController { viewModel.playback }

    private var displaySeconds: Double {
        isDragging ? dragSeconds : playback.currentTimeSeconds
    }

    private var duration: Double {
        max(playback.durationSeconds, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full-width scrubber — only elapsed/duration flank the track (no skip/speed here).
            HStack(spacing: 10) {
                Text(displaySeconds.formattedDuration)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(minWidth: 40, alignment: .trailing)

                timelineTrack
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.scrubHitHeight)

                Text(duration > 0 ? duration.formattedDuration : "–:––")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.appTextSecondary)
                    .frame(minWidth: 40, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.scrubHitHeight)

            // Play / skip / speed sit *below* the track so they never compress it horizontally.
            // Trailing spacer keeps room for FloatingPlayerPanel’s bottom-trailing chrome.
            HStack(spacing: 8) {
                transportIconButton(
                    "gobackward.15",
                    help: "Skip back \(Int(InlinePlaybackController.skipSeconds))s (⌥←)"
                ) {
                    playback.skipBy(-InlinePlaybackController.skipSeconds)
                }

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextPrimary)
                .help(playback.isPlaying ? "Pause" : "Play")

                transportIconButton(
                    "goforward.15",
                    help: "Skip forward \(Int(InlinePlaybackController.skipSeconds))s (⌥→)"
                ) {
                    playback.skipBy(InlinePlaybackController.skipSeconds)
                }

                playbackSpeedMenu

                Spacer(minLength: 72)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.transportControlsHeight)
        }
        // Fixed height — without this, ZStack proposes the full player size and the bar expands.
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .coordinateSpace(name: Self.barSpaceName)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.55), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Preview lives on the bar (not inside the track GeometryReader) so it can rise into
        // the video without being clipped by the track’s layout bounds.
        .overlay(alignment: .topLeading) {
            scrubPreviewOverlay
        }
        .onPreferenceChange(ScrubTrackFrameKey.self) { trackFrame = $0 }
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
    }

    private var playbackSpeedMenu: some View {
        Menu {
            ForEach(InlinePlaybackController.playbackRateChoices, id: \.self) { rate in
                Button {
                    playback.setPlaybackRate(rate)
                } label: {
                    if abs(playback.playbackRate - rate) < 0.001 {
                        Label(
                            InlinePlaybackController.formatPlaybackRate(rate),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(InlinePlaybackController.formatPlaybackRate(rate))
                    }
                }
            }
        } label: {
            Text(InlinePlaybackController.formatPlaybackRate(playback.playbackRate))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.appTextPrimary)
                .frame(minWidth: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Playback speed")
    }

    private func transportIconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appTextPrimary)
        .help(help)
    }

    @ViewBuilder
    private var scrubPreviewOverlay: some View {
        if let hoverFraction, let hoverSeconds, trackFrame.width > 1 {
            let xInBar = trackFrame.minX + hoverFraction * trackFrame.width
            scrubPreviewCard(seconds: hoverSeconds)
                .position(
                    x: clampedPreviewCenterX(xInBar, trackMinX: trackFrame.minX, trackWidth: trackFrame.width),
                    y: -Self.previewHeight / 2 - 10
                )
                .allowsHitTesting(false)
                .zIndex(100)
        }
    }

    private var timelineTrack: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let progress = duration > 0 ? min(max(displaySeconds / duration, 0), 1) : 0
            let playheadX = progress * width
            // Keep the thin track near the bottom of the hit area so transport/chrome sit close under it.
            let trackY = geo.size.height - Self.trackCenterYFromBottom

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.clear)

                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Self.trackCenterYFromBottom - 2)

                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: max(playheadX, 0), height: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, Self.trackCenterYFromBottom - 2)

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .position(x: playheadX, y: trackY)

                // Existing bookmarks stay on top so a single click still jumps.
                ForEach(viewModel.bookmarksForPlayback) { bookmark in
                    bookmarkTick(bookmark, trackWidth: width, trackY: trackY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .help("Click to seek · Double-click to bookmark at pointer")
            // Single-click/drag seeks; double-click bookmarks at the same pointer (playhead restored).
            .gesture(scrubGesture(trackWidth: width))
            .simultaneousGesture(
                SpatialTapGesture(count: 2, coordinateSpace: .local)
                    .onEnded { value in
                        bookmarkFromDoubleClick(x: value.location.x, trackWidth: width)
                    }
            )
            // DragGesture(minimumDistance: 0) often blocks SwiftUI’s onContinuousHover on macOS;
            // AppKit tracking still receives mouse-moved while gestures handle click/drag seek.
            .background {
                ScrubHoverTracker(
                    onMove: { point in
                        updateScrubHover(x: point.x, trackWidth: width)
                    },
                    onExit: {
                        if !isDragging { clearScrubHover() }
                    }
                )
            }
            .background {
                Color.clear.preference(
                    key: ScrubTrackFrameKey.self,
                    value: geo.frame(in: .named(Self.barSpaceName))
                )
            }
        }
    }

    /// Double-click where a single click would seek → bookmark at pointer, leave playhead where it was.
    private func bookmarkFromDoubleClick(x: CGFloat, trackWidth: CGFloat) {
        suppressSeekCommit = true
        let restore = playheadBeforeScrub ?? playback.currentTimeSeconds
        let resume = wasPlayingBeforeDrag
        isDragging = false
        addBookmarkAtTrackX(x, trackWidth: trackWidth)
        playback.seek(toSeconds: restore, resumePlayback: resume)
    }

    /// Bookmark at the scrub-preview / pointer time — does not seek or pause playback.
    private func addBookmarkAtTrackX(_ x: CGFloat, trackWidth: CGFloat) {
        guard duration > 0, let video = playback.currentVideo else { return }
        let fraction = min(max(x / max(trackWidth, 1), 0), 1)
        // Prefer the live hover time (matches the preview card) when present.
        let seconds = hoverSeconds ?? (fraction * duration)
        Task {
            await viewModel.addBookmark(for: video, atSeconds: seconds)
        }
    }

    private func scrubPreviewCard(seconds: Double) -> some View {
        VStack(spacing: 4) {
            Group {
                if let hoverPreview {
                    Image(nsImage: hoverPreview)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.5)
                }
            }
            .frame(width: Self.previewWidth, height: Self.previewHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )

            Text(seconds.formattedDuration)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.65), in: Capsule())
        }
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
    }

    private static let barSpaceName = "PlaybackTimelineBar"

    private func clampedPreviewCenterX(_ x: CGFloat, trackMinX: CGFloat, trackWidth: CGFloat) -> CGFloat {
        let half = Self.previewWidth / 2
        let minX = trackMinX + half
        let maxX = trackMinX + trackWidth - half
        return min(max(x, minX), max(minX, maxX))
    }

    private func updateScrubHover(x: CGFloat, trackWidth: CGFloat) {
        guard duration > 0, let video = playback.currentVideo else {
            clearScrubHover()
            return
        }
        let fraction = min(max(x / trackWidth, 0), 1)
        let seconds = fraction * duration
        // Skip no-op updates — thrashing @State was breaking FloatingPlayerPanel `.onHover` auto-hide.
        if let hoverFraction, abs(hoverFraction - fraction) < 0.001 {
            return
        }
        hoverFraction = fraction
        hoverSeconds = seconds

        let thumbService = viewModel.thumbnailService
        if let cached = thumbService.cachedScrubPreviewImage(for: video, atSeconds: seconds) {
            hoverPreview = cached
        }

        hoverRequestID &+= 1
        let requestID = hoverRequestID
        Task {
            let image = await thumbService.scrubPreviewImage(for: video, atSeconds: seconds)
            guard requestID == hoverRequestID, let image else { return }
            hoverPreview = image
        }
    }

    private func clearScrubHover() {
        hoverRequestID &+= 1
        hoverFraction = nil
        hoverSeconds = nil
        hoverPreview = nil
    }

    private func scrubGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard duration > 0 else { return }
                if !isDragging {
                    isDragging = true
                    suppressSeekCommit = false
                    wasPlayingBeforeDrag = playback.isPlaying
                    playheadBeforeScrub = playback.currentTimeSeconds
                }
                guard !suppressSeekCommit else { return }
                let fraction = min(max(value.location.x / trackWidth, 0), 1)
                dragSeconds = fraction * duration
                playback.seek(toSeconds: dragSeconds, resumePlayback: false)
                // Preview only while actually dragging — a plain click must not leave a thumbnail up.
                let dragged = hypot(value.translation.width, value.translation.height) > 2
                if dragged {
                    updateScrubHover(x: value.location.x, trackWidth: trackWidth)
                }
            }
            .onEnded { value in
                defer {
                    isDragging = false
                    playheadBeforeScrub = nil
                    clearScrubHover()
                }
                guard duration > 0 else { return }
                if suppressSeekCommit {
                    suppressSeekCommit = false
                    return
                }
                let fraction = min(max(value.location.x / trackWidth, 0), 1)
                let seconds = fraction * duration
                let resume = wasPlayingBeforeDrag
                playback.seek(toSeconds: seconds, resumePlayback: resume)
            }
    }

    @ViewBuilder
    private func bookmarkTick(_ bookmark: VideoBookmark, trackWidth: CGFloat, trackY: CGFloat) -> some View {
        let fraction = duration > 0 ? min(max(bookmark.seconds / duration, 0), 1) : 0
        let x = fraction * trackWidth

        Button {
            viewModel.jumpToBookmark(bookmark)
        } label: {
            DiamondTick()
                .fill(Color.appAccent)
                .frame(width: 10, height: 10)
                .contentShape(Rectangle().inset(by: -6))
        }
        .buttonStyle(.plain)
        .help("\(bookmark.title) — \(bookmark.formattedTimecode)")
        .position(x: x, y: max(6, trackY - 10))
    }
}

// MARK: - Track geometry

private struct ScrubTrackFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0 { value = next }
    }
}

// MARK: - Hover tracking (AppKit)

/// Pass-through mouse tracker. `hitTest` returns nil so SwiftUI drag/seek still works;
/// an `NSTrackingArea` delivers move/exit while the cursor is over the scrubber.
/// (No app-wide local monitor — that thrashed SwiftUI state and broke panel hover auto-hide.)
private struct ScrubHoverTracker: NSViewRepresentable {
    var onMove: (CGPoint) -> Void
    var onExit: () -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
    }

    final class TrackerView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onExit: (() -> Void)?
        private var tracking: NSTrackingArea?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
            rebuildTracking()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            rebuildTracking()
        }

        private func rebuildTracking() {
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        override func mouseMoved(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseEntered(with event: NSEvent) {
            onMove?(convert(event.locationInWindow, from: nil))
        }

        override func mouseExited(with event: NSEvent) {
            onExit?()
        }
    }
}

private struct DiamondTick: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
