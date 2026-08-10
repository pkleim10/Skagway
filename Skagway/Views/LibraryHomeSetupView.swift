import SwiftUI

/// Privacy / library-home chooser shown before Landing or the library UI.
/// Can be shown again via File → Change Library Location…
struct LibraryHomeSetupView: View {
    /// After Choose Folder…, pick cache placement then remember-bookmark vs open-each-launch.
    @State private var pendingCustomFolder: URL?
    @State private var pendingCachePlacement: DatabaseExportImport.LibraryCachePlacement?

    var body: some View {
        Group {
            if let folder = pendingCustomFolder {
                if let placement = pendingCachePlacement {
                    accessModeStep(folder: folder, cachePlacement: placement)
                } else {
                    cachePlacementStep(folder: folder)
                }
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
                    detail: "Skagway keeps its own library catalog (paths, tags, ratings, collections, play history) and thumbnail cache on disk. Each library stores its own cache location, so opening one library never depends on another volume’s cache."
                )
                privacyBullet(
                    title: "Media on an encrypted volume",
                    detail: "Choose Folder… and co-locate the library and cache on the same encrypted volume as your media. When that volume is locked or offline, that library’s catalog and previews are unavailable — other libraries keep working with their own caches."
                )
                privacyBullet(
                    title: "Use defaults on this Mac",
                    detail: "Library in Application Support and cache in system Caches — no further choices. Best when you are not putting the catalog on an encrypted volume."
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
                        pendingCachePlacement = nil
                    }
                }) {
                    Label("Choose Folder…", systemImage: "folder.badge.gearshape")
                        .frame(maxWidth: 340)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)
                .help("Pick a library folder, then choose where this library’s thumbnail cache lives.")
            }
        }
    }

    private func cachePlacementStep(folder: URL) -> some View {
        VStack(spacing: AppSpacing.xxxl) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: AppSpacing.sm) {
                Text("Where should this library’s cache live?")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .multilineTextAlignment(.center)

                Text(DatabaseExportImport.pathForDisplay(folder))
                    .font(.callout.monospaced())
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                Text("Each library keeps its own thumbnail cache. This choice is stored in the library file.")
                    .font(.body)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                privacyBullet(
                    title: "Co-locate with library (recommended)",
                    detail: "Creates a Skagway-cache folder next to the library. Best when the library sits on the same volume as your media (including encrypted volumes)."
                )
                privacyBullet(
                    title: "System default",
                    detail: "Stores this library’s cache under ~/Library/Caches/Skagway. Useful when the library folder is on a volume you prefer not to fill with previews."
                )
                privacyBullet(
                    title: "Choose a folder…",
                    detail: "Pick any folder. Skagway will read and write this library’s thumbnails there."
                )
            }
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.xxl)
            .frame(maxWidth: 560)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay(cardStroke)

            VStack(spacing: AppSpacing.md) {
                Button(action: { pendingCachePlacement = .coLocated }) {
                    Label("Co-locate with library", systemImage: "folder.fill")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button(action: { pendingCachePlacement = .systemDefault }) {
                    Label("System default", systemImage: "internaldrive")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button(action: {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.canCreateDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.title = "Choose Thumbnail Cache Folder"
                    panel.message = "Skagway will store this library’s thumbnails in the folder you choose."
                    if panel.runModal() == .OK, let url = panel.url {
                        pendingCachePlacement = .custom(url)
                    }
                }) {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button("Back") {
                    pendingCustomFolder = nil
                    pendingCachePlacement = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, AppSpacing.sm)
            }
        }
    }

    private func accessModeStep(
        folder: URL,
        cachePlacement: DatabaseExportImport.LibraryCachePlacement
    ) -> some View {
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
                    detail: "Skagway stores no library location on the boot disk. Each launch you open the library yourself (File → Open Library…). The cache location stays inside the library file."
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
                    commitCustomHome(folder: folder, mode: .rememberBookmark, cachePlacement: cachePlacement)
                }) {
                    Label("Remember this location", systemImage: "bookmark.fill")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button(action: {
                    commitCustomHome(folder: folder, mode: .askEachLaunch, cachePlacement: cachePlacement)
                }) {
                    Label("Ask every time I open Skagway", systemImage: "hand.raised")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.bordered)
                .tint(Color.appAccent)
                .controlSize(.large)

                Button("Back") {
                    pendingCachePlacement = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, AppSpacing.sm)
            }
        }
    }

    private func commitCustomHome(
        folder: URL,
        mode: DatabaseExportImport.LibraryHomeAccessMode,
        cachePlacement: DatabaseExportImport.LibraryCachePlacement
    ) {
        do {
            try DatabaseExportImport.activateCustomLibraryHome(
                folder,
                accessMode: mode,
                cachePlacement: cachePlacement
            )
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
