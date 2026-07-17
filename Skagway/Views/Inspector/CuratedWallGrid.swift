import SwiftUI
import AppKit

// MARK: - Per-card selection state

/// One `@Observable` instance per card. When `isSelected` changes, only that card's
/// body re-runs — not the entire grid. This matches AppKit table behaviour where row
/// highlighting is O(1) rather than O(visible rows).
@Observable
final class CardSelectionState {
    var isSelected: Bool = false
}

/// Plain (non-`@Observable`) store so `CuratedWallGrid.body` can call `state(for:)`
/// without registering a SwiftUI observation dependency on the selection set.
private final class CardSelectionStore {
    private var states: [String: CardSelectionState] = [:]

    func state(for id: String) -> CardSelectionState {
        if let s = states[id] { return s }
        let s = CardSelectionState()
        states[id] = s
        return s
    }

    func sync(to newIds: Set<String>) {
        let current = Set(states.filter { $0.value.isSelected }.keys)
        for id in current.subtracting(newIds) { states[id]?.isSelected = false }
        for id in newIds.subtracting(current) { state(for: id).isSelected = true }
    }
}

/// Process-wide Launch Services cache for "Open With" menus. Filled synchronously on miss so
/// eager `.contextMenu` builders don't re-query LS for every visible card of a new extension.
private enum OpenWithAppCache {
    static var byExtension: [String: [URL]] = [:]
}

// MARK: - Grid

/// The elegant "Wall" browsing surface for the Curated Wall experience.
/// Matches the refined mockups:
/// - Up to 5 columns at typical window widths with generous fixed spacing
/// - Fewer columns when the pane narrows so cards stay at least as wide as they are tall
/// - Clean gallery cards (no dense metadata overload)
/// - No in-wall header or controls — search/count/toggle/filters live in the thin bar above
struct CuratedWallGrid: View {
    @Bindable var viewModel: LibraryViewModel
    let thumbnailService: ThumbnailService
    /// Browser pane width from ContentView's GeometryReader (not ScrollView background —
    /// that measure was unreliable and collapsed the grid to 1 column).
    let containerWidth: CGFloat

    @State private var lastClickedId: String?
    @FocusState private var renameFocus: Bool
    @State private var selectionStore = CardSelectionStore()
    @State private var filmstripVideo: Video?

    // Max from the full-window mock; live `columns` is the source of truth for ↑/↓ row steps
    // in ContentView and for scroll-to-row math below.
    static let maxColumns = 5
    private(set) static var columns = 5
    /// Whole-card floor: thumb (188) + under-thumb row + card padding ≈ 220.
    private static let minCellWidth: CGFloat = 220
    private static let spacing: CGFloat = 22
    private static let outerPadding: CGFloat = 18

    private var spacing: CGFloat { Self.spacing }
    private var outerPadding: CGFloat { Self.outerPadding }

    /// Largest `1...maxColumns` such that flexible cells are at least `minCellWidth` wide.
    /// Invalid/zero widths keep `maxColumns` so a transient layout pass can't pin the grid at 1.
    static func columnCount(forContainerWidth width: CGFloat) -> Int {
        guard width > 1 else { return maxColumns }
        let inner = max(0, width - outerPadding * 2)
        let n = Int((inner + spacing) / (minCellWidth + spacing))
        return min(maxColumns, max(1, n))
    }

    private var columnCount: Int {
        Self.columnCount(forContainerWidth: containerWidth)
    }

    var body: some View {
        // Flexible equal columns fill the width. Column count comes from the parent pane width
        // (equality of the *integer* count is what matters — we never remount with `.id(...)`).
        // No GeometryReader around LazyVGrid content — preserves native scroller behaviour.
        let cols = columnCount
        ScrollView(.vertical) {
            LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols),
                    spacing: spacing
                ) {
                    ForEach(viewModel.filteredVideos) { video in
                        let isRenamingRow = viewModel.renamingVideoId == video.id
                        let isMoving = viewModel.activeMoveVideoIds.contains(video.id)
                        CuratedWallCard(
                            video: video,
                            selectionState: selectionStore.state(for: video.id),
                            isRenaming: isRenamingRow,
                            renameText: isRenamingRow ? $viewModel.renameText : .constant(""),
                            thumbnailService: thumbnailService,
                            isMoving: isMoving,
                            resumeFraction: resumeFraction(for: video),
                            hoverPreviewEnabled: viewModel.gridHoverPreviewEnabled && !viewModel.isPlayingInline,
                            renameFocus: $renameFocus,
                            onCommitRename: { commitRename(video) },
                            onCancelRename: cancelRename,
                            onRenameEditingChanged: { viewModel.isEditingText = $0 }
                        )
                        .id(video.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleSelection(video)
                        }
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            viewModel.isPlayingInline = true
                        })
                        .contextMenu {
                            Button("Play in External Player") { play(video) }
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(video.filePath, inFileViewerRootedAtPath: "")
                            }
                            Button("Rename") {
                                viewModel.renameText = video.fileName
                                viewModel.renamingVideoId = video.id
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : "")
                            Menu("Open With") {
                                // NB: SwiftUI evaluates contextMenu content EAGERLY, per
                                // instantiated card, on every grid update — nothing heavy may
                                // run directly in this builder. Computing the selection URLs
                                // here (via a per-id linear scan, no less) was the 75-second
                                // select-all hang at 12k; it now happens in the button action.
                                // The installed-apps lookup below is a real Launch Services query,
                                // so it goes through `installedAppURLs(for:)`, which caches by file
                                // extension instead of re-querying per card on every render.
                                if ExternalApps.isSubmarineInstalled {
                                    Button("Submarine") { ExternalApps.openInSubmarine(openWithURLs(for: video)) }
                                    Divider()
                                }
                                let appURLs = installedAppURLs(for: video)
                                ForEach(appURLs, id: \.self) { appURL in
                                    Button(appURL.deletingPathExtension().lastPathComponent) {
                                        NSWorkspace.shared.open(
                                            [video.url],
                                            withApplicationAt: appURL,
                                            configuration: NSWorkspace.OpenConfiguration()
                                        )
                                        Task { await viewModel.recordPlay(for: video) }
                                    }
                                }
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : "")
                            Divider()
                            Button("Re-encode to MP4\u{2026}") {
                                if let ffmpeg = viewModel.resolvedFFmpegPath {
                                    let ids = viewModel.selectedVideoIds.contains(video.id)
                                        ? viewModel.selectedVideoIds : [video.id]
                                    let selected = viewModel.filteredVideos.filter { ids.contains($0.id) }
                                    for v in selected { viewModel.reencodeVideo(v, ffmpegPath: ffmpeg) }
                                }
                            }
                            .disabled(isMoving || viewModel.resolvedFFmpegPath == nil)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : (viewModel.resolvedFFmpegPath == nil ? "Requires ffmpeg — configure the path in Settings \u{2192} Tools" : ""))
                            Button("Move Files\u{2026}") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                panel.prompt = "Move Here"
                                panel.message = "Choose a destination folder"
                                if panel.runModal() == .OK, let dest = panel.url {
                                    let ids = viewModel.selectedVideoIds.contains(video.id)
                                        ? viewModel.selectedVideoIds : [video.id]
                                    let selected = viewModel.filteredVideos.filter { ids.contains($0.id) }
                                    Task { await viewModel.moveVideos(selected, to: dest) }
                                }
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move already in progress" : "")
                            Divider()
                            Button("Modify Filmstrip\u{2026}") {
                                filmstripVideo = video
                            }
                            Button("Regenerate Thumbnail") {
                                let ids = viewModel.selectedVideoIds.contains(video.id)
                                    ? viewModel.selectedVideoIds : [video.id]
                                let selected = viewModel.filteredVideos.filter { ids.contains($0.id) }
                                for v in selected {
                                    Task {
                                        if let url = try? await thumbnailService.regenerateThumbnail(for: v) {
                                            await viewModel.setRegeneratedThumbnailPath(videoPath: v.filePath, url: url)
                                        }
                                    }
                                }
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : "")
                            if viewModel.isDuplicate(video.id) {
                                Divider()
                                Button("Not a Duplicate") {
                                    let ids = viewModel.selectedVideoIds.contains(video.id)
                                        ? viewModel.selectedVideoIds : [video.id]
                                    let selected = viewModel.filteredVideos.filter { ids.contains($0.id) }
                                    Task { await viewModel.markNotDuplicate(selected) }
                                }
                                .help("Confirm this isn't a duplicate — it leaves the Duplicates library and stays out unless a genuinely new matching file is added")
                            }
                            Divider()
                            Button("Export Metadata\u{2026}") {
                                let ids = viewModel.selectedVideoIds.contains(video.id)
                                    ? viewModel.selectedVideoIds : [video.id]
                                viewModel.selectedVideoIds = ids
                                viewModel.presentExportMetadata(scope: .selection)
                            }
                            Divider()
                            Button("New Album from Selection\u{2026}") {
                                let ids = viewModel.selectedVideoIds.contains(video.id)
                                    ? viewModel.selectedVideoIds : [video.id]
                                viewModel.presentNewAlbumFromSelection(ids)
                            }
                            if !viewModel.albums.isEmpty {
                                Menu("Add to Album") {
                                    ForEach(viewModel.albums, id: \.listId) { album in
                                        Button(album.name) {
                                            let ids = viewModel.selectedVideoIds.contains(video.id)
                                                ? viewModel.selectedVideoIds : [video.id]
                                            Task { await viewModel.addVideos(paths: ids, toAlbum: album) }
                                        }
                                    }
                                }
                            }
                            if case .collection(let active) = viewModel.sidebarFilter, active.isAlbum {
                                Button("Remove from \"\(active.name)\"") {
                                    let ids = viewModel.selectedVideoIds.contains(video.id)
                                        ? viewModel.selectedVideoIds : [video.id]
                                    Task { await viewModel.removeVideos(paths: ids, fromAlbum: active) }
                                }
                            }
                            Divider()
                            Button("Remove from Library") {
                                let ids = viewModel.selectedVideoIds.contains(video.id)
                                    ? viewModel.selectedVideoIds : [video.id]
                                Task { await viewModel.removeVideosFromLibrary(ids) }
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : "")
                            Button("Delete Video…", role: .destructive) {
                                let ids = viewModel.selectedVideoIds.contains(video.id)
                                    ? viewModel.selectedVideoIds : [video.id]
                                viewModel.pendingDeleteIds = ids
                                viewModel.showDeleteConfirmation = true
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : "")
                        }
                    }
                }
                .padding(outerPadding)
                .background(ScrollCommandHandler(command: viewModel.scrollCommand, mode: .grid))
            }
            .scrollIndicators(.visible)
            .background(Color(red: 3 / 255, green: 13 / 255, blue: 23 / 255))   // #030D17
            .onAppear {
                selectionStore.sync(to: viewModel.selectedVideoIds)
                guard viewModel.scrollToSelectedOnViewSwitch else { return }
                viewModel.scrollToSelectedOnViewSwitch = false
                guard let id = viewModel.lastSelectedVideoId ?? viewModel.selectedVideoIds.first,
                      let index = viewModel.filteredVideos.firstIndex(where: { $0.id == id }) else { return }
                let videos = viewModel.filteredVideos
                let cols = columnCount
                let rowIndex = index / cols
                let totalRows = (videos.count + cols - 1) / cols
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    viewModel.issueScrollCommand(.toRow(index: rowIndex, total: totalRows))
                }
            }
            .onChange(of: viewModel.selectedVideoIds) { _, newIds in
                selectionStore.sync(to: newIds)
            }
            .onChange(of: viewModel.renamingVideoId) { _, id in
                if id != nil {
                    DispatchQueue.main.async { renameFocus = true }
                }
            }
            .onChange(of: viewModel.scrollToVideoId) { _, targetId in
                guard let id = targetId else { return }
                viewModel.scrollToVideoId = nil
                let videos = viewModel.filteredVideos
                guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
                let cols = columnCount
                let rowIndex = index / cols
                let totalRows = (videos.count + cols - 1) / cols
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    viewModel.issueScrollCommand(.toRow(index: rowIndex, total: totalRows))
                }
            }
            .onChange(of: cols, initial: true) { _, n in
                if Self.columns != n { Self.columns = n }
            }
        .sheet(item: $filmstripVideo) { video in
            FilmstripConfigView(
                video: video,
                thumbnailService: thumbnailService,
                defaultRows: viewModel.defaultFilmstripRows,
                defaultColumns: viewModel.defaultFilmstripColumns
            ) { _ in
                viewModel.filmstripRefreshId &+= 1
            }
        }
        .confirmationDialog(
            "Delete \(viewModel.pendingDeleteIds.count == 1 ? "Video" : "\(viewModel.pendingDeleteIds.count) Videos")",
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = viewModel.pendingDeleteIds
                viewModel.pendingDeleteIds = []
                Task { await viewModel.deleteVideos(ids) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingDeleteIds = []
            }
        } message: {
            if viewModel.pendingDeleteIds.count == 1 {
                Text("The file will be moved to Trash.")
            } else {
                Text("\(viewModel.pendingDeleteIds.count) files will be moved to Trash.")
            }
        }
    }

    private func handleSelection(_ video: Video) {
        let flags = NSEvent.modifierFlags
        let newIds: Set<String>
        if flags.contains(.command) {
            var ids = viewModel.selectedVideoIds
            if ids.contains(video.id) { ids.remove(video.id) } else { ids.insert(video.id) }
            lastClickedId = video.id
            newIds = ids
        } else if flags.contains(.shift), let anchor = lastClickedId,
                  let aIdx = viewModel.filteredVideos.firstIndex(where: { $0.id == anchor }),
                  let idx = viewModel.filteredVideos.firstIndex(where: { $0.id == video.id }) {
            let range = min(aIdx, idx)...max(aIdx, idx)
            newIds = Set(range.map { viewModel.filteredVideos[$0].id })
        } else {
            lastClickedId = video.id
            newIds = [video.id]
        }
        // Update card states first (O(1) per-card @Observable update — only the 2 affected
        // cards re-render, not the whole grid), then update the VM one tick later so the
        // inspector re-renders after the selection ring is already visible.
        selectionStore.sync(to: newIds)
        DispatchQueue.main.async { viewModel.selectedVideoIds = newIds }
    }

    private func commitRename(_ video: Video) {
        let newName = viewModel.renameText.trimmingCharacters(in: .whitespaces)
        viewModel.renamingVideoId = nil
        guard !newName.isEmpty, newName != video.fileName else {
            viewModel.renameText = ""
            return
        }
        Task {
            _ = await viewModel.renameVideo(video, to: newName)
            viewModel.renameText = ""
        }
    }

    private func cancelRename() {
        viewModel.renamingVideoId = nil
        viewModel.renameText = ""
    }

    /// Fraction (0...1) of the video already watched, per its saved resume position — drives the
    /// thin progress bar on the card thumbnail, Netflix/Hulu "continue watching" style. `nil` hides
    /// the bar (never played, or finished — the resume position is cleared in both those cases).
    private func resumeFraction(for video: Video) -> Double? {
        _ = viewModel.resumePositionsRevision // establishes the Observation dependency for re-renders
        guard let seconds = PlaybackPositionStore.loadSeconds(filePath: video.filePath),
              let duration = video.duration, duration > 0
        else { return nil }
        return min(max(seconds / duration, 0), 1)
    }

    private func play(_ video: Video) {
        NSWorkspace.shared.open(video.url)
        Task { await viewModel.recordPlay(for: video) }
    }

    /// URLs the "Open With" actions target: the whole selection when the clicked card is part of
    /// a multi-selection, else just the clicked video. Single pass over `filteredVideos` — and
    /// only ever called from a button action, never from the (eagerly evaluated) menu builder.
    private func openWithURLs(for video: Video) -> [URL] {
        let ids = viewModel.selectedVideoIds
        guard ids.count > 1, ids.contains(video.id) else { return [video.url] }
        return viewModel.filteredVideos.filter { ids.contains($0.id) }.map(\.url)
    }

    /// Which apps can open this video's file type — Launch Services, cached per extension in
    /// `OpenWithAppCache` (process-wide). Eager `.contextMenu` builders call this per visible card
    /// on every grid update; a miss fills the cache synchronously so the next card of the same
    /// type is free (async `@State` fill left every new extension re-querying LS for all cells).
    private func installedAppURLs(for video: Video) -> [URL] {
        let ext = video.url.pathExtension.lowercased()
        if let cached = OpenWithAppCache.byExtension[ext] { return cached }
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: video.url)
        OpenWithAppCache.byExtension[ext] = urls
        return urls
    }
}
