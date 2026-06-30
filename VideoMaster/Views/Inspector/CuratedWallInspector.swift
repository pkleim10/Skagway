import AVFoundation
import AVKit
import SwiftUI
import AppKit

/// Dedicated (trimmed for speed-to-visible) Inspector for the Curated Wall variant.
/// We are delivering the left Wall (easiest high-fidelity piece) first per "the easiest one".
/// Still a purpose-built surface: medium hero, title+actions, facts, rating, tall notes, footer.
/// Matches the refined mock visual hierarchy as closely as we can while staying compilable.
struct CuratedWallInspector: View {
    let video: Video?
    @Bindable var viewModel: LibraryViewModel
    let thumbnailService: ThumbnailService

    private var selectedIds: Set<String> { viewModel.selectedVideoIds }

    @State private var hero: NSImage?
    @State private var filmstrip: NSImage?
    @State private var heroPlayer: AVPlayer?
    @State private var notes: String = ""
    private var notesKey: String { "CuratedWall.notes.\(video?.filePath ?? "none")" }

    var body: some View {
        GeometryReader { geo in
            let heroH = max(140, min(geo.size.height * 0.40, 260))

            VStack(spacing: 0) {
                if let v = video {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Medium hero (the visual weight from the mock)
                            heroView(for: v, height: heroH)

                            // Title + icon actions
                            titleAndActions(for: v)

                            // Compact facts
                            factsRow(for: v)

                            // Rating (accented treatment)
                            ratingBlock(for: selectedIds)

                            // Tags (restored)
                            tagsBlock()

                            // Notes — tall first-class editor
                            notesBlock()

                            // Footer
                            footer(for: v)
                        }
                        .padding(14)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appInspectorPanel()
        }
        .frame(minWidth: 300)
        .onAppear { loadNotes() }
        .onChange(of: video?.filePath) { _, _ in
            loadNotes()
            hero = nil
        }
        .onChange(of: notes) { _, val in
            UserDefaults.standard.set(val, forKey: notesKey)
        }
        .onChange(of: viewModel.showThumbnailInDetail) { _, _ in
            filmstrip = nil
            Task { await loadHero() }
        }
        .onChange(of: video?.filePath) { _, _ in
            stopHeroPlayer()
            hero = nil
            filmstrip = nil
        }
        .onChange(of: viewModel.isPlayingInline) { _, isOn in
            if isOn && !viewModel.inlineOverlayActive {
                startLocalHeroPlayer()
            } else if !isOn {
                stopHeroPlayer()
            }
        }
        .task(id: video?.filePath) {
            await loadHero()
        }
    }

    // MARK: - Hero

    private func heroView(for v: Video, height: CGFloat) -> some View {
        let isDetailPlaying = viewModel.isPlayingInline && !viewModel.inlineOverlayActive

        // Core media view with consistent sizing and clipping.
        let media: some View = Group {
            if isDetailPlaying, let p = heroPlayer {
                FloatingPlayerView(player: p)
                    .aspectRatio(16/9, contentMode: .fit)
            } else if viewModel.showThumbnailInDetail {
                if let img = hero {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.appSurface)
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundStyle(Color.appTextTertiary.opacity(0.4))
                        }
                }
            } else if let fs = filmstrip {
                Image(nsImage: fs)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .local) { location in
                                    filmstripSeekAndPlay(at: location, size: geo.size, video: v)
                                }
                        }
                    }
            } else {
                Rectangle()
                    .fill(Color.appSurface)
                    .overlay {
                        Image(systemName: "filmstrip")
                            .font(.largeTitle)
                            .foregroundStyle(Color.appTextTertiary.opacity(0.4))
                    }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appDivider.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            if !isDetailPlaying {
                viewModel.setInlinePlaybackMode(.detailPane)
                viewModel.pendingFilmstripSeekSeconds = nil
                viewModel.isPlayingInline = true
            }
        }

        // Attach controls to the media first (so they hug the image corners),
        // then center the whole decorated media horizontally in the inspector.
        let decorated = media
            .overlay(alignment: .topTrailing) {
                if !isDetailPlaying {
                    HStack(spacing: 2) {
                        Button { viewModel.showThumbnailInDetail = true } label: {
                            Text("Still").font(.caption2)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(viewModel.showThumbnailInDetail ? Color.appAccent.opacity(0.28) : .clear)
                        .clipShape(Capsule())
                        Button { viewModel.showThumbnailInDetail = false } label: {
                            Text("Filmstrip").font(.caption2)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(!viewModel.showThumbnailInDetail ? Color.appAccent.opacity(0.28) : .clear)
                        .clipShape(Capsule())
                    }
                    .padding(3)
                    .background(Material.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isDetailPlaying, let d = v.formattedDuration {
                    Text(d)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(6)
                }
            }

        // Center the (decorated) media in the inspector width.
        return decorated
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func startPlayback(_ v: Video) {
        viewModel.setInlinePlaybackMode(.detailPane)
        viewModel.pendingFilmstripSeekSeconds = nil
        viewModel.isPlayingInline = true
    }

    private func filmstripSeekAndPlay(at location: CGPoint, size: CGSize, video: Video) {
        let w = max(1.0, size.width)
        let progress = max(0.0, min(1.0, location.x / w))
        let dur = video.duration ?? 0.0
        viewModel.pendingFilmstripSeekSeconds = progress * dur
        viewModel.setInlinePlaybackMode(.detailPane)
        viewModel.isPlayingInline = true
    }

    private func loadHero() async {
        guard let v = video else { return }
        if let lo = thumbnailService.loadThumbnail(for: v.filePath) {
            await MainActor.run { hero = lo }
        }
        if viewModel.showThumbnailInDetail {
            if let hi = await thumbnailService.detailPreviewImage(for: v, longEdge: 720) {
                await MainActor.run { hero = hi }
            }
        } else {
            if let img = thumbnailService.loadFilmstrip(for: v.filePath) {
                await MainActor.run { filmstrip = img }
            } else if let img = try? await thumbnailService.generateFilmstrip(for: v) {
                await MainActor.run { filmstrip = img }
            }
        }
    }

    private func startLocalHeroPlayer() {
        guard let url = video?.url else { return }
        stopHeroPlayer()
        let p = AVPlayer(url: url)
        heroPlayer = p
        if let seek = viewModel.pendingFilmstripSeekSeconds, seek >= 0 {
            p.seek(to: CMTime(seconds: seek, preferredTimescale: 600))
            viewModel.pendingFilmstripSeekSeconds = nil
        }
        p.play()
    }

    private func stopHeroPlayer() {
        heroPlayer?.pause()
        heroPlayer = nil
    }

    // MARK: - Title + icon actions

    private func titleAndActions(for v: Video) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(v.fileName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appTextPrimary)
                .lineLimit(2)

            HStack(spacing: 14) {
                Button { viewModel.isPlayingInline = true } label: {
                    Image(systemName: "play.fill")
                }.buttonStyle(.plain).foregroundStyle(Color.appAccent)

                Button {
                    NSWorkspace.shared.selectFile(v.filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }.buttonStyle(.plain)

                Spacer()

                Button {
                    viewModel.setInlinePlaybackMode(.overlay)
                    viewModel.isPlayingInline = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }.buttonStyle(.plain).foregroundStyle(Color.appTextSecondary)
            }
            .font(.callout)
        }
    }

    // MARK: - Compact facts

    private func factsRow(for v: Video) -> some View {
        let parts = [
            v.resolutionLabel ?? "—",
            v.formattedDuration ?? "—",
            v.formattedFileSize
        ]
        return HStack(spacing: 8) {
            ForEach(parts, id: \.self) { t in
                Text(t).font(.caption2).foregroundStyle(Color.appTextSecondary)
            }
        }
    }

    // MARK: - Rating

    private func ratingBlock(for ids: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Rectangle().fill(Color.appAccent).frame(width: 3, height: 12).cornerRadius(2)
                Text("Rating").font(.caption.weight(.semibold)).foregroundStyle(Color.appAccent)
            }
            RatingView(rating: currentRating(for: ids), size: 18) { r in
                viewModel.applyRating(to: ids, rating: r)
                Task { await viewModel.persistRating(for: ids, rating: r) }
            }
        }
    }

    private func currentRating(for ids: Set<String>) -> Int {
        let vals = viewModel.filteredVideos.filter { ids.contains($0.id) }.map(\.rating)
        if let first = vals.first, vals.allSatisfy({ $0 == first }) { return first }
        return video?.rating ?? 0
    }

    // MARK: - Notes (tall editor)

    private func notesBlock() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Rectangle().fill(Color.appAccent).frame(width: 3, height: 12).cornerRadius(2)
                Text("Notes").font(.caption.weight(.semibold)).foregroundStyle(Color.appAccent)
                Spacer()
                Text("\(notes.count)").font(.caption2).foregroundStyle(Color.appTextTertiary)
            }
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .background(Color.appSurface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func loadNotes() {
        notes = UserDefaults.standard.string(forKey: notesKey) ?? ""
    }

    // MARK: - Tags (restored capability)
    private func tagsBlock() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Rectangle().fill(Color.appAccent).frame(width: 3, height: 12).cornerRadius(2)
                Text("Tags").font(.caption.weight(.semibold)).foregroundStyle(Color.appAccent)
                Spacer()
            }

            let sorted = viewModel.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if sorted.isEmpty {
                Text("No tags defined yet.")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary)
            } else {
                // 6-column grid for scannability. Long names truncate with ellipsis.
                // Appearance (capsule, colors, padding) is preserved.
                // Columns stretch to full width; content left-aligned within each column.
                let tagColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)
                LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 4) {
                    ForEach(sorted) { tag in
                        let applied = isTagAppliedToSelection(tag)
                        Button {
                            Task {
                                if applied {
                                    await viewModel.removeTag(tag, fromVideos: selectedIds)
                                } else {
                                    await viewModel.addTag(tag.name, toVideos: selectedIds)
                                }
                                // re-render will pick up via tagsForVideos
                            }
                        } label: {
                            Text(tag.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(applied ? Color.appAccent.opacity(0.18) : Color.appSurface.opacity(0.65))
                                .overlay(
                                    Capsule().stroke(applied ? Color.appAccent.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Quick add new tag (text field inline)
            HStack(spacing: 4) {
                TextField("New tag", text: $newTagText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .onSubmit { createAndApplyNewTag() }
                Button {
                    createAndApplyNewTag()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }

    @State private var newTagText: String = ""

    private func isTagAppliedToSelection(_ tag: Tag) -> Bool {
        let applied = viewModel.tagsForVideos(selectedIds)
        return applied.contains { $0.id == tag.id }
    }

    private func createAndApplyNewTag() {
        let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await viewModel.createTag(name)
            await viewModel.addTag(name, toVideos: selectedIds)
            newTagText = ""
        }
    }

    // MARK: - Footer

    private func footer(for v: Video) -> some View {
        Text(v.filePath)
            .font(.system(size: 9))
            .foregroundStyle(Color.appTextTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(Color.appTextTertiary)
            Text("Select a video on the wall")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
