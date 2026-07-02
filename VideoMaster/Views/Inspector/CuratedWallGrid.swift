import SwiftUI
import AppKit

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
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: Self.columns),
                    spacing: spacing
                ) {
                    ForEach(viewModel.filteredVideos) { video in
                        // Use dedicated elegant card (no inline rename in wall MVP for visual cleanliness)
                        CuratedWallCard(
                            video: video,
                            isSelected: viewModel.selectedVideoIds.contains(video.id),
                            thumbnailService: thumbnailService
                        )
                        .id(video.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            play(video)
                        }
                        .onTapGesture {
                            handleSelection(video)
                        }
                        .contextMenu {
                            Button("Play in External Player") { play(video) }
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(video.filePath, inFileViewerRootedAtPath: "")
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
                            Divider()
                            Button("Re-encode to MP4\u{2026}") {
                                if let ffmpeg = viewModel.resolvedFFmpegPath {
                                    let ids = viewModel.selectedVideoIds.contains(video.id)
                                        ? viewModel.selectedVideoIds : [video.id]
                                    let selected = viewModel.filteredVideos.filter { ids.contains($0.id) }
                                    for v in selected { viewModel.reencodeVideo(v, ffmpegPath: ffmpeg) }
                                }
                            }
                            .disabled(viewModel.resolvedFFmpegPath == nil)
                            .help(viewModel.resolvedFFmpegPath == nil ? "Requires ffmpeg — configure the path in Settings \u{2192} Tools" : "")
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
                            Divider()
                            Button("Remove from Library") {
                                Task { await viewModel.removeVideosFromLibrary([video.id]) }
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.pendingDeleteIds = [video.id]
                                viewModel.showDeleteConfirmation = true
                            }
                        }
                    }
                }
                .padding(outerPadding)
                .background(ScrollCommandHandler(command: viewModel.scrollCommand, mode: .grid))
            }
            .scrollIndicators(.visible)
            .background(Color(red: 3 / 255, green: 13 / 255, blue: 23 / 255))   // #030D17
            .onAppear {
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
            // Keep the keyboard-navigated selection visible. `anchor: nil` does the minimal scroll to
            // reveal the target — cheap for the adjacent ±1/±row arrow moves that drive this.
            .onChange(of: viewModel.scrollToVideoId) { _, targetId in
                guard let id = targetId else { return }
                viewModel.scrollToVideoId = nil
                proxy.scrollTo(id, anchor: nil)
            }
        }
    }

    private func handleSelection(_ video: Video) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if viewModel.selectedVideoIds.contains(video.id) {
                viewModel.selectedVideoIds.remove(video.id)
            } else {
                viewModel.selectedVideoIds.insert(video.id)
            }
            lastClickedId = video.id
        } else if flags.contains(.shift), let anchor = lastClickedId,
                  let aIdx = viewModel.filteredVideos.firstIndex(where: { $0.id == anchor }),
                  let idx = viewModel.filteredVideos.firstIndex(where: { $0.id == video.id }) {
            let range = min(aIdx, idx)...max(aIdx, idx)
            viewModel.selectedVideoIds = Set(range.map { viewModel.filteredVideos[$0].id })
        } else {
            viewModel.selectedVideoIds = [video.id]
            lastClickedId = video.id
        }
    }

    private func play(_ video: Video) {
        NSWorkspace.shared.open(video.url)
        Task { await viewModel.recordPlay(for: video) }
    }
}
