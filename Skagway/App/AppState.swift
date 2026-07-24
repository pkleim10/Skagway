import AppKit
import Foundation
import GRDB

@MainActor
@Observable
final class AppState {
    let dbManager: DatabaseManager?
    let libraryViewModel: LibraryViewModel?
    let thumbnailService: ThumbnailService

    var hasLibrary: Bool { dbManager != nil }

    /// Bumped when Open Recent changes so File menu / Landing refresh (UserDefaults alone does not invalidate SwiftUI commands).
    private(set) var recentLibrariesEpoch: Int = 0

    init() {
        LegacyRenameMigrator.migrateIfNeeded()
        thumbnailService = ThumbnailService()
        var db: DatabaseManager?
        var vm: LibraryViewModel?
        do {
            _ = try DatabaseExportImport.prepareDatabaseForLaunch()
            // Hold off opening a library until the one-time home/privacy chooser is done.
            if DatabaseExportImport.hasCompletedLibraryHomeSetup {
                // askEachLaunch: paths exist only for the current session (cleared on quit).
                // rememberBookmark / standard: paths persist across launches.
                let userClosed = DatabaseExportImport.userClosedLibrary
                DatabaseExportImport.clearUserClosedLibrary()
                if !userClosed, let path = DatabaseExportImport.databasePathForLaunch() {
                    let manager = try DatabaseManager(path: path)
                    db = manager
                    vm = LibraryViewModel(
                        dbPool: manager.dbPool,
                        thumbnailService: thumbnailService
                    )
                }
            }
        } catch {
            // File deleted, corrupted, or no library — show landing / setup
        }
        dbManager = db
        libraryViewModel = vm
        DatabaseExportImport.activeDbPool = db?.dbPool

        // `NSApp` / shared application is not ready during `App.init` — defer Sparkle + appearance.
        DispatchQueue.main.async {
            // Start Sparkle after NSApp exists (auto-check stays off until Settings enables it).
            _ = UpdateChecker.shared
            Self.applyDarkAppearance()
        }
    }

    /// Recent libraries for menus/landing. Reads `recentLibrariesEpoch` so observers refresh after Clear Menu.
    func recentLibraryItems() -> [RecentLibraryItem] {
        _ = recentLibrariesEpoch
        return DatabaseExportImport.recentLibraryItems()
    }

    func clearRecentLibraries() {
        DatabaseExportImport.clearRecentLibraries()
        recentLibrariesEpoch &+= 1
    }

    /// Call after an in-process Open Recent mutation (e.g. Open Home Library when already open).
    func noteRecentLibrariesChanged() {
        recentLibrariesEpoch &+= 1
    }

    /// Skagway is dark-only; lock `NSApp` so system light mode cannot wash out the UI.
    static func applyDarkAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
}
