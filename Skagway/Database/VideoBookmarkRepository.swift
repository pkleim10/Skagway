import Foundation
import GRDB

struct VideoBookmarkRepository {
    let dbPool: DatabasePool

    func fetch(forVideoId videoId: Int64) async throws -> [VideoBookmark] {
        try await dbPool.read { db in
            try VideoBookmark
                .filter(Column("videoId") == videoId)
                .order(Column("seconds").asc)
                .fetchAll(db)
        }
    }

    @discardableResult
    func insert(_ bookmark: VideoBookmark) async throws -> VideoBookmark {
        try await dbPool.write { db in
            var row = bookmark
            try row.insert(db)
            return row
        }
    }

    func update(_ bookmark: VideoBookmark) async throws {
        try await dbPool.write { db in
            try bookmark.update(db)
        }
    }

    func delete(_ bookmark: VideoBookmark) async throws {
        _ = try await dbPool.write { db in
            try bookmark.delete(db)
        }
    }

    func updateTitle(id: Int64, title: String) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE video_bookmark SET title = ? WHERE id = ?",
                arguments: [title, id]
            )
        }
    }

    func updateThumbnailPath(id: Int64, path: String?) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE video_bookmark SET thumbnailPath = ? WHERE id = ?",
                arguments: [path, id]
            )
        }
    }
}
