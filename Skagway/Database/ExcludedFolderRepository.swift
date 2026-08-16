import Foundation
import GRDB

struct ExcludedFolderRepository {
    let dbPool: DatabasePool

    func fetchAll() async throws -> [ExcludedFolder] {
        try await dbPool.read { db in
            try ExcludedFolder.order(Column("name").asc).fetchAll(db)
        }
    }

    func fetchPaths() async throws -> [String] {
        try await dbPool.read { db in
            try String.fetchAll(db, sql: "SELECT folderPath FROM excluded_folder")
        }
    }

    @discardableResult
    func insert(_ folder: ExcludedFolder) async throws -> ExcludedFolder {
        try await dbPool.write { db in
            var row = folder
            try row.insert(db)
            return row
        }
    }

    func delete(_ folder: ExcludedFolder) async throws {
        _ = try await dbPool.write { db in
            try folder.delete(db)
        }
    }

    func exists(folderPath: String) async throws -> Bool {
        let normalized = ExcludedFolderMatcher.normalize(folderPath)
        return try await dbPool.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT COUNT(*) > 0 FROM excluded_folder WHERE folderPath = ? COLLATE NOCASE",
                arguments: [normalized]
            ) ?? false
        }
    }
}
