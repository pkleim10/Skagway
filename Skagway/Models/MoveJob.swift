import Foundation

/// A single "Move Files…" job, tracked for cross-volume moves (which are a real copy + delete
/// and can take real wall-clock time). Same-volume moves are an atomic `FileManager.moveItem`
/// rename and never enter the queue — see `LibraryViewModel.moveVideos(_:to:)`.
///
/// Safety mirrors the re-encode queue: the destination copy lands at a temp name
/// (`<name>.moving`) first. Only once the copy is verified complete is it promoted to the
/// final name, and only *then* is the source deleted — a crash mid-copy leaves at worst an
/// orphaned `.moving` temp at the destination, with the original file untouched.
struct MoveJob: Codable, Identifiable, Equatable {
    enum Status: Codable, Equatable {
        case queued
        case moving(fractionComplete: Double)
        case completed
        case failed(reason: String)
    }

    let id: UUID
    /// DB row id, resolved to a live `Video` at run time (survives path changes from other jobs).
    var videoDatabaseId: Int64?
    /// Path at enqueue time — used for display and as a fallback when the DB row can't be resolved.
    var sourcePath: String
    var sourceFileName: String
    var destinationFolderPath: String
    var status: Status
    var enqueuedAt: Date

    /// Set once the job completes.
    var completedAt: Date?
    /// Final path at the destination once completed.
    var newPath: String?

    init(video: Video, destinationFolder: URL) {
        self.id = UUID()
        self.videoDatabaseId = video.databaseId
        self.sourcePath = video.filePath
        self.sourceFileName = video.fileName
        self.destinationFolderPath = destinationFolder.path
        self.status = .queued
        self.enqueuedAt = Date()
    }

    var isActive: Bool {
        switch status {
        case .queued, .moving: return true
        case .completed, .failed: return false
        }
    }

    var isCompleted: Bool { status == .completed }
}
