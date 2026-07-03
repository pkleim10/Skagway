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

// MARK: - Grid

/// The elegant "Wall" browsing surface for the Curated Wall experience.
/// Matches the refined mockups:
/// - ~5 columns at typical window widths with generous fixed spacing
/// - Clean gallery cards (no dense metadata overload)
/// - No in-wall header or controls — search/count/toggle/filters live in the thin bar above
struct CuratedWallGrid: View {
    @Bindable var viewModel: LibraryViewModel
    let thumbnailService: ThumbnailService

    @State private var lastClickedId: String?
    @FocusState private var renameFocus: Bool
    @State private var selectionStore = CardSelectionStore()
    @State private var filmstripVideo: Video?

    // Target from the full-window mock + checklist decisions: 5 columns, generous breathing.
    // `columns` is the single source of truth for the grid width — arrow-key row navigation in
    // ContentView reads it so ↑/↓ move by exactly one row.
    static let columns = 5
    private let spacing: CGFloat = 22
    private let outerPadding: CGFloat = 18

    var body: some View {
        // Flexible columns (5 equal, filling the width) instead of GeometryReader-computed fixed
        // widths — visually identical, but dropping the GeometryReader lets SwiftUI show the native
        // scroller reliably, including the legacy (space-reserving) style used when the system is set
        // to "Always" or a mouse is attached. Search/count/toggle/filters live in the thin bar above.
        ScrollView(.vertical) {
            LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: Self.columns),
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
                            Menu("Open With") {
                                let urlsToSend: [URL] = {
                                    if viewModel.selectedVideoIds.count > 1,
                                       viewModel.selectedVideoIds.contains(video.id) {
                                        return viewModel.selectedVideoIds.compactMap { id in
                                            viewModel.filteredVideos.first(where: { $0.id == id })?.url
                                        }
                                    }
                                    return [video.url]
                                }()
                                if ExternalApps.isSubmarineInstalled {
                                    Button("Submarine") { ExternalApps.openInSubmarine(urlsToSend) }
                                    Divider()
                                }
                                let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: video.url)
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
                            Divider()
                            Button("Remove from Library") {
                                Task { await viewModel.removeVideosFromLibrary([video.id]) }
                            }
                            .disabled(isMoving)
                            .help(isMoving ? "Move in progress — file isn't safe to modify yet" : "")
                            Button("Delete Video…", role: .destructive) {
                                viewModel.pendingDeleteIds = [video.id]
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
                let rowIndex = index / Self.columns
                let totalRows = (videos.count + Self.columns - 1) / Self.columns
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
                let rowIndex = index / Self.columns
                let totalRows = (videos.count + Self.columns - 1) / Self.columns
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
                    viewModel.issueScrollCommand(.toRow(index: rowIndex, total: totalRows))
                }
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

    private func play(_ video: Video) {
        NSWorkspace.shared.open(video.url)
        Task { await viewModel.recordPlay(for: video) }
    }
}
