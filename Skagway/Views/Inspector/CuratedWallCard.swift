import SwiftUI
import AppKit
import AVFoundation

/// Dedicated elegant gallery card for the Curated Wall.
/// Track B card chrome: vignette, title scrim, coherent on-thumb badges, premium selection/hover.
struct CuratedWallCard: View {
    let video: Video
    let selectionState: CardSelectionState
    let isRenaming: Bool
    @Binding var renameText: String
    let thumbnailService: ThumbnailService
    /// True while this video has an active (queued or in-flight) cross-volume move — shows a
    /// spinner badge over the thumbnail so the "frozen" state is visible without right-clicking.
    var isMoving: Bool = false
    /// Fraction (0...1) watched, from the saved resume position — draws a thin progress bar along
    /// the bottom of the thumbnail, Netflix/Hulu "continue watching" style. `nil`/0 hides it.
    var resumeFraction: Double? = nil
    /// When false (e.g. main floating player is open), skip live hover scrub to avoid fighting AVFoundation.
    var hoverPreviewEnabled: Bool = true
    var renameFocus: FocusState<Bool>.Binding
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void
    var onRenameEditingChanged: (Bool) -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false
    @State private var previewPlayer: AVPlayer?
    @State private var previewTask: Task<Void, Never>?
    /// Cancelled + replaced every time the task below (re)starts, so a slow detail-preview fetch from
    /// a *previous* thumbnailPath (e.g. right before a "Regenerate Thumbnail") can't land after a
    /// newer one and overwrite it with a stale image — `.task(id:)`'s auto-cancellation only covers
    /// its own structured body, not this nested unstructured `Task`.
    @State private var detailUpgradeTask: Task<Void, Never>?

    private let thumbHeight: CGFloat = 188
    private let corner: CGFloat = 8

    /// Title on scrim except while renaming or during live hover preview (keep the peek clear).
    private var showChromeTitleOnThumb: Bool {
        !isRenaming && previewPlayer == nil
    }

    var body: some View {
        let isSelected = selectionState.isSelected
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                thumbMedia
                    .frame(height: thumbHeight)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay {
                        // Soft vignette — cheap radial falloff (no blur filters on the hot path).
                        RadialGradient(
                            colors: [.clear, .black.opacity(isHovering ? 0.32 : 0.22)],
                            center: .center,
                            startRadius: 36,
                            endRadius: 150
                        )
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .bottom) {
                        // Title scrim — readable filename on the image itself.
                        if showChromeTitleOnThumb {
                            titleScrim
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        topBadgeCluster
                            .padding(6)
                    }
                    .overlay(alignment: .topLeading) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.appAccent)
                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                                .padding(6)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if let resumeFraction, resumeFraction > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.35))
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.appAccent, Color.yellow.opacity(0.95)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(2, geo.size.width * resumeFraction))
                                }
                            }
                            .frame(height: 3)
                            .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? Color.appAccent.opacity(0.95)
                                    : Color.white.opacity(isHovering ? 0.22 : 0.10),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    }
                    .shadow(
                        color: .black.opacity(isHovering ? 0.28 : (isSelected ? 0.20 : 0.12)),
                        radius: isHovering ? 10 : 6,
                        y: isHovering ? 4 : 2
                    )
                    .scaleEffect(isHovering && !isSelected ? 1.015 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHovering)

                if isMoving {
                    movingOverlay
                }
            }

            // Under-thumb row stays compact (date + stars) so card height is stable with on-scrim titles.
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.appAccent, lineWidth: 1.5)
                        )
                        .focused(renameFocus)
                        .onSubmit { onCommitRename() }
                        .onExitCommand { onCancelRename() }
                        .onAppear { onRenameEditingChanged(true) }
                        .onDisappear { onRenameEditingChanged(false) }
                }

                HStack(spacing: 6) {
                    Text(video.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.appTextTertiary)

                    Spacer(minLength: 0)

                    if video.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(0..<video.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 12 / 255, green: 20 / 255, blue: 30 / 255)
                        : (isHovering ? Color.appSurface.opacity(0.55) : Color.clear)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: corner + 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                .stroke(isSelected ? Color.appAccent.opacity(0.85) : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                startHoverPreviewIfAllowed()
            } else {
                stopHoverPreview()
            }
        }
        .onChange(of: hoverPreviewEnabled) { _, enabled in
            if !enabled { stopHoverPreview() }
        }
        .onChange(of: isMoving) { _, moving in
            if moving { stopHoverPreview() }
        }
        .onDisappear {
            stopHoverPreview()
        }
        .task(id: "\(video.filePath)|\(video.thumbnailPath ?? "")") {
            if let lo = thumbnailService.loadThumbnail(for: video.filePath) {
                thumbnail = lo
            }
            detailUpgradeTask?.cancel()
            detailUpgradeTask = Task {
                if let hi = await thumbnailService.detailPreviewImage(for: video, longEdge: 720) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.thumbnail = hi
                    }
                }
            }
        }
    }

    // MARK: - Chrome pieces (SwiftUI-only; no extra bitmap assets)

    private var thumbMedia: some View {
        Color.appSurface
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(Color.appTextTertiary.opacity(0.5))
                }
            }
            .overlay {
                if let previewPlayer {
                    HoverPreviewPlayerView(player: previewPlayer)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }

    private var titleScrim: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
            .overlay(alignment: .bottomLeading) {
                Text(video.fileName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 7)
            }
        }
        .allowsHitTesting(false)
    }

    private var topBadgeCluster: some View {
        HStack(spacing: 4) {
            if video.hasSubtitles {
                chromeBadge {
                    Image(systemName: "captions.bubble.fill")
                        .font(.system(size: 9, weight: .semibold))
                }
                .help("Subtitles available")
                .accessibilityLabel("Subtitles available")
            }
            if let dur = video.formattedDuration {
                chromeBadge {
                    Text(dur)
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func chromeBadge<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    private var movingOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(0.45))
            VStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Moving…")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(height: thumbHeight)
        .allowsHitTesting(false)
    }

    // MARK: - Hover preview

    private func startHoverPreviewIfAllowed() {
        guard hoverPreviewEnabled, !isMoving, !isRenaming else { return }
        previewTask?.cancel()
        previewTask = nil
        if let previewPlayer {
            previewPlayer.pause()
            previewPlayer.replaceCurrentItem(with: nil)
        }
        previewPlayer = nil

        let token = HoverPreviewExclusive.claim()
        let url = video.url
        let duration = video.duration
        previewTask = Task { @MainActor in
            await HoverPreviewPlayback.run(
                url: url,
                knownDuration: duration,
                token: token,
                assignPlayer: { player in
                    self.previewPlayer = player
                }
            )
        }
    }

    private func stopHoverPreview() {
        previewTask?.cancel()
        previewTask = nil
        if let previewPlayer {
            previewPlayer.pause()
            previewPlayer.replaceCurrentItem(with: nil)
        }
        previewPlayer = nil
    }
}
