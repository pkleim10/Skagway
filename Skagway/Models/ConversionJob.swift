import Foundation

/// A single "Re-encode to MP4" job, tracked from enqueue through completion.
///
/// The design keeps the user's original file intact under its real name until the
/// encode provably succeeds:
///   1. ffmpeg reads the untouched original and writes `<stem>_convert.mp4`.
///   2. On success the original is renamed to `<stem>_backup.<ext>` and the temp
///      `_convert.mp4` is renamed to the final `<stem>.mp4`.
///   3. The backup is *kept* (not trashed) so the user can restore or delete it
///      later from the queue manager.
///
/// Jobs are persisted so a queue survives app relaunch (interrupted jobs resume).
struct ConversionJob: Codable, Identifiable, Equatable {
    enum Status: Codable, Equatable {
        case queued
        case converting(pct: Int)
        case completed
        case failed(reason: String)
    }

    let id: UUID
    /// DB row id, resolved to a live `Video` at run time (survives path/extension changes).
    var videoDatabaseId: Int64?
    /// Path at enqueue time — used for display and as a fallback when the DB row can't be resolved.
    var sourcePath: String
    var sourceFileName: String
    var ffmpegPath: String
    /// Source duration, if known, for computing encode percentage.
    var durationSeconds: Double?
    var status: Status
    var enqueuedAt: Date

    /// Set once the job completes.
    var completedAt: Date?
    /// Final output path (the `.mp4`) once completed.
    var convertedPath: String?
    /// The kept-aside original (`<stem>_backup.<ext>`). Nil once the backup is
    /// deleted or the conversion is restored.
    var backupPath: String?

    init(video: Video, ffmpegPath: String) {
        self.id = UUID()
        self.videoDatabaseId = video.databaseId
        self.sourcePath = video.filePath
        self.sourceFileName = video.fileName
        self.ffmpegPath = ffmpegPath
        self.durationSeconds = video.duration
        self.status = .queued
        self.enqueuedAt = Date()
    }

    /// Convenience for migrating a legacy `recentlyConverted` entry into a completed job.
    init(migratedConvertedPath path: String, date: Date) {
        self.id = UUID()
        self.videoDatabaseId = nil
        self.sourcePath = path
        self.sourceFileName = (path as NSString).lastPathComponent
        self.ffmpegPath = ""
        self.durationSeconds = nil
        self.status = .completed
        self.enqueuedAt = date
        self.completedAt = date
        self.convertedPath = path
        self.backupPath = nil // legacy flow trashed backups immediately
    }

    var isActive: Bool {
        switch status {
        case .queued, .converting: return true
        case .completed, .failed: return false
        }
    }

    var isCompleted: Bool { status == .completed }

    /// Completed jobs age out of the queue list after 30 days (the backup file, if any,
    /// is unaffected — only the tracking row is dropped).
    func isExpired(now: Date = Date()) -> Bool {
        guard status == .completed, let completedAt else { return false }
        return now.timeIntervalSince(completedAt) > 30 * 24 * 60 * 60
    }
}
