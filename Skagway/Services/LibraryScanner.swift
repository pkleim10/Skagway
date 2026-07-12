import Foundation
import GRDB

enum ScanUpdate: Sendable {
    case started(total: Int)
    case progress(current: Int, total: Int, fileName: String)
    case completed
    case error(String)
    /// Non-fatal: some individual files failed to process but the scan otherwise completed normally.
    /// Yielded before `.completed`; per-file details are logged to console.
    case partialFailure(count: Int)
}

actor LibraryScanner {
    private let dbPool: DatabasePool
    private let metadataExtractor = MetadataExtractor()
    private let thumbnailService: ThumbnailService
    private let videoRepo: VideoRepository

    init(dbPool: DatabasePool, thumbnailService: ThumbnailService) {
        self.dbPool = dbPool
        self.thumbnailService = thumbnailService
        self.videoRepo = VideoRepository(dbPool: dbPool)
    }

    func scan(folder: URL) -> AsyncStream<ScanUpdate> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.performScan(folder: folder, continuation: continuation)
            }
        }
    }

    private func performScan(folder: URL, continuation: AsyncStream<ScanUpdate>.Continuation) async {
        let videoFiles = discoverVideoFiles(in: folder)
        continuation.yield(.started(total: videoFiles.count))

        let concurrencyLimit = 4
        var processed = 0
        var failures = 0

        await withTaskGroup(of: Bool.self) { group in
            for (index, fileURL) in videoFiles.enumerated() {
                if index >= concurrencyLimit, let ok = await group.next(), !ok {
                    failures += 1
                }

                group.addTask { [self] in
                    await self.processFile(fileURL)
                }

                processed += 1
                continuation.yield(
                    .progress(
                        current: processed,
                        total: videoFiles.count,
                        fileName: fileURL.lastPathComponent
                    )
                )
            }

            for await ok in group where !ok {
                failures += 1
            }
        }

        if failures > 0 {
            continuation.yield(.partialFailure(count: failures))
        }
        continuation.yield(.completed)
        continuation.finish()
    }

    @discardableResult
    private func processFile(_ fileURL: URL) async -> Bool {
        do {
            let exists = try await videoRepo.videoExists(filePath: fileURL.path)
            guard !exists else { return true }

            let metadata = await metadataExtractor.extract(from: fileURL)
            let hasSRT = SubtitleTrack.findSidecarSRT(for: fileURL) != nil

            let videoInput = Video(
                filePath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                fileSize: metadata.fileSize,
                duration: metadata.duration,
                width: metadata.width,
                height: metadata.height,
                codec: metadata.codec,
                frameRate: metadata.frameRate,
                creationDate: metadata.creationDate,
                dateAdded: Date(),
                rating: 0,
                playCount: 0,
                hasSubtitles: hasSRT,
                contentFingerprint: ContentFingerprint.compute(url: fileURL)
            )

            let video = try await videoRepo.insert(videoInput)

            Task.detached { [thumbnailService, videoRepo] in
                if let url = try? await thumbnailService.generateThumbnail(for: video),
                   let dbId = video.databaseId
                {
                    try? await videoRepo.updateThumbnailPath(videoId: dbId, path: url.path)
                }
            }
            return true
        } catch {
            print("Failed to process \(fileURL.lastPathComponent): \(error)")
            return false
        }
    }

    func scanFiles(_ urls: [URL]) -> AsyncStream<ScanUpdate> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.performFilesScan(urls: urls, continuation: continuation)
            }
        }
    }

    private func performFilesScan(urls: [URL], continuation: AsyncStream<ScanUpdate>.Continuation) async {
        let videoFiles = urls.filter { $0.isVideoFile }
        guard !videoFiles.isEmpty else {
            continuation.yield(.started(total: 0))
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        continuation.yield(.started(total: videoFiles.count))

        let concurrencyLimit = 4
        var processed = 0
        var failures = 0

        await withTaskGroup(of: Bool.self) { group in
            for (index, fileURL) in videoFiles.enumerated() {
                if index >= concurrencyLimit, let ok = await group.next(), !ok {
                    failures += 1
                }

                group.addTask { [self] in
                    await self.processFile(fileURL)
                }

                processed += 1
                continuation.yield(
                    .progress(
                        current: processed,
                        total: videoFiles.count,
                        fileName: fileURL.lastPathComponent
                    )
                )
            }

            for await ok in group where !ok {
                failures += 1
            }
        }

        if failures > 0 {
            continuation.yield(.partialFailure(count: failures))
        }
        continuation.yield(.completed)
        continuation.finish()
    }

    func scanForNewFiles(folders: [URL], knownPaths: Set<String>) -> AsyncStream<ScanUpdate> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.performNewFilesScan(folders: folders, knownPaths: knownPaths, continuation: continuation)
            }
        }
    }

    private func performNewFilesScan(
        folders: [URL],
        knownPaths: Set<String>,
        continuation: AsyncStream<ScanUpdate>.Continuation
    ) async {
        var newFiles: [URL] = []
        for folder in folders {
            for file in discoverVideoFiles(in: folder) where !knownPaths.contains(file.path) {
                newFiles.append(file)
            }
        }

        guard !newFiles.isEmpty else {
            continuation.yield(.started(total: 0))
            continuation.yield(.completed)
            continuation.finish()
            return
        }

        continuation.yield(.started(total: newFiles.count))

        let concurrencyLimit = 4
        var processed = 0
        var failures = 0

        await withTaskGroup(of: Bool.self) { group in
            for (index, fileURL) in newFiles.enumerated() {
                if index >= concurrencyLimit, let ok = await group.next(), !ok {
                    failures += 1
                }

                group.addTask { [self] in
                    await self.importFile(fileURL)
                }

                processed += 1
                continuation.yield(
                    .progress(
                        current: processed,
                        total: newFiles.count,
                        fileName: fileURL.lastPathComponent
                    )
                )
            }

            for await ok in group where !ok {
                failures += 1
            }
        }

        if failures > 0 {
            continuation.yield(.partialFailure(count: failures))
        }
        continuation.yield(.completed)
        continuation.finish()
    }

    @discardableResult
    private func importFile(_ fileURL: URL) async -> Bool {
        do {
            let metadata = await metadataExtractor.extract(from: fileURL)
            let hasSRT = SubtitleTrack.findSidecarSRT(for: fileURL) != nil

            let videoInput = Video(
                filePath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                fileSize: metadata.fileSize,
                duration: metadata.duration,
                width: metadata.width,
                height: metadata.height,
                codec: metadata.codec,
                frameRate: metadata.frameRate,
                creationDate: metadata.creationDate,
                dateAdded: Date(),
                rating: 0,
                playCount: 0,
                hasSubtitles: hasSRT,
                contentFingerprint: ContentFingerprint.compute(url: fileURL)
            )

            let video = try await videoRepo.insert(videoInput)

            Task.detached { [thumbnailService, videoRepo] in
                if let url = try? await thumbnailService.generateThumbnail(for: video),
                   let dbId = video.databaseId
                {
                    try? await videoRepo.updateThumbnailPath(videoId: dbId, path: url.path)
                }
            }
            return true
        } catch {
            print("Failed to import \(fileURL.lastPathComponent): \(error)")
            return false
        }
    }

    private func discoverVideoFiles(in folder: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return results }

        while let url = enumerator.nextObject() as? URL {
            if url.isVideoFile {
                results.append(url)
            }
        }
        return results
    }
}
