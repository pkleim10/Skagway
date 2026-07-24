import SwiftUI

/// Privacy / library-home chooser shown before Landing or the library UI.
/// Can be shown again via File → Change Library & Cache Location…
struct LibraryHomeSetupView: View {
    /// After Choose Folder…, ask remember-bookmark vs open-each-launch.
    @State private var pendingCustomFolder: URL?

    var body: some View {
        Group {
            if let folder = pendingCustomFolder {
                accessModeStep(folder: folder)
            } else {
                locationStep
            }
        }
        .padding(AppSpacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    private var locationStep: some View {
        VStack(spacing: AppSpacing.xxxl) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: AppSpacing.sm) {
                Text("Choose where Skagway stores its data")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Skagway is not a vault. It does not modify or protect your source media in any way — your video files stay where you put them, unchanged.")
                    .font(.title3)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                privacyBullet(
                    title: "Nothing leaves your Mac",
                    detail: "None of your data is ever sent to Mach II Labs or anywhere else. No account, no cloud sync, no usage analytics. Optional update checks (off by default) only ask whether a newer Skagway build exists — they do not upload your library or media."
                )
                privacyBullet(
                    title: "You control the catalog and cache",
                    detail: "Skagway keeps its own library catalog (paths, tags, ratings, collections, play history) and thumbnail cache on disk. You choose where those live."
                )
                privacyBullet(
                    title: "Media on an encrypted volume",
                    detail: "Choose Folder… and put the library and cache on the same encrypted volume as your media. When that volume is locked or offline, Skagway’s catalog and previews are unavailable too — not just the videos."
                )
                privacyBullet(
                    title: "Media on a normal volume",
                    detail: "Use standard location on this Mac. The library goes in Application Support and the cache in Caches — the usual places for app data."
                )
                privacyBullet(
                    title: "One cache for the whole app",
                    detail: "Whichever option you pick, that thumbnail cache is shared by every library you open later. Existing files in a chosen folder are never wiped. You can change this later from File → Change Library & Cache Location…"
                )
            }
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.xxl)
            .frame(maxWidth: 560)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay(cardStroke)

            VStack(spacing: AppSpacing.md) {
                Button(action: { DatabaseExportImport.useStandardLibraryHome() }) {
                    Label("Use standard location on this Mac", systemImage: "internaldrive")
                        .frame(maxWidth: 340)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)
                .help(DatabaseExportImport.defaultLibraryPathForDisplay)

                Button(action: {
                    if let folder = DatabaseExportImport.pickCustomLibraryHomeFolder() {
                        pendingCustomFolder = folder
                    }
                }) {
                    Label("Choose Folder…", systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: 340)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)
                .help("Best when your media is on an encrypted volume — library and Skagway-cache stay with that volume.")
            }
        }
    }

    private func accessModeStep(folder: URL) -> some View {
        VStack(spacing: AppSpacing.xxxl) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: AppSpacing.sm) {
                Text("How should Skagway find this library?")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .multilineTextAlignment(.center)

                Text(DatabaseExportImport.pathForDisplay(folder))
                    .font(.callout.monospaced())
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                privacyBullet(
                    title: "Remember this location",
                    detail: "Skagway stores opaque bookmarks only in this Mac’s preferences (~/Library/Preferences/com.machiilabs.skagway.plist) — no plain folder paths, and not a separate bookmark file. When the volume is mounted, the library can open automatically. A determined person with access to this Mac might still inspect that prefs file; they will not see your catalog or cache while the volume is locked."
                )
                privacyBullet(
                    title: "Ask every time I open Skagway",
                    detail: "Skagway stores no library or cache location on the boot disk. Each launch you open the library yourself (File → Open Library…). Maximum privacy for where you keep Skagway’s data; slightly more friction."
                )
            }
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.xxl)
            .frame(maxWidth: 560)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay(cardStroke)

            VStack(spacing: AppSpacing.md) {
                Button(action: {
                    commitCustomHome(folder: folder, mode: .rememberBookmark)
                }) {
                    Label("Remember this location", systemImage: "bookmark.fill")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button(action: {
                    commitCustomHome(folder: folder, mode: .askEachLaunch)
                }) {
                    Label("Ask every time I open Skagway", systemImage: "hand.raised")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button("Back") {
                    pendingCustomFolder = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, AppSpacing.sm)
            }
        }
    }

    private func commitCustomHome(folder: URL, mode: DatabaseExportImport.LibraryHomeAccessMode) {
        do {
            try DatabaseExportImport.activateCustomLibraryHome(folder, accessMode: mode)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            .fill(Material.appSubtleGlass)
            .background(Color.appSurface.opacity(0.75))
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            .stroke(Color.appAccent.opacity(0.15), lineWidth: 1)
    }

    private func privacyBullet(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)
            Text(detail)
                .font(.body)
                .foregroundStyle(Color.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
