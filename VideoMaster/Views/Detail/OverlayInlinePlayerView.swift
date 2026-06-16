import AVKit
import AppKit
import SwiftUI

/// Self-contained inline player for the floating **overlay** mode (`viewModel.inlineOverlayActive`).
///
/// It mirrors `VideoDetailView`'s inline player — resume position, sidecar subtitles, resume banner, error
/// overlay, and the Space/Shift-Space control counters — but deliberately omits the fullscreen-window
/// routing: fullscreen-start takes precedence over overlay, so this view is only ever mounted when fullscreen
/// is off. It owns its own `AVPlayer` and `SubtitleTrack`, and the browser/detail layout underneath is never
/// resized or frozen, so the grid/list scroll position is preserved across playback.
struct OverlayInlinePlayerView: View {
    let video: Video
    @Bindable var viewModel: LibraryViewModel

    @State private var player: AVPlayer?
    @State private var subtitleTrack = SubtitleTrack()
    @State private var didAutoResume = false
    @State private var resumedFromSeconds: Double?
    @State private var resumeBannerOpacity: Double = 1
    @State private var resumeBannerFadeTask: Task<Void, Never>?
    @State private var playerError: String?
    @State private var statusTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                FloatingPlayerView(player: player, showsFullscreenButton: false)
                SubtitleOverlayContainer(track: subtitleTrack)
                if didAutoResume, let resumeSecs = resumedFromSeconds {
                    resumeOverlay(resumedFromSeconds: resumeSecs) {
                        cancelResumeBannerFadeTask()
                        resumeBannerOpacity = 1
                        didAutoResume = false
                        resumedFromSeconds = nil
                        PlaybackPositionStore.clear(filePath: video.filePath)
                        player.seek(to: .zero) { _ in player.play() }
                    }
                    .opacity(resumeBannerOpacity)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            if let playerError {
                errorOverlay(playerError)
            }
        }
        .task(id: video.id) {
            discoverSidecarSubtitles()
            let seek = viewModel.pendingFilmstripSeekSeconds ?? 0
            viewModel.pendingFilmstripSeekSeconds = nil
            startPlayback(at: seek)
        }
        .onChange(of: viewModel.inlinePlayPauseToggle) { _, _ in
            guard let player else { return }
            if player.timeControlStatus == .playing { player.pause() } else { player.play() }
        }
        .onChange(of: viewModel.inlineRestartFromBeginning) { _, _ in
            guard let player else { return }
            cancelResumeBannerFadeTask()
            didAutoResume = false
            resumedFromSeconds = nil
            resumeBannerOpacity = 1
            PlaybackPositionStore.clear(filePath: video.filePath)
            player.seek(to: .zero) { _ in player.play() }
        }
        .onChange(of: viewModel.fadeResumeBannerAutomatically) { _, enabled in
            if !enabled {
                cancelResumeBannerFadeTask()
                resumeBannerOpacity = 1
            } else if didAutoResume {
                scheduleResumeBannerFadeIfNeeded()
            }
        }
        .onChange(of: viewModel.resumeBannerFadeDelaySeconds) { _, _ in
            if didAutoResume, viewModel.fadeResumeBannerAutomatically {
                scheduleResumeBannerFadeIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            persistPositionIfPossible()
        }
        .onDisappear {
            stopPlayback()
            viewModel.pendingFilmstripSeekSeconds = nil
        }
    }

    // MARK: - Playback lifecycle (no fullscreen routing — see type doc)

    private func startPlayback(at seconds: Double) {
        playerError = nil
        statusTask?.cancel()
        statusTask = Task { @MainActor in
            let asset = AVURLAsset(url: video.url)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            guard !Task.isCancelled else { return }
            guard playable else {
                if FileManager.default.fileExists(atPath: video.filePath) {
                    let ext = video.url.pathExtension.uppercased()
                    playerError = ext.isEmpty
                        ? "This file cannot be played by the built-in player."
                        : "\(ext) files cannot be played by the built-in player."
                } else {
                    playerError = "The file could not be found. The drive may not be mounted."
                }
                viewModel.isPlayingInline = false
                return
            }

            let newPlayer = AVPlayer(url: video.url)
            player = newPlayer
            subtitleTrack.attach(to: newPlayer)

            let resumeSeconds: Double? = {
                guard seconds == 0 else { return nil }
                guard let s = PlaybackPositionStore.loadSeconds(filePath: video.filePath) else { return nil }
                guard s >= 1.0 else { return nil }
                if let duration = video.duration, duration > 0, s >= duration - 5.0 { return nil }
                return s
            }()
            if let resumeSeconds {
                resumeBannerOpacity = 1
                didAutoResume = true
                resumedFromSeconds = resumeSeconds
                newPlayer.seek(to: CMTime(seconds: resumeSeconds, preferredTimescale: 600)) { _ in newPlayer.play() }
                scheduleResumeBannerFadeIfNeeded()
            } else if seconds > 0 {
                cancelResumeBannerFadeTask()
                resumeBannerOpacity = 1
                didAutoResume = false
                resumedFromSeconds = nil
                newPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)) { _ in newPlayer.play() }
            } else {
                cancelResumeBannerFadeTask()
                resumeBannerOpacity = 1
                didAutoResume = false
                resumedFromSeconds = nil
                newPlayer.play()
            }
            Task { await viewModel.recordPlay(for: video) }

            guard let item = newPlayer.currentItem else { return }
            for await status in item.publisher(for: \AVPlayerItem.status).values {
                guard !Task.isCancelled else { return }
                if status == .failed {
                    playerError = item.error?.localizedDescription ?? "The file could not be opened for playback."
                    viewModel.isPlayingInline = false
                    return
                } else if status == .readyToPlay {
                    return
                }
            }
        }
    }

    private func stopPlayback() {
        statusTask?.cancel()
        statusTask = nil
        persistPositionIfPossible()
        cancelResumeBannerFadeTask()
        resumeBannerOpacity = 1
        subtitleTrack.detach()
        player?.pause()
        player = nil
    }

    private func persistPositionIfPossible() {
        guard let player else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return }
        PlaybackPositionStore.saveSeconds(seconds, filePath: video.filePath)
    }

    private func cancelResumeBannerFadeTask() {
        resumeBannerFadeTask?.cancel()
        resumeBannerFadeTask = nil
    }

    private func scheduleResumeBannerFadeIfNeeded() {
        cancelResumeBannerFadeTask()
        guard viewModel.fadeResumeBannerAutomatically else { return }
        let delay = max(1, viewModel.resumeBannerFadeDelaySeconds)
        resumeBannerFadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) { resumeBannerOpacity = 0 }
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            didAutoResume = false
            resumedFromSeconds = nil
            resumeBannerOpacity = 1
        }
    }

    private func discoverSidecarSubtitles() {
        let videoPath = video.filePath
        if let srt = SubtitleTrack.findSidecarSRT(for: video.url) {
            subtitleTrack.load(from: srt)
            Task { await viewModel.setHasSubtitles(videoPath: videoPath, hasSubtitles: true) }
        } else {
            subtitleTrack.unload()
            Task { await viewModel.setHasSubtitles(videoPath: videoPath, hasSubtitles: false) }
        }
    }

    // MARK: - Overlays

    private func resumeOverlay(resumedFromSeconds: Double, startAtBeginning: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text("Resumed at \(formatTimestamp(resumedFromSeconds))")
                .font(.caption)
                .foregroundStyle(.primary)
            Button("Start at beginning", action: startAtBeginning)
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func errorOverlay(_ message: String) -> some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.yellow)
                Text("Playback Failed")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                HStack(spacing: 10) {
                    Button("Open in External Player") {
                        playerError = nil
                        NSWorkspace.shared.open(video.url)
                        Task { await viewModel.recordPlay(for: video) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Dismiss") {
                        playerError = nil
                        viewModel.isPlayingInline = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.white)
                }
            }
            .padding()
        }
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
