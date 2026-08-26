import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pasteboard payload for in-app album reorder. Uses public UTF-8 text so macOS SwiftUI
/// `onDrag` / `onDrop` actually deliver (a private exported UTType never matched).
enum AlbumReorderPasteboard {
    static let prefix = "skagway-album-video:"
    static let dropTypes: [UTType] = [.utf8PlainText, .plainText, .text]

    static func payload(videoId: String) -> String {
        prefix + videoId
    }

    static func videoId(from payload: String) -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }
        let id = String(trimmed.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    static func itemProvider(videoId: String) -> NSItemProvider {
        NSItemProvider(object: payload(videoId: videoId) as NSString)
    }

    /// Returns true if this drop looks like an album reorder (so file/poster drops can still run).
    static func isAlbumReorder(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            dropTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }
    }

    static func loadVideoId(from providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
        guard let provider = providers.first(where: { provider in
            dropTypes.contains { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        }) else {
            completion(nil)
            return
        }
        let identifiers = dropTypes.map(\.identifier) + [NSPasteboard.PasteboardType.string.rawValue]
        func tryIdentifier(_ index: Int) {
            if index >= identifiers.count {
                provider.loadObject(ofClass: NSString.self) { object, _ in
                    let id = (object as? NSString).flatMap { videoId(from: $0 as String) }
                    DispatchQueue.main.async { completion(id) }
                }
                return
            }
            let identifier = identifiers[index]
            guard provider.hasItemConformingToTypeIdentifier(identifier) else {
                tryIdentifier(index + 1)
                return
            }
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                if let id = videoId(fromLoaded: item) {
                    DispatchQueue.main.async { completion(id) }
                } else {
                    tryIdentifier(index + 1)
                }
            }
        }
        tryIdentifier(0)
    }

    private static func videoId(fromLoaded item: Any?) -> String? {
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return videoId(from: string)
        }
        if let string = item as? String {
            return videoId(from: string)
        }
        if let string = item as? NSString {
            return videoId(from: string as String)
        }
        if let url = item as? URL {
            return videoId(from: url.absoluteString)
        }
        return nil
    }
}

/// Grip + drop target for album playlist reorder. Drag starts from the handle so card tap-to-select
/// is not fighting the drag recognizer (`.draggable` on the whole card was a no-op on macOS).
struct AlbumCardReorderModifier: ViewModifier {
    let enabled: Bool
    let videoId: String
    let title: String
    @Binding var targetId: String?
    let onReorder: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    AlbumReorderPasteboard.itemProvider(videoId: videoId)
                } preview: {
                    Text(title)
                        .font(.caption)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .onDrop(of: AlbumReorderPasteboard.dropTypes, isTargeted: Binding(
                    get: { targetId == videoId },
                    set: { hovering in
                        if hovering {
                            targetId = videoId
                        } else if targetId == videoId {
                            targetId = nil
                        }
                    }
                )) { providers in
                    guard AlbumReorderPasteboard.isAlbumReorder(providers) else { return false }
                    AlbumReorderPasteboard.loadVideoId(from: providers) { draggedId in
                        guard let draggedId else { return }
                        onReorder(draggedId)
                    }
                    return true
                }
                .overlay(alignment: .topLeading) {
                    AlbumReorderGrip(videoId: videoId, title: title)
                }
        } else {
            content
        }
    }
}

/// Dedicated drag source. Isolated from tap/selection so a click-drag actually begins a session.
private struct AlbumReorderGrip: View {
    let videoId: String
    let title: String

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(8)
            .onDrag {
                AlbumReorderPasteboard.itemProvider(videoId: videoId)
            } preview: {
                Text(title)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .help("Drag to reorder this album")
    }
}
