import AppKit
import Foundation
import GRDB

struct RecentLibraryItem: Identifiable {
    let id: String
    let displayName: String
    let url: URL
}

enum DatabaseExportImport {
    private static let activeLibraryBookmarkKey = PrefsKeys.activeLibraryBookmark
    private static let activeLibraryPathKey = PrefsKeys.activeLibraryPath
    private static let recentLibraryBookmarksKey = PrefsKeys.recentLibraryBookmarks
    private static let recentLibraryPathsKey = PrefsKeys.recentLibraryPaths
    private static let userClosedLibraryKey = PrefsKeys.userClosedLibrary
    private static let maxRecentLibraries = 10

    /// On-disk library extension (Mach II Labs).
    static let libraryFilenameExtension = "machii"
    private static let appSupportFolderName = "Skagway"
    private static let defaultLibraryFileName = "Skagway.machii"

    /// Stored reference to the active dbPool, set by AppState on init.
    nonisolated(unsafe) static var activeDbPool: DatabasePool?

    /// Checkpoints the current library and removes WAL files. Call before switching or closing.
    /// Only removes WAL/SHM files if the checkpoint succeeds — prevents data loss.
    static func checkpointAndCleanWAL() {
        guard let pool = activeDbPool, let url = activeLibraryURL() else { return }
        do {
            try pool.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
            let path = url.path
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        } catch {
            // Checkpoint failed — leave WAL/SHM intact to avoid data loss
        }
    }

    private static var applicationSupportRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static var dbDirectoryURL: URL {
        applicationSupportRootURL.appendingPathComponent(appSupportFolderName, isDirectory: true)
    }

    /// App Support library file. Only used when the user chose **Standard** at setup.
    static var defaultLibraryURL: URL {
        dbDirectoryURL.appendingPathComponent(defaultLibraryFileName, isDirectory: false)
    }

    /// How Skagway finds the library home after setup.
    enum LibraryHomeAccessMode: String {
        /// Application Support + system Caches; open automatically.
        case standard
        /// Custom folder; opaque bookmark kept on this Mac so the library can open when the volume is available.
        case rememberBookmark
        /// Custom folder; no location stored on the boot disk — user opens the library each launch.
        case askEachLaunch
    }

    static var libraryHomeAccessMode: LibraryHomeAccessMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: PrefsKeys.libraryHomeAccessMode),
               let mode = LibraryHomeAccessMode(rawValue: raw) {
                return mode
            }
            // Pre-access-mode installs: custom cache path ⇒ remembered bookmark; else standard.
            if hasCompletedLibraryHomeSetup {
                let hasCustomCache =
                    UserDefaults.standard.string(forKey: PrefsKeys.thumbnailCachePath) != nil
                    || UserDefaults.standard.data(forKey: PrefsKeys.thumbnailCacheBookmark) != nil
                return hasCustomCache ? .rememberBookmark : .standard
            }
            return .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: PrefsKeys.libraryHomeAccessMode)
        }
    }

    /// Whether setup chose a custom folder (not Application Support).
    /// When true, there is no Application Support “default” library — only the chosen home.
    static var usesCustomLibraryHome: Bool {
        switch libraryHomeAccessMode {
        case .standard: return false
        case .rememberBookmark, .askEachLaunch: return true
        }
    }

    /// User must pick the library each launch (no remembered location on the boot disk).
    static var promptsForLibraryEachLaunch: Bool {
        libraryHomeAccessMode == .askEachLaunch
    }

    /// Remember-custom-home: only opaque bookmarks in prefs — never plain library/cache paths.
    static var storesLocationAsBookmarkOnly: Bool {
        libraryHomeAccessMode == .rememberBookmark
    }

    /// Folder that owns the startup library + (when custom) co-located `Skagway-cache/`.
    static var homeLibraryFolderURL: URL {
        if storesLocationAsBookmarkOnly {
            if let bookmark = UserDefaults.standard.data(forKey: PrefsKeys.thumbnailCacheBookmark),
               let url = resolveLibraryBookmark(bookmark) {
                return url.deletingLastPathComponent()
            }
            if let bookmark = UserDefaults.standard.data(forKey: activeLibraryBookmarkKey),
               let url = resolveLibraryBookmark(bookmark) {
                return url.deletingLastPathComponent()
            }
            return dbDirectoryURL
        }
        if let path = UserDefaults.standard.string(forKey: PrefsKeys.thumbnailCachePath) {
            return URL(fileURLWithPath: path, isDirectory: true).deletingLastPathComponent()
        }
        return dbDirectoryURL
    }

    /// Library file for the startup home (chosen folder, or App Support only if Standard was chosen).
    static var homeLibraryURL: URL {
        if let existing = findLibraryFile(in: homeLibraryFolderURL) {
            return existing
        }
        return homeLibraryFolderURL.appendingPathComponent(defaultLibraryFileName, isDirectory: false)
    }

    static var homeLibraryExists: Bool {
        FileManager.default.fileExists(atPath: homeLibraryURL.path)
    }

    /// Whether the library that would open on launch is the startup home library.
    static var isHomeLibraryActive: Bool {
        guard let path = databasePathForLaunch() else { return false }
        return (path as NSString).standardizingPath
            == (homeLibraryURL.path as NSString).standardizingPath
    }

    /// Short path shown in help / alerts (tilde-abbreviated when under the home directory).
    static func pathForDisplay(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static var defaultLibraryPathForDisplay: String {
        pathForDisplay(defaultLibraryURL)
    }

    static var homeLibraryPathForDisplay: String {
        pathForDisplay(homeLibraryURL)
    }

    /// Whether the user explicitly closed the library. Checked once at launch, then cleared.
    static var userClosedLibrary: Bool {
        UserDefaults.standard.bool(forKey: userClosedLibraryKey)
    }

    static func clearUserClosedLibrary() {
        UserDefaults.standard.removeObject(forKey: userClosedLibraryKey)
    }

    /// Path to open for database. Standard / askEachLaunch may use plain paths; rememberBookmark is bookmark-only.
    /// Nil = no library. Does **not** erase prefs when a bookmark fails to resolve after a rebuild —
    /// that used to wipe the active library and prune recents.
    static func databasePathForLaunch() -> String? {
        if storesLocationAsBookmarkOnly {
            scrubPlainLocationPathsFromPrefs()
            if let bookmark = UserDefaults.standard.data(forKey: activeLibraryBookmarkKey),
               let url = resolveLibraryBookmark(bookmark),
               FileManager.default.fileExists(atPath: url.path) {
                refreshBookmarkIfNeeded(for: url, isActive: true)
                return (url.path as NSString).standardizingPath
            }
            return nil
        }

        if let path = UserDefaults.standard.string(forKey: activeLibraryPathKey),
           FileManager.default.fileExists(atPath: path) {
            refreshBookmarkIfNeeded(forPath: path, isActive: true)
            return path
        }

        if let bookmark = UserDefaults.standard.data(forKey: activeLibraryBookmarkKey),
           let url = resolveLibraryBookmark(bookmark),
           FileManager.default.fileExists(atPath: url.path) {
            // Persist path for Standard / in-session askEachLaunch so the next launch survives
            // bookmark resolution failures.
            let path = (url.path as NSString).standardizingPath
            UserDefaults.standard.set(path, forKey: activeLibraryPathKey)
            return path
        }

        // No active library: use startup home only. App Support exists solely when Standard was chosen
        // (`usesCustomLibraryHome` == false). Never fall back to App Support after Choose Folder.
        if usesCustomLibraryHome {
            return homeLibraryExists ? homeLibraryURL.path : nil
        }
        if FileManager.default.fileExists(atPath: defaultLibraryURL.path) {
            return defaultLibraryURL.path
        }
        return nil
    }

    /// Display name of the active library for window title (extension stripped). Empty when no library.
    static var activeLibraryDisplayName: String {
        if let path = databasePathForLaunch() {
            return displayName(for: URL(fileURLWithPath: path))
        }
        return ""
    }

    /// Returns display name for a library URL.
    private static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        for ext in [".machii", ".sqlite", ".db", ".sqlite3"] {
            if name.lowercased().hasSuffix(ext) {
                return String(name.dropLast(ext.count))
            }
        }
        return name
    }

    /// URL of the active library (for Save Copy, etc.). Nil when no library.
    static func activeLibraryURL() -> URL? {
        guard let path = databasePathForLaunch() else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Skagway-\(formatter.string(from: Date())).\(libraryFilenameExtension)"
    }

    /// Validates that the file is a valid Skagway library database (has video table).
    static func validateImportFile(at url: URL) throws {
        let db = try DatabaseQueue(path: url.path)
        _ = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM video") }
    }

    // MARK: - Bookmark / path helpers

    /// Resolve a saved bookmark. Tries plain resolution first (app is not sandboxed), then security-scope
    /// for older bookmarks created with `.withSecurityScope`.
    private static func resolveLibraryBookmark(_ data: Data) -> URL? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }
        return nil
    }

    private static func makeLibraryBookmark(for url: URL) -> Data? {
        // Non-sandboxed app: plain bookmarks survive rebuilds far more reliably than security-scoped ones.
        if let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static func setActiveLibraryPreferences(url: URL) {
        if let bookmark = makeLibraryBookmark(for: url) {
            UserDefaults.standard.set(bookmark, forKey: activeLibraryBookmarkKey)
        }
        if storesLocationAsBookmarkOnly {
            UserDefaults.standard.removeObject(forKey: activeLibraryPathKey)
        } else {
            let path = (url.path as NSString).standardizingPath
            UserDefaults.standard.set(path, forKey: activeLibraryPathKey)
        }
    }

    private static func clearActiveLibraryPreferences() {
        UserDefaults.standard.removeObject(forKey: activeLibraryBookmarkKey)
        UserDefaults.standard.removeObject(forKey: activeLibraryPathKey)
    }

    private static func refreshBookmarkIfNeeded(forPath path: String, isActive: Bool) {
        refreshBookmarkIfNeeded(for: URL(fileURLWithPath: path), isActive: isActive)
    }

    private static func refreshBookmarkIfNeeded(for url: URL, isActive: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let bookmark = makeLibraryBookmark(for: url) else { return }
        if isActive {
            UserDefaults.standard.set(bookmark, forKey: activeLibraryBookmarkKey)
        }
    }

    /// Drops plain library/cache/recent paths when Remember mode must stay bookmark-only.
    static func scrubPlainLocationPathsFromPrefs() {
        guard storesLocationAsBookmarkOnly else { return }
        UserDefaults.standard.removeObject(forKey: activeLibraryPathKey)
        UserDefaults.standard.removeObject(forKey: PrefsKeys.thumbnailCachePath)
        UserDefaults.standard.removeObject(forKey: recentLibraryPathsKey)
    }

    // MARK: - Recent Libraries

    /// Returns recent libraries. Paths are authoritative for Standard; Remember mode does not keep a path list.
    /// Only drops entries whose files are actually gone — never because a bookmark failed to resolve.
    static func recentLibraryItems() -> [RecentLibraryItem] {
        if storesLocationAsBookmarkOnly {
            scrubPlainLocationPathsFromPrefs()
            return []
        }

        migrateRecentBookmarksIntoPathsIfNeeded()

        var paths = UserDefaults.standard.stringArray(forKey: recentLibraryPathsKey) ?? []
        var result: [RecentLibraryItem] = []
        var keptPaths: [String] = []

        for path in paths {
            let standardized = (path as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: standardized) else { continue }
            if keptPaths.contains(standardized) { continue }
            keptPaths.append(standardized)
            let url = URL(fileURLWithPath: standardized)
            result.append(RecentLibraryItem(
                id: standardized,
                displayName: displayName(for: url),
                url: url
            ))
        }

        if keptPaths != paths {
            UserDefaults.standard.set(keptPaths, forKey: recentLibraryPathsKey)
        }

        // Keep bookmark blobs in sync when we can (non-fatal if creation fails).
        var bookmarks: [Data] = []
        for path in keptPaths.prefix(maxRecentLibraries) {
            if let data = makeLibraryBookmark(for: URL(fileURLWithPath: path)) {
                bookmarks.append(data)
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: recentLibraryBookmarksKey)

        return result
    }

    /// One-shot: pull paths out of legacy bookmark-only recents so rebuilds don’t erase history.
    private static func migrateRecentBookmarksIntoPathsIfNeeded() {
        if storesLocationAsBookmarkOnly { return }

        var paths = UserDefaults.standard.stringArray(forKey: recentLibraryPathsKey) ?? []
        let bookmarks = UserDefaults.standard.array(forKey: recentLibraryBookmarksKey) as? [Data] ?? []

        var changed = false
        for data in bookmarks {
            guard let url = resolveLibraryBookmark(data) else { continue }
            let path = (url.path as NSString).standardizingPath
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if !paths.contains(path) {
                paths.append(path)
                changed = true
            }
        }
        if changed {
            UserDefaults.standard.set(Array(paths.prefix(maxRecentLibraries)), forKey: recentLibraryPathsKey)
        }

        // Also migrate active bookmark → path once (even when recents are empty).
        if UserDefaults.standard.string(forKey: activeLibraryPathKey) == nil,
           let bookmark = UserDefaults.standard.data(forKey: activeLibraryBookmarkKey),
           let url = resolveLibraryBookmark(bookmark),
           FileManager.default.fileExists(atPath: url.path) {
            UserDefaults.standard.set((url.path as NSString).standardizingPath, forKey: activeLibraryPathKey)
        }
    }

    /// Adds a library URL to the recent list. Dedupes by path, trims to max.
    static func addToRecent(url: URL) {
        if storesLocationAsBookmarkOnly { return }

        let path = (url.path as NSString).standardizingPath
        var paths = UserDefaults.standard.stringArray(forKey: recentLibraryPathsKey) ?? []
        paths.removeAll { ($0 as NSString).standardizingPath == path }
        paths.insert(path, at: 0)
        paths = Array(paths.prefix(maxRecentLibraries))
        UserDefaults.standard.set(paths, forKey: recentLibraryPathsKey)

        if let bookmark = makeLibraryBookmark(for: url) {
            var kept: [Data] = []
            for data in UserDefaults.standard.array(forKey: recentLibraryBookmarksKey) as? [Data] ?? [] {
                guard let u = resolveLibraryBookmark(data),
                      (u.path as NSString).standardizingPath != path else { continue }
                kept.append(data)
            }
            kept.insert(bookmark, at: 0)
            UserDefaults.standard.set(Array(kept.prefix(maxRecentLibraries)), forKey: recentLibraryBookmarksKey)
        }
    }

    /// Switches to a library and restarts.
    static func switchToLibrary(_ item: RecentLibraryItem) {
        checkpointAndCleanWAL()
        let didStartAccess = item.url.startAccessingSecurityScopedResource()
        defer { if didStartAccess { item.url.stopAccessingSecurityScopedResource() } }
        syncCachePreferences(forLibraryURL: item.url)
        setActiveLibraryPreferences(url: item.url)
        if !promptsForLibraryEachLaunch {
            addToRecent(url: item.url)
        }
        clearUserClosedLibrary()
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// Clears all recent library bookmarks.
    static func clearRecentLibraries() {
        UserDefaults.standard.removeObject(forKey: recentLibraryBookmarksKey)
        UserDefaults.standard.removeObject(forKey: recentLibraryPathsKey)
    }

    /// Schedules the app to relaunch after this process terminates. Uses launchctl so the relaunch survives our exit.
    private static func relaunchAfterTerminate() {
        let appPath = Bundle.main.bundlePath
        let script = """
        #!/bin/bash
        sleep 2
        open "\(appPath)"
        launchctl remove com.machiilabs.skagway.relaunch 2>/dev/null || true
        """
        let scriptURL = dbDirectoryURL.appendingPathComponent("relaunch.sh", isDirectory: false)
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try? (scriptURL as NSURL).setResourceValue(true, forKey: .isExecutableKey)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = [
                "submit", "-l", "com.machiilabs.skagway.relaunch",
                "-o", dbDirectoryURL.appendingPathComponent("relaunch_out.log").path,
                "-e", dbDirectoryURL.appendingPathComponent("relaunch_err.log").path,
                "--", "/bin/bash", scriptURL.path
            ]
            try task.run()
        } catch {
            try? FileManager.default.removeItem(at: scriptURL)
        }
    }

    // MARK: - Save Copy

    /// Saves a copy of the current library to a user-chosen path. Does not switch.
    static func saveCopy(dbPool: DatabasePool) {
        guard let sourceURL = activeLibraryURL() else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = [libraryFilenameExtension]
        panel.nameFieldStringValue = defaultExportFileName()
        panel.title = "Save Copy"
        panel.message = "Saves one complete Skagway library file (.machii extension). Companion -wal / -shm files are temporary while Skagway is open and do not need to be copied."
        panel.showsTagField = false

        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        do {
            try dbPool.writeWithoutTransaction { db in try db.checkpoint(.truncate) }
            let fm = FileManager.default
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            // Drop stale sidecars next to an overwritten destination if any exist.
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: destURL.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.removeItem(at: side)
                }
            }
            try fm.copyItem(at: sourceURL, to: destURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Open Library

    /// Shows open panel and switches to the selected library.
    static func openLibraryFromUserSelection() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = [libraryFilenameExtension]
        panel.allowsOtherFileTypes = false
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open Library"
        panel.message = "Select a library file to open."

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            try validateImportFile(at: sourceURL)
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        syncCachePreferences(forLibraryURL: sourceURL)
        let item = RecentLibraryItem(
            id: sourceURL.path,
            displayName: sourceURL.lastPathComponent,
            url: sourceURL
        )
        switchToLibrary(item)
    }

    // MARK: - Create Library

    /// Creates the startup-home library if missing. Never overwrites an existing file.
    /// Standard home → App Support; custom home → chosen folder only (no App Support library).
    static func createHomeLibraryIfNeeded() {
        let fm = FileManager.default
        let destURL = homeLibraryURL
        try? fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: destURL.path) else {
            let alert = NSAlert()
            alert.messageText = "Library Already Exists"
            alert.informativeText = "A library already exists at \(homeLibraryPathForDisplay). Use Open Home Library to open it, or choose a different location with New Library…"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        do {
            try DatabaseMigration.createEmptyDatabase(at: destURL.path)
            clearUserClosedLibrary()
            setActiveLibraryPreferences(url: destURL)
            addToRecent(url: destURL)
            relaunchAfterTerminate()
            NSApplication.shared.terminate(nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Switches to the startup-home library and relaunches.
    static func openHomeLibrary() {
        if promptsForLibraryEachLaunch {
            openLibraryFromUserSelection()
            return
        }
        guard homeLibraryExists else {
            let alert = NSAlert()
            alert.messageText = "Home Library Not Found"
            alert.informativeText = "No library exists at \(homeLibraryPathForDisplay). Use Create Home Library to create one, or Change Library & Cache Location…"
            alert.alertStyle = .informational
            alert.runModal()
            return
        }
        if isHomeLibraryActive {
            return
        }
        checkpointAndCleanWAL()
        syncCachePreferences(forLibraryURL: homeLibraryURL)
        setActiveLibraryPreferences(url: homeLibraryURL)
        clearUserClosedLibrary()
        addToRecent(url: homeLibraryURL)
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// Creates a new empty library at user-chosen path and switches to it.
    static func createNewLibrary() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = [libraryFilenameExtension]
        panel.nameFieldStringValue = "New Library.\(libraryFilenameExtension)"
        panel.title = "New Library"
        panel.message = "Choose a location for the new library."
        panel.showsTagField = false

        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        let didStartAccess = destURL.startAccessingSecurityScopedResource()
        defer { if didStartAccess { destURL.stopAccessingSecurityScopedResource() } }

        do {
            try DatabaseMigration.createEmptyDatabase(at: destURL.path)
            syncCachePreferences(forLibraryURL: destURL)
            let item = RecentLibraryItem(
                id: destURL.path,
                displayName: destURL.lastPathComponent,
                url: destURL
            )
            switchToLibrary(item)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Close / Delete

    /// Closes the current library and relaunches to show landing. Keeps file on disk.
    static func closeLibrary() {
        checkpointAndCleanWAL()
        clearActiveLibraryPreferences()
        UserDefaults.standard.set(true, forKey: userClosedLibraryKey)
        UserDefaults.standard.synchronize()
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// Deletes the library file from disk, removes from recent, and relaunches. Requires confirmation.
    static func deleteThisLibrary(at url: URL) {
        let fm = FileManager.default
        for ext in ["", "-wal", "-shm"] {
            let path = url.path + ext
            if fm.fileExists(atPath: path) {
                try? fm.removeItem(atPath: path)
            }
        }
        removeFromRecent(url: url)
        let standardized = (url.path as NSString).standardizingPath
        if let active = UserDefaults.standard.string(forKey: activeLibraryPathKey),
           (active as NSString).standardizingPath == standardized {
            clearActiveLibraryPreferences()
        } else if databasePathForLaunch() == url.path {
            clearActiveLibraryPreferences()
        }
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// Removes a library URL from the recent list.
    static func removeFromRecent(url: URL) {
        let path = (url.path as NSString).standardizingPath
        var paths = UserDefaults.standard.stringArray(forKey: recentLibraryPathsKey) ?? []
        paths.removeAll { ($0 as NSString).standardizingPath == path }
        UserDefaults.standard.set(paths, forKey: recentLibraryPathsKey)

        var kept: [Data] = []
        for data in UserDefaults.standard.array(forKey: recentLibraryBookmarksKey) as? [Data] ?? [] {
            guard let u = resolveLibraryBookmark(data),
                  (u.path as NSString).standardizingPath != path else { continue }
            kept.append(data)
        }
        UserDefaults.standard.set(kept, forKey: recentLibraryBookmarksKey)
    }

    // MARK: - Library home setup (privacy / location)

    /// Whether the one-time library-home chooser has been completed.
    static var hasCompletedLibraryHomeSetup: Bool {
        UserDefaults.standard.bool(forKey: PrefsKeys.didCompleteLibraryHomeSetup)
    }

    static func markLibraryHomeSetupComplete() {
        UserDefaults.standard.set(true, forKey: PrefsKeys.didCompleteLibraryHomeSetup)
    }

    /// Standard home: App Support library + `~/Library/Caches/Skagway/Skagway-cache`. Never deletes an existing library.
    static func useStandardLibraryHome() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true)
        clearThumbnailCachePreferences()
        clearUserClosedLibrary()

        if !fm.fileExists(atPath: defaultLibraryURL.path) {
            do {
                try DatabaseMigration.createEmptyDatabase(at: defaultLibraryURL.path)
            } catch {
                NSAlert(error: error).runModal()
                return
            }
        }

        clearActiveLibraryPreferences()
        addToRecent(url: defaultLibraryURL)
        libraryHomeAccessMode = .standard
        markLibraryHomeSetupComplete()
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// Quits and shows the library/cache location chooser again. Does not delete files on disk.
    static func changeLibraryAndCacheLocation() {
        let alert = NSAlert()
        alert.messageText = "Change Library & Cache Location?"
        alert.informativeText = """
        Skagway will quit and ask again where to store the library and thumbnail cache, and (for a chosen folder) whether to remember that location.

        Your library files and thumbnails on disk are not deleted. The thumbnail cache location is shared by every library you open — choosing a folder sets that one cache for the whole app.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        checkpointAndCleanWAL()
        UserDefaults.standard.set(false, forKey: PrefsKeys.didCompleteLibraryHomeSetup)
        UserDefaults.standard.removeObject(forKey: PrefsKeys.libraryHomeAccessMode)
        UserDefaults.standard.synchronize()
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// Folder picker only — caller shows the remember vs ask-each-launch step next.
    static func pickCustomLibraryHomeFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Library Location"
        panel.message = "Choose a folder for the library database and the app-wide cache (a Skagway-cache subfolder). If a library or cache is already there, Skagway will use it as-is."

        guard panel.runModal() == .OK, let folderURL = panel.url else { return nil }

        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer { if didStartAccess { folderURL.stopAccessingSecurityScopedResource() } }
        return folderURL
    }

    /// Custom home folder: `Skagway.machii` (or any existing `*.machii`) + co-located `Skagway-cache/`.
    /// Existing library/cache in the folder are reused — never overwritten or deleted.
    static func activateCustomLibraryHome(_ folderURL: URL, accessMode: LibraryHomeAccessMode) throws {
        precondition(accessMode == .rememberBookmark || accessMode == .askEachLaunch)

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw LibraryHomeSetupError.notAFolder
        }

        let cacheURL = ThumbnailService.coLocatedCacheDirectory(inLibraryHome: folderURL)
        try fm.createDirectory(at: cacheURL, withIntermediateDirectories: true)

        let libraryURL: URL
        if let existing = findLibraryFile(in: folderURL) {
            try validateImportFile(at: existing)
            libraryURL = existing
        } else if let source = migrationSourceLibraryURL() {
            checkpointAndCleanWAL()
            libraryURL = folderURL.appendingPathComponent(defaultLibraryFileName, isDirectory: false)
            if fm.fileExists(atPath: libraryURL.path) {
                try validateImportFile(at: libraryURL)
            } else {
                try fm.copyItem(at: source, to: libraryURL)
                try? copySQLiteSidecars(from: source, to: libraryURL)
                try validateImportFile(at: libraryURL)
            }
        } else {
            libraryURL = folderURL.appendingPathComponent(defaultLibraryFileName, isDirectory: false)
            try DatabaseMigration.createEmptyDatabase(at: libraryURL.path)
        }

        libraryHomeAccessMode = accessMode
        clearUserClosedLibrary()

        switch accessMode {
        case .rememberBookmark:
            clearRecentLibraries()
            setThumbnailCachePreferences(cacheURL)
            setActiveLibraryPreferences(url: libraryURL)
            scrubPlainLocationPathsFromPrefs()
        case .askEachLaunch:
            // No location residue on the boot disk — open the library explicitly each launch.
            clearActiveLibraryPreferences()
            clearThumbnailCachePreferences()
            clearRecentLibraries()
        case .standard:
            break
        }

        markLibraryHomeSetupComplete()
        relaunchAfterTerminate()
        NSApplication.shared.terminate(nil)
    }

    /// When opening a library under a custom home, point the app-wide cache at that folder’s Skagway-cache.
    static func syncCachePreferences(forLibraryURL url: URL) {
        guard usesCustomLibraryHome else { return }
        let folder = url.deletingLastPathComponent()
        let cacheURL = ThumbnailService.coLocatedCacheDirectory(inLibraryHome: folder)
        setThumbnailCachePreferences(cacheURL)
    }

    /// Clears remembered library/cache paths after a prompt-each-launch session (quit or next launch).
    static func clearSessionLocationPreferencesIfNeeded() {
        guard promptsForLibraryEachLaunch else { return }
        clearActiveLibraryPreferences()
        clearThumbnailCachePreferences()
    }

    /// Prefer `Skagway.machii`, else the first `*.machii` in the folder (non-recursive).
    static func findLibraryFile(in folderURL: URL) -> URL? {
        let fm = FileManager.default
        let preferred = folderURL.appendingPathComponent(defaultLibraryFileName, isDirectory: false)
        if fm.fileExists(atPath: preferred.path) {
            return preferred
        }
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return contents.first {
            $0.pathExtension.lowercased() == libraryFilenameExtension
        }
    }

    private static func migrationSourceLibraryURL() -> URL? {
        if let path = UserDefaults.standard.string(forKey: activeLibraryPathKey),
           FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Only Standard setup has an App Support library; custom home never uses it as a source.
        if !usesCustomLibraryHome,
           FileManager.default.fileExists(atPath: defaultLibraryURL.path) {
            return defaultLibraryURL
        }
        return nil
    }

    private static func copySQLiteSidecars(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let src = URL(fileURLWithPath: source.path + suffix)
            let dst = URL(fileURLWithPath: dest.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            if fm.fileExists(atPath: dst.path) { continue }
            try fm.copyItem(at: src, to: dst)
        }
    }

    private static func setThumbnailCachePreferences(_ url: URL) {
        if let bookmark = makeLibraryBookmark(for: url) {
            UserDefaults.standard.set(bookmark, forKey: PrefsKeys.thumbnailCacheBookmark)
        }
        if storesLocationAsBookmarkOnly {
            UserDefaults.standard.removeObject(forKey: PrefsKeys.thumbnailCachePath)
        } else {
            let path = (url.path as NSString).standardizingPath
            UserDefaults.standard.set(path, forKey: PrefsKeys.thumbnailCachePath)
        }
    }

    private static func clearThumbnailCachePreferences() {
        UserDefaults.standard.removeObject(forKey: PrefsKeys.thumbnailCachePath)
        UserDefaults.standard.removeObject(forKey: PrefsKeys.thumbnailCacheBookmark)
    }

    // MARK: - Launch

    /// Run at app launch. Ensures App Support folder exists. Does not create a default library.
    /// Does not touch the Open Recent list (Clear Menu must stay cleared across launches).
    static func prepareDatabaseForLaunch() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dbDirectoryURL, withIntermediateDirectories: true)
        scrubPlainLocationPathsFromPrefs()

        try? fm.removeItem(at: dbDirectoryURL.appendingPathComponent("relaunch.sh", isDirectory: false))
        try? fm.removeItem(at: dbDirectoryURL.appendingPathComponent("relaunch_out.log", isDirectory: false))
        try? fm.removeItem(at: dbDirectoryURL.appendingPathComponent("relaunch_err.log", isDirectory: false))
    }
}

enum LibraryHomeSetupError: LocalizedError {
    case notAFolder

    var errorDescription: String? {
        switch self {
        case .notAFolder:
            return "Choose a folder for the library and thumbnail cache."
        }
    }
}
