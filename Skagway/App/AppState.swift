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

    init() {
        LegacyRenameMigrator.migrateIfNeeded()
        thumbnailService = ThumbnailService()
        var db: DatabaseManager?
        var vm: LibraryViewModel?
        do {
            _ = try DatabaseExportImport.prepareDatabaseForLaunch()
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
        } catch {
            // File deleted, corrupted, or no library — show landing
        }
        dbManager = db
        libraryViewModel = vm
        DatabaseExportImport.activeDbPool = db?.dbPool

        // `NSApp` / shared application is not ready during `App.init` — applying here crashes (IUO nil).
        DispatchQueue.main.async {
            Self.applyDarkAppearance()
        }
    }

    /// Skagway is dark-only; lock `NSApp` so system light mode cannot wash out the UI.
    static func applyDarkAppearance() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
}
