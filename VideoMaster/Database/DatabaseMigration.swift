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

        migrator.registerMigration("v9_collectionRuleGroups") { db in
            // Two-level AND/OR grouping: rules now cluster into groups (mode within a group), and
            // the collection's existing `matchMode` becomes the mode *between* groups. Every
            // existing collection's flat rule list is backfilled into a single group carrying the
            // collection's original matchMode (see below), since the outer mode is a no-op for a
            // lone group and would otherwise not preserve "match ANY" collections.
            try db.create(table: "collection_rule_group") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("collectionId", .integer).notNull().references("collection", onDelete: .cascade)
                t.column("orderIndex", .integer).notNull()
                t.column("matchMode", .text).notNull().defaults(to: "all")
            }
            try db.create(
                index: "idx_collection_rule_group_collectionId",
                on: "collection_rule_group",
                columns: ["collectionId"]
            )

            try db.alter(table: "collection_rule") { t in
                t.add(column: "groupId", .integer).references("collection_rule_group", onDelete: .cascade)
            }

            // A lone group's outer combination mode is a no-op only if the GROUP itself carries the
            // collection's original matchMode — otherwise a pre-existing "any" collection would
            // silently start requiring ALL its rules to match.
            let collectionRows = try Row.fetchAll(db, sql: "SELECT id, matchMode FROM collection")
            for row in collectionRows {
                let collectionId: Int64 = row["id"]
                let matchMode: String = row["matchMode"]
                try db.execute(
                    sql: "INSERT INTO collection_rule_group (collectionId, orderIndex, matchMode) VALUES (?, 0, ?)",
                    arguments: [collectionId, matchMode]
                )
                let groupId = db.lastInsertedRowID
                try db.execute(
                    sql: "UPDATE collection_rule SET groupId = ? WHERE collectionId = ?",
                    arguments: [groupId, collectionId]
                )
            }
        }

        migrator.registerMigration("v10_collectionRuleValue2") { db in
            // Second value for the new `.between` range operator (nullable — every existing rule
            // leaves it NULL, and the unified filter matcher only reads it for `.between`). The
            // `attribute` column is unchanged: built-in attributes keep their exact RuleAttribute
            // rawValue token, so existing rows decode straight into `FilterField.builtin(...)`;
            // custom-field rules (new) store a `custom:<uuid>` token in that same TEXT column.
            try db.alter(table: "collection_rule") { t in
                t.add(column: "value2", .text)
            }
        }

        migrator.registerMigration("v11_albums") { db in
            // Albums = manual membership collections. Existing rows default to smart (rule-based).
            try db.alter(table: "collection") { t in
                t.add(column: "kind", .text).notNull().defaults(to: CollectionKind.smart.rawValue)
            }
            try db.create(table: "collection_video") { t in
                t.column("videoId", .integer).notNull()
                    .references("video", onDelete: .cascade)
                t.column("collectionId", .integer).notNull()
                    .references("collection", onDelete: .cascade)
                t.column("dateAdded", .datetime).notNull()
                t.primaryKey(["videoId", "collectionId"])
            }
            try db.create(
                index: "idx_collection_video_collectionId",
                on: "collection_video",
                columns: ["collectionId"]
            )
        }

        try migrator.migrate(pool)
    }
}
