import Foundation
import UniformTypeIdentifiers

extension URL {
    /// True when the path extension resolves to a UTType that conforms to `public.image`
    /// (JPEG, PNG, HEIC, WebP, TIFF, GIF, etc.). Used for Set Poster / image drops.
    var isImageFile: Bool {
        let ext = pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }
}
