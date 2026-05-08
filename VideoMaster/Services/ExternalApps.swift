import AppKit
import Foundation

/// Utilities for handing off videos to well-known sibling apps.
///
/// Today this is just Submarine (the batch-subtitle generator at
/// `com.kleimeyer.submarine`), but the same pattern generalizes: look up the
/// app via bundle id so we never hardcode `/Applications` paths, and pass all
/// URLs in a single `NSWorkspace.open` call so the target receives them as one
/// `application(_:open:)` batch.
enum ExternalApps {
    /// Bundle identifier of the Submarine app (set in `Submarine/project.yml`).
    static let submarineBundleIdentifier = "com.kleimeyer.submarine"

    /// Resolves the installed Submarine bundle, or `nil` if Launch Services
    /// doesn't know about it. Uses the modern (non-deprecated) URL-based API.
    static var submarineAppURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: submarineBundleIdentifier)
    }

    /// True when Submarine is installed and Launch Services can find it.
    /// Cheap enough to call on every context-menu build.
    static var isSubmarineInstalled: Bool {
        submarineAppURL != nil
    }

    /// Opens the given video URLs in Submarine as a single batch. No-op on
    /// empty input or when Submarine isn't installed.
    ///
    /// Targets the running instance's bundleURL when Submarine is already open
    /// so Launch Services routes to it instead of spawning a second copy.
    /// `createsNewApplicationInstance = false` is the critical flag — without
    /// it NSWorkspace ignores LSMultipleInstancesProhibited and always launches
    /// fresh regardless of which bundleURL is passed.
    static func openInSubmarine(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let appURL = NSRunningApplication
            .runningApplications(withBundleIdentifier: submarineBundleIdentifier)
            .first?.bundleURL ?? submarineAppURL
        guard let appURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
    }
}
