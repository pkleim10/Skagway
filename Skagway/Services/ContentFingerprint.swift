import Foundation
import CryptoKit

/// Cheap, content-based duplicate fingerprint. Hashes the file's byte size plus the first and
/// last 64 KB (or the whole file when it's smaller than 128 KB) into a SHA-256 hex string.
///
/// Rationale: two byte-identical files produce the same fingerprint; two genuinely different
/// files that merely happen to share size + rounded duration (the old heuristic's false-positive
/// case) will almost always differ in their head or tail bytes, so they no longer collide.
/// Reading only the ends keeps it cheap on multi-GB videos — no full-file scan. Because it's
/// derived from content, it's stable across rename/move (unlike the file-path identity).
enum ContentFingerprint {
    /// Bytes read from each end. A collision now requires identical size AND identical first 64 KB
    /// AND identical last 64 KB but differing middle — vanishingly unlikely for real files, and the
    /// pairwise "Not a Duplicate" override covers that residual case anyway.
    private static let chunkSize = 64 * 1024

    /// Computes the fingerprint, or `nil` if the file can't be read (e.g. drive not mounted).
    static func compute(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch { return nil }

        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }

        do {
            if size <= UInt64(chunkSize) * 2 {
                // Small enough: hash the whole file.
                try handle.seek(toOffset: 0)
                if let data = try handle.read(upToCount: Int(size)) { hasher.update(data: data) }
            } else {
                // Head.
                try handle.seek(toOffset: 0)
                if let head = try handle.read(upToCount: chunkSize) { hasher.update(data: head) }
                // Tail.
                try handle.seek(toOffset: size - UInt64(chunkSize))
                if let tail = try handle.read(upToCount: chunkSize) { hasher.update(data: tail) }
            }
        } catch { return nil }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
