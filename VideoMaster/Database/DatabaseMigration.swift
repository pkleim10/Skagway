import Foundation
import GRDB

enum DatabaseMigration {
    /// Creates an empty database at the given path and runs all migrations.
    static func createEmptyDatabase(at path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=DELETE")
        }
        let pool = try DatabasePool(path: path, configuration: config)
        try migrate(pool)
    }

    static func migrate(_ pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        // Do not use eraseDatabaseOnSchemaChange — it wipes user data when opening existing DBs.

        migrator.registerMigration("v1_createTables") { db in
            try db.create(table: "video") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("filePath", .text).notNull().unique()
                t.column("fileName", .text).notNull()
                t.column("fileSize", .integer).notNull()
                t.column("duration", .double)
                t.column("width", .integer)
                t.column("height", .integer)
                t.column("codec", .text)
                t.column("frameRate", .double)
                t.column("creationDate", .datetime)
                t.column("dateAdded", .datetime).notNull()
                t.column("rating", .integer).notNull().defaults(to: 0)
                t.column("thumbnailPath", .text)
                t.column("lastPlayed", .datetime)
                t.column("playCount", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "tag") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique().collate(.nocase)
            }

            try db.create(table: "video_tag") { t in
                t.column("videoId", .integer).notNull().references("video", onDelete: .cascade)
                t.column("tagId", .integer).notNull().references("tag", onDelete: .cascade)
                t.primaryKey(["videoId", "tagId"])
            }

            try db.create(virtualTable: "video_fts", using: FTS5()) { t in
                t.synchronize(withTable: "video")
                t.column("fileName")
            }

            try db.create(index: "idx_video_rating", on: "video", columns: ["rating"])
            try db.create(index: "idx_video_duration", on: "video", columns: ["duration"])
            try db.create(index: "idx_video_fileSize", on: "video", columns: ["fileSize"])
            try db.create(index: "idx_video_dateAdded", on: "video", columns: ["dateAdded"])
        }

        migrator.registerMigration("v2_dataSources") { db in
            try db.create(table: "data_source") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("folderPath", .text).notNull().unique()
                t.column("name", .text).notNull()
                t.column("dateAdded", .datetime).notNull()
            }
        }

        migrator.registerMigration("v3_collections") { db in
            try db.create(table: "collection") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("dateCreated", .datetime).notNull()
            }

            try db.create(table: "collection_rule") { t in
                t.column("collectionId", .integer).notNull()
                    .references("collection", onDelete: .cascade)
                t.column("attribute", .text).notNull()
                t.column("comparison", .text).notNull()
                t.column("value", .text).notNull()
            }

            try db.create(
                index: "idx_collection_rule_collectionId",
                on: "collection_rule",
                columns: ["collectionId"]
            )
        }

        migrator.registerMigration("v4_collectionMatchMode") { db in
            try db.alter(table: "collection") { t in
                t.add(column: "matchMode", .text).notNull().defaults(to: "all")
            }
        }

        migrator.registerMigration("v5_video_custom_metadata") { db in
            try db.create(table: "video_custom_metadata") { t in
                t.column("videoId", .integer).notNull()
                    .references("video", onDelete: .cascade)
                t.column("fieldId", .text).notNull()
                t.column("value", .text).notNull()
                t.primaryKey(["videoId", "fieldId"])
            }
            try db.create(
                index: "idx_video_custom_metadata_videoId",
                on: "video_custom_metadata",
                columns: ["videoId"]
            )
        }

        migrator.registerMigration("v6_hasSubtitles") { db in
            try db.alter(table: "video") { t in
                // Default 0 means "unknown / not detected". Set at import when a sidecar `.srt`
                // is found, and updated at playback/selection time via the detail view.
                t.add(column: "hasSubtitles", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v7_contentFingerprint") { db in
            try db.alter(table: "video") { t in
                // Nullable: unknown until computed (unreachable files, or not yet backfilled).
                // Cheap content hash (size + first/last 64 KB) — see `ContentFingerprint`.
                t.add(column: "contentFingerprint", .text)
            }
        }

        migrator.registerMigration("v8_notDuplicatePairs") { db in
            // "These two videos are confirmed NOT duplicates of each other." Stored normalized
            // (videoIdA < videoIdB). FK cascade auto-cleans when either video is removed, like
            // `video_tag`. See `VideoNotDuplicatePair` and the Duplicates recompute in the VM.
            try db.create(table: "video_not_duplicate") { t in
                t.column("videoIdA", .integer).notNull().references("video", onDelete: .cascade)
                t.column("videoIdB", .integer).notNull().references("video", onDelete: .cascade)
                t.primaryKey(["videoIdA", "videoIdB"])
            }
        }

        try migrator.migrate(pool)
    }
}
