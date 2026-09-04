import XCTest
import GRDB
@testable import Skagway

final class DatabaseMigrationTests: XCTestCase {
    func testCreateEmptyDatabaseAppliesLatestSchema() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skagway-migrate-\(UUID().uuidString).machii")
        defer { try? FileManager.default.removeItem(at: url) }

        try DatabaseMigration.createEmptyDatabase(at: url.path)

        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)

        try pool.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
            for required in [
                "video", "tag", "video_tag", "collection", "collection_rule",
                "collection_rule_group", "collection_video", "library_cache", "excluded_folder",
            ] {
                XCTAssertTrue(tables.contains(required), "missing table \(required)")
            }

            let videoCols = try Row.fetchAll(db, sql: "PRAGMA table_info(video)").map { $0["name"] as String }
            XCTAssertTrue(videoCols.contains("contentFingerprint"))
            XCTAssertTrue(videoCols.contains("hasSubtitles"))
            XCTAssertTrue(videoCols.contains("title"))
            XCTAssertTrue(videoCols.contains("originalFileName"))

            let membershipCols = try Row.fetchAll(db, sql: "PRAGMA table_info(collection_video)")
                .map { $0["name"] as String }
            XCTAssertTrue(membershipCols.contains("sortIndex"))

            let indexes = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
            XCTAssertTrue(indexes.contains("idx_collection_video_collectionId_sortIndex"))
        }
    }

    func testMigrateIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skagway-migrate-twice-\(UUID().uuidString).machii")
        defer { try? FileManager.default.removeItem(at: url) }

        try DatabaseMigration.createEmptyDatabase(at: url.path)
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        try DatabaseMigration.migrate(pool)
        try DatabaseMigration.migrate(pool)
    }
}
