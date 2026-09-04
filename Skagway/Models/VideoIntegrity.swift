import Foundation

/// Library “Corrupt” heuristic — missing decode metadata, or still no thumbnail after generation settled.
enum VideoIntegrity {
    static func isCorrupt(_ video: Video, thumbnailsSettled: Bool) -> Bool {
        video.duration == nil && video.width == nil && video.height == nil
            || (thumbnailsSettled && video.thumbnailPath == nil)
    }
}
