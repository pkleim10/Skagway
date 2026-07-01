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

    // Target from the full-window mock + checklist decisions: 5 columns, generous breathing
    private let targetColumns = 5
    private let spacing: CGFloat = 22
    private let outerPadding: CGFloat = 18

    var body: some View {
        // Flexible columns (5 equal, filling the width) instead of GeometryReader-computed fixed
        // widths — visually identical, but dropping the GeometryReader lets SwiftUI show the native
        // scroller reliably, including the legacy (space-reserving) style used when the system is set
        // to "Always" or a mouse is attached. Search/count/toggle/filters live in the thin bar above.
        ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: targetColumns),
                spacing: spacing
            ) {
                ForEach(viewModel.filteredVideos) { video in
                    // Use dedicated elegant card (no inline rename in wall MVP for visual cleanliness)
                    CuratedWallCard(
                        video: video,
                        isSelected: viewModel.selectedVideoIds.contains(video.id),
                        thumbnailService: thumbnailService
                    )
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
                        Divider()
                        Button("Delete") {
                            viewModel.pendingDeleteIds = [video.id]
                            viewModel.showDeleteConfirmation = true
                        }
                    }
                }
            }
            .padding(outerPadding)
        }
        .scrollIndicators(.visible)
        .background(Color.appBackground.opacity(0.4))
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
