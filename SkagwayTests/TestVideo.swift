import Foundation
@testable import Skagway

enum TestVideo {
    static func make(
        path: String = "/tmp/clip.mp4",
        fileName: String? = nil,
        title: String = "",
        rating: Int = 0,
        duration: Double? = 10,
        width: Int? = 1920,
        height: Int? = 1080,
        thumbnailPath: String? = "/tmp/thumb.jpg",
        databaseId: Int64? = 1,
        dateAdded: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Video {
        Video(
            databaseId: databaseId,
            filePath: path,
            fileName: fileName ?? (path as NSString).lastPathComponent,
            title: title,
            originalFileName: fileName ?? (path as NSString).lastPathComponent,
            fileSize: 1_000_000,
            duration: duration,
            width: width,
            height: height,
            codec: "h264",
            frameRate: 24,
            creationDate: nil,
            dateAdded: dateAdded,
            rating: rating,
            thumbnailPath: thumbnailPath,
            lastPlayed: nil,
            playCount: 0
        )
    }
}
