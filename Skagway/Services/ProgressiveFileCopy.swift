import Darwin
import Foundation

/// Near-native file copy via `copyfile(3)` with byte progress and cooperative abort.
///
/// Prefer this over `FileManager.copyItem` (no progress) and over a Swift `FileHandle` loop
/// (slower). Abort must use `MoveAbortLatch` — `Task.cancel()` alone is not enough.
enum ProgressiveFileCopy {
    /// Copies `source` → `destination` (overwrites destination if present).
    /// - Throws: `CancellationError` when aborted; other errors on I/O failure.
    /// - Note: Leaves a partial destination on abort/failure for the caller to remove.
    static func copy(
        from source: URL,
        to destination: URL,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) throws {
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: source.path)
        let total = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        let context = CopyContext(totalBytes: total, isCancelled: isCancelled, onProgress: onProgress)
        let unmanaged = Unmanaged.passRetained(context)
        defer { unmanaged.release() }

        guard let state = copyfile_state_alloc() else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { copyfile_state_free(state) }

        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), unmanaged.toOpaque())
        let cb: copyfile_callback_t = copyfileStatusCallback
        copyfile_state_set(
            state,
            UInt32(COPYFILE_STATE_STATUS_CB),
            unsafeBitCast(cb, to: UnsafeMutableRawPointer.self)
        )

        let flags = copyfile_flags_t(COPYFILE_ALL)
        let result = source.path.withCString { srcPtr in
            destination.path.withCString { dstPtr in
                copyfile(srcPtr, dstPtr, state, flags)
            }
        }

        if isCancelled() || Task.isCancelled {
            throw CancellationError()
        }
        if result < 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "copyfile failed (errno \(errno))"]
            )
        }
        if context.lastFraction < 1.0 {
            onProgress(1.0)
        }
    }
}

/// Thread-safe abort latch for an in-flight cross-volume move.
final class MoveAbortLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false

    func abort() {
        lock.lock()
        aborted = true
        lock.unlock()
    }

    var isAborted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return aborted
    }
}

// MARK: - copyfile callback

private final class CopyContext: @unchecked Sendable {
    let totalBytes: Int64
    let isCancelled: @Sendable () -> Bool
    let onProgress: @Sendable (Double) -> Void
    var lastFraction: Double = -1

    init(
        totalBytes: Int64,
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) {
        self.totalBytes = totalBytes
        self.isCancelled = isCancelled
        self.onProgress = onProgress
    }
}

private func copyfileStatusCallback(
    _ what: Int32,
    _ stage: Int32,
    _ state: copyfile_state_t?,
    _ src: UnsafePointer<CChar>?,
    _ dst: UnsafePointer<CChar>?,
    _ ctx: UnsafeMutableRawPointer?
) -> Int32 {
    guard let ctx else { return COPYFILE_CONTINUE }
    let context = Unmanaged<CopyContext>.fromOpaque(ctx).takeUnretainedValue()

    if context.isCancelled() {
        return COPYFILE_QUIT
    }

    if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let state {
        var copied: off_t = 0
        if copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied) == 0, context.totalBytes > 0 {
            let fraction = min(1.0, Double(copied) / Double(context.totalBytes))
            if fraction - context.lastFraction >= 0.01 || fraction >= 1.0 {
                context.lastFraction = fraction
                context.onProgress(fraction)
            }
        }
    }

    if stage == COPYFILE_ERR {
        return COPYFILE_QUIT
    }
    return COPYFILE_CONTINUE
}
