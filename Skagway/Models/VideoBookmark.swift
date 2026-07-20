import Foundation
import GRDB

/// User-authored point of interest in a video: timestamp + name + frame still.
/// Resume playback remains a separate automatic store (`PlaybackPositionStore`).
struct VideoBookmark: Codable, Equatable, Hashable, Identifiable {
    var id: Int64?
    var videoId: Int64
    var seconds: Double
    var title: String
    var thumbnailPath: String?
    var dateCreated: Date

    var listId: String { "bookmark-\(id ?? 0)" }

    var formattedTimecode: String { seconds.formattedDuration }
}

extension VideoBookmark: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "video_bookmark"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
