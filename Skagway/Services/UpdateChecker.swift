import Foundation
import Sparkle

/// Thin wrapper around Sparkle’s standard updater UI.
///
/// Automatic checks default **off** (`SUEnableAutomaticChecks` in Info.plist). Enabling the
/// Settings toggle sets `automaticallyChecksForUpdates` (persisted by Sparkle). Manual
/// **Check for Updates…** always works when a feed is reachable.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Menu / button action — shows Sparkle’s standard check UI.
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Bound from Settings. Sparkle persists this in the app’s user defaults.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
