import Foundation

/// One-shot cutover from the former product name / bundle ID.
///
/// **Allowlist:** this file is the only intentional runtime home for old-name strings
/// (`VideoMaster`, `com.videomaster.VideoMaster`, `videomaster.playback…`).
/// Steady-state code uses Skagway paths and `PrefsKeys` only.
enum LegacyRenameMigrator {
    private static let oldBundleID = "com.videomaster.VideoMaster"
    private static let oldAppSupportFolder = "VideoMaster"
    private static let oldDefaultLibraryFile = "VideoMaster.VideoMaster"
    private static let oldPlaybackPositionsKey = "videomaster.playback.lastPositionsByPath"
    private static let oldDividerSidebarKey = "playbackDividerSidebar"
    private static let oldDividerContentKey = "playbackDividerContent"

    private static let newAppSupportFolder = "Skagway"
    private static let newDefaultLibraryFile = "Skagway.machii"

    /// Call once at the very start of `AppState.init`, before any prefs reads.
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PrefsKeys.didCompleteLegacyRename) else { return }

        migratePrefs(into: defaults)
        copyDefaultLibraryIfNeeded()
        copyThumbnailCacheIfNeeded()

        defaults.set(true, forKey: PrefsKeys.didCompleteLegacyRename)
        defaults.synchronize()
    }

    // MARK: - Prefs

    private static func migratePrefs(into defaults: UserDefaults) {
        let oldDomain = UserDefaults(suiteName: oldBundleID)

        for suffix in PrefsKeys.migratableSuffixes {
            let oldKey = "VideoMaster.\(suffix)"
            let newKey: String
            if suffix == "lastOpenedLibraryBookmark" {
                newKey = PrefsKeys.activeLibraryBookmark
            } else {
                newKey = PrefsKeys.prefix + suffix
            }

            if defaults.object(forKey: newKey) == nil {
                if let value = defaults.object(forKey: oldKey) {
                    defaults.set(value, forKey: newKey)
                    defaults.removeObject(forKey: oldKey)
                } else if let value = oldDomain?.object(forKey: oldKey) {
                    defaults.set(value, forKey: newKey)
                }
            } else if defaults.object(forKey: oldKey) != nil {
                defaults.removeObject(forKey: oldKey)
            }
        }

        // Playback positions (lowercase legacy key)
        if defaults.object(forKey: PrefsKeys.playbackLastPositionsByPath) == nil,
           let value = defaults.object(forKey: oldPlaybackPositionsKey)
            ?? oldDomain?.object(forKey: oldPlaybackPositionsKey) {
            defaults.set(value, forKey: PrefsKeys.playbackLastPositionsByPath)
            defaults.removeObject(forKey: oldPlaybackPositionsKey)
        } else if defaults.object(forKey: oldPlaybackPositionsKey) != nil {
            defaults.removeObject(forKey: oldPlaybackPositionsKey)
        }

        // Unprefixed divider keys → Skagway.*
        if defaults.object(forKey: PrefsKeys.playbackDividerSidebar) == nil,
           defaults.object(forKey: oldDividerSidebarKey) != nil {
            defaults.set(defaults.object(forKey: oldDividerSidebarKey), forKey: PrefsKeys.playbackDividerSidebar)
            defaults.removeObject(forKey: oldDividerSidebarKey)
        }
        if defaults.object(forKey: PrefsKeys.playbackDividerContent) == nil,
           defaults.object(forKey: oldDividerContentKey) != nil {
            defaults.set(defaults.object(forKey: oldDividerContentKey), forKey: PrefsKeys.playbackDividerContent)
            defaults.removeObject(forKey: oldDividerContentKey)
        }
    }

    // MARK: - Library file (copy, leave source)

    private static func copyDefaultLibraryIfNeeded() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let newDir = appSupport.appendingPathComponent(newAppSupportFolder, isDirectory: true)
        let dest = newDir.appendingPathComponent(newDefaultLibraryFile, isDirectory: false)
        guard !fm.fileExists(atPath: dest.path) else { return }

        let oldDir = appSupport.appendingPathComponent(oldAppSupportFolder, isDirectory: true)
        let candidates = [
            oldDir.appendingPathComponent(oldDefaultLibraryFile, isDirectory: false).path,
            oldDir.appendingPathComponent("VideoMaster.sqlite", isDirectory: false).path,
            oldDir.appendingPathComponent("library.sqlite", isDirectory: false).path,
            newDir.appendingPathComponent(oldDefaultLibraryFile, isDirectory: false).path,
            newDir.appendingPathComponent("VideoMaster.sqlite", isDirectory: false).path,
            newDir.appendingPathComponent("library.sqlite", isDirectory: false).path,
        ]

        for source in candidates where fm.fileExists(atPath: source) {
            try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            copyLibraryFile(fromPath: source, toPath: dest.path)
            return
        }
    }

    private static func copyLibraryFile(fromPath source: String, toPath dest: String) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: dest) else { return }
        try? fm.copyItem(atPath: source, toPath: dest)
        for ext in ["-wal", "-shm"] {
            let fromExt = source + ext
            let toExt = dest + ext
            if fm.fileExists(atPath: fromExt), !fm.fileExists(atPath: toExt) {
                try? fm.copyItem(atPath: fromExt, toPath: toExt)
            }
        }
    }

    // MARK: - Thumbnails (copy, leave source)

    private static func copyThumbnailCacheIfNeeded() {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let dest = caches.appendingPathComponent("\(newAppSupportFolder)/thumbnails", isDirectory: true)
        let source = caches.appendingPathComponent("\(oldAppSupportFolder)/thumbnails", isDirectory: true)
        guard !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: source.path) else { return }
        try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: source, to: dest)
    }
}
