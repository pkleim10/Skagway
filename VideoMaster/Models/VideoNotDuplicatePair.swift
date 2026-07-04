import Foundation
import GRDB

/// A user decision that two videos are **not** duplicates of each other, despite sharing a
/// content fingerprint. Stored normalized (`videoIdA < videoIdB`) so an unordered pair has a
/// single row. FK cascade (see the `v8_notDuplicatePairs` migration) removes the row when either
/// video is deleted from the library. Consumed by the Duplicates recompute in `LibraryViewModel`.
struct VideoNotDuplicatePair: Codable, Equatable {
    var videoIdA: Int64
    var videoIdB: Int64

    /// Build a normalized pair (lower id first) from two arbitrary video database ids.
    init(_ a: Int64, _ b: Int64) {
        self.videoIdA = min(a, b)
        self.videoIdB = max(a, b)
    }
}

extension VideoNotDuplicatePair: FetchableRecord, PersistableRecord {
    static let databaseTableName = "video_not_duplicate"
}
