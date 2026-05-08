import Foundation

/// Persists last-known playback positions per video.
///
/// Today this is intentionally lightweight (UserDefaults) and keyed by file path so
/// it works even before a video has a database id (or if the DB is reset).
enum PlaybackPositionStore {
    private static let defaults = UserDefaults.standard
    private static let key = "videomaster.playback.lastPositionsByPath"

    static func loadSeconds(filePath: String) -> Double? {
        guard let dict = defaults.dictionary(forKey: key) as? [String: Double] else { return nil }
        return dict[filePath]
    }

    static func saveSeconds(_ seconds: Double, filePath: String) {
        var dict = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        dict[filePath] = seconds
        defaults.set(dict, forKey: key)
    }

    static func clear(filePath: String) {
        var dict = (defaults.dictionary(forKey: key) as? [String: Double]) ?? [:]
        dict.removeValue(forKey: filePath)
        defaults.set(dict, forKey: key)
    }
}

