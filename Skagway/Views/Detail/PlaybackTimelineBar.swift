import AppKit
import SwiftUI

/// Skagway-owned transport: the sole scrubber (AVPlayerView controls are `.none`).
struct PlaybackTimelineBar: View {
    @Bindable var viewModel: LibraryViewModel
    /// When false, the bar is faded (panel hover chrome / full-screen idle).
    var controlsVisible: Bool = true

    /// Row with play / times / scrubber (full player width, normal padding only).
    static let transportRowHeight: CGFloat = 44
    /// Tall hit target for the scrubber (visual track stays a thin capsule centered inside).
    static let scrubHitHeight: CGFloat = 40
    /// Top strip where bookmark diamonds live — double-click bookmarks at the pointer (not playhead).
    static let diamondLaneHeight: CGFloat = 18
    /// Extra height *below* the scrubber line so bottom-corner chrome doesn’t sit on the track.
    static let belowTrackClearance: CGFloat = 20
    static let barHeight: CGFloat = transportRowHeight + belowTrackClearance

    private static let previewWidth: CGFloat = 160
    private static let previewHeight: CGFloat = 90

    @State private var isDragging = false
    @State private var dragSeconds: Double = 0
    @State private var wasPlayingBeforeDrag = false

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
            // Full-width transport — no horizontal chrome reserves.
            HStack(spacing: 10) {
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
            .frame(height: Self.transportRowHeight)

            // Taller zone under the blue scrubber line; panel chrome stays in the corners here.
            Color.clear
                .frame(height: Self.belowTrackClearance)
                .allowsHitTesting(false)
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

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.clear)

                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: max(playheadX, 0), height: 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .position(x: playheadX, y: geo.size.height / 2)

                // Hit targets under the diamond buttons: top = bookmark-at-pointer,
                // bottom = scrub (so double-click doesn’t also seek).
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: Self.diamondLaneHeight)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .help("Double-click to bookmark at pointer")
                        .highPriorityGesture(
                            SpatialTapGesture(count: 2, coordinateSpace: .local)
                                .onEnded { value in
                                    addBookmarkAtTrackX(value.location.x, trackWidth: width)
                                }
                        )

                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture(trackWidth: width))
                }

                // Existing bookmarks stay on top so a single click still jumps.
                ForEach(viewModel.bookmarksForPlayback) { bookmark in
                    bookmarkTick(bookmark, trackWidth: width, trackHeight: geo.size.height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        hoverFraction = fraction
        hoverSeconds = seconds

        let thumbService = viewModel.thumbnailService
        // Instant paint when this scrub step is already cached (no await / no debounce).
        // Keep the previous frame visible until a newer decode arrives — matches YouTube’s feel.
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
                    wasPlayingBeforeDrag = playback.isPlaying
                }
                let fraction = min(max(value.location.x / trackWidth, 0), 1)
                dragSeconds = fraction * duration
                playback.seek(toSeconds: dragSeconds, resumePlayback: false)
                updateScrubHover(x: value.location.x, trackWidth: trackWidth)
            }
            .onEnded { value in
                guard duration > 0 else {
                    isDragging = false
                    return
                }
                let fraction = min(max(value.location.x / trackWidth, 0), 1)
                let seconds = fraction * duration
                let resume = wasPlayingBeforeDrag
                isDragging = false
                playback.seek(toSeconds: seconds, resumePlayback: resume)
            }
    }

    @ViewBuilder
    private func bookmarkTick(_ bookmark: VideoBookmark, trackWidth: CGFloat, trackHeight: CGFloat) -> some View {
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
        .position(x: x, y: max(8, trackHeight / 2 - 10))
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

/// Pass-through mouse tracker. `hitTest` returns nil so SwiftUI drag/seek still works; an
/// `NSTrackingArea` still delivers move/exit while the cursor is over the scrubber.
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
            let point = convert(event.locationInWindow, from: nil)
            onMove?(point)
        }

        override func mouseEntered(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onMove?(point)
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
