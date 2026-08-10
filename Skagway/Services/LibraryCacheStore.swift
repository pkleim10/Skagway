import Foundation
import GRDB

/// Persists the thumbnail/filmstrip cache root inside the open library DB (singleton `library_cache` row).
/// Save Copy duplicates this pointer, so the copy keeps using the original cache.
enum LibraryCacheStore {
    private static let singletonID = 1

    /// Resolved cache directory from the library DB, if a row exists and the bookmark/path resolve.
    static func resolvedURL(db: Database) throws -> URL? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT path, bookmark FROM library_cache WHERE id = ?",
            arguments: [singletonID]
        ) else { return nil }

        if let data: Data = row["bookmark"], let url = resolveBookmark(data) {
            return url.standardizedFileURL
        }
        guard let path: String = row["path"] else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    /// Write / replace the singleton cache location.
    static func save(db: Database, directory: URL, bookmark: Data?) throws {
        try db.execute(
            sql: """
            INSERT INTO library_cache (id, path, bookmark) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET path = excluded.path, bookmark = excluded.bookmark
            """,
            arguments: [
                singletonID,
                (directory.path as NSString).standardizingPath,
                bookmark,
            ]
        )
    }

    /// True when the library has a stored cache row (even if the volume is offline).
    static func hasStoredLocation(db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT COUNT(*) > 0 FROM library_cache WHERE id = ?",
            arguments: [singletonID]
        ) ?? false
    }

    // MARK: - Bookmark helpers (mirror library bookmarks — app is not sandboxed)

    static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        return nil
    }

    static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
