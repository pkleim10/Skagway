import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let skagwayAlbumVideo = UTType(exportedAs: "com.machiilabs.skagway.album-video")
}

/// In-app drag payload for album playlist reorder. Not a file URL — poster/import drops stay separate.
struct AlbumVideoDragItem: Codable, Transferable {
    let videoId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .skagwayAlbumVideo)
    }
}

/// Drag source + drop target for album playlist reorder. No-ops when `enabled` is false so grid
/// cells and list rows can keep a stable modifier chain.
struct AlbumCardReorderModifier: ViewModifier {
    let enabled: Bool
    let videoId: String
    let title: String
    @Binding var targetId: String?
    let onReorder: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(AlbumVideoDragItem(videoId: videoId)) {
                    Text(title)
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .dropDestination(for: AlbumVideoDragItem.self) { items, _ in
                    guard let item = items.first else { return false }
                    onReorder(item.videoId)
                    return true
                } isTargeted: { hovering in
                    if hovering {
                        targetId = videoId
                    } else if targetId == videoId {
                        targetId = nil
                    }
                }
        } else {
            content
        }
    }
}
