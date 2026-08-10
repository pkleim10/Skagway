import Foundation
import CryptoKit

/// Resolves on-disk thumbnail/filmstrip cache folder names.
///
/// Live writes go to the open library’s cache (`LibraryCacheStore` /
/// `DatabaseExportImport.ensureLibraryCacheRoot`). New co-located caches use visible
/// `Skagway-cache`. Older `.Skagway-cache` / `thumbnails` folders are still recognized.
enum ThumbnailCacheLocator {
    /// Canonical co-located cache folder name (visible in Finder).
    static let cacheFolderName = "Skagway-cache"
    /// Hidden sibling name still accepted when resolving.
    static let hiddenCacheFolderName = ".Skagway-cache"
    /// Pre–Skagway-cache folder name still accepted when discovering legacy roots.
    static let legacyCacheFolderName = "thumbnails"

    /// Known cache directory basenames under a parent (visible first, then hidden, then legacy).
    static var knownCacheFolderNames: [String] {
        [cacheFolderName, hiddenCacheFolderName, legacyCacheFolderName]
    }

    /// `~/Library/Caches/Skagway` parent.
    static var systemSkagwayCachesParent: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("Skagway", isDirectory: true)
    }

    /// Standard-home shared cache: `~/Library/Caches/Skagway/Skagway-cache` (or existing legacy name).
    static var standardSharedCacheDirectory: URL {
        if let existing = resolveExistingCacheDirectory(inParent: systemSkagwayCachesParent) {
            return existing
        }
        return systemSkagwayCachesParent.appendingPathComponent(cacheFolderName, isDirectory: true)
    }

    /// Per-library system cache so two “system default” libraries do not share one folder.
    static func systemCacheDirectory(forLibraryURL libraryURL: URL) -> URL {
        let hash = SHA256.hash(data: Data(libraryURL.path.utf8))
        let hex = hash.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
        return systemSkagwayCachesParent
            .appendingPathComponent("libraries", isDirectory: true)
            .appendingPathComponent(hex, isDirectory: true)
    }

    /// Prefer an existing `Skagway-cache` / `.Skagway-cache` / `thumbnails` under `parent`.
    static func resolveExistingCacheDirectory(inParent parent: URL) -> URL? {
        let fm = FileManager.default
        return knownCacheFolderNames
            .map { parent.appendingPathComponent($0, isDirectory: true) }
            .first { fm.fileExists(atPath: $0.path) }
    }

    /// Co-located cache next to a library file’s parent folder (create path if none exists yet).
    static func coLocatedCacheDirectory(forLibraryURL libraryURL: URL) -> URL {
        let parent = libraryURL.deletingLastPathComponent()
        if let existing = resolveExistingCacheDirectory(inParent: parent) {
            return existing
        }
        return parent.appendingPathComponent(cacheFolderName, isDirectory: true)
    }
}
