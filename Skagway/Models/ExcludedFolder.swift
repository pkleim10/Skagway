import Foundation
import GRDB

struct ExcludedFolder: Codable, Identifiable, Equatable, Hashable {
    var id: Int64?
    var folderPath: String
    var name: String
    var dateAdded: Date

    var url: URL { URL(fileURLWithPath: folderPath) }
}

extension ExcludedFolder: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "excluded_folder"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// Path containment for scan excludes. Case-insensitive; requires a path-separator boundary
/// so `/Videos` does not match `/Videos-backup`.
enum ExcludedFolderMatcher {
    static func normalize(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var p = url.path
        while p.count > 1, p.hasSuffix("/") {
            p.removeLast()
        }
        return p
    }

    /// True when `path` is an excluded root or a descendant of one.
    static func contains(_ path: String, excludedRoots: [String]) -> Bool {
        guard !excludedRoots.isEmpty else { return false }
        let candidate = normalize(path)
        for root in excludedRoots where isUnder(root: normalize(root), path: candidate) {
            return true
        }
        return false
    }

    static func isUnder(root: String, path: String) -> Bool {
        if path.caseInsensitiveCompare(root) == .orderedSame { return true }
        guard path.count > root.count + 1 else { return false }
        let prefix = String(path.prefix(root.count))
        guard prefix.caseInsensitiveCompare(root) == .orderedSame else { return false }
        let sep = path[path.index(path.startIndex, offsetBy: root.count)]
        return sep == "/"
    }

    /// A scan exclude must be a descendant of the data source, not the source folder itself.
    static func isValidExclusion(path: String, ofSource sourcePath: String) -> Bool {
        let p = normalize(path)
        let r = normalize(sourcePath)
        guard p.caseInsensitiveCompare(r) != .orderedSame else { return false }
        return isUnder(root: r, path: p)
    }

    /// Deepest data source whose folder contains `path` (path-length wins when sources nest).
    static func owningSource(of path: String, among sources: [DataSource]) -> DataSource? {
        let p = normalize(path)
        return sources
            .filter { isUnder(root: normalize($0.folderPath), path: p) }
            .max { normalize($0.folderPath).count < normalize($1.folderPath).count }
    }

    static func excludes(
        ownedBy source: DataSource,
        from excludes: [ExcludedFolder],
        sources: [DataSource]
    ) -> [ExcludedFolder] {
        excludes.filter { owningSource(of: $0.folderPath, among: sources)?.id == source.id }
    }

    static func orphanedExcludes(
        from excludes: [ExcludedFolder],
        sources: [DataSource]
    ) -> [ExcludedFolder] {
        excludes.filter { owningSource(of: $0.folderPath, among: sources) == nil }
    }
}
