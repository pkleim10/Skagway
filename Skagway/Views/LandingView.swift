import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: AppSpacing.xxxl) {
            // App icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)

            // Title + subtitle
            VStack(spacing: AppSpacing.sm) {
                Text("Skagway")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.appTextPrimary)

                Text(
                    DatabaseExportImport.promptsForLibraryEachLaunch
                        ? "Open your library to continue — its location is not remembered on this Mac"
                        : "Create or open a library to get started"
                )
                    .font(.title3)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            // Main action card
            VStack(spacing: AppSpacing.lg) {
                // Primary create actions
                VStack(spacing: AppSpacing.md) {
                    if DatabaseExportImport.promptsForLibraryEachLaunch {
                        Button(action: { DatabaseExportImport.openLibraryFromUserSelection() }) {
                            Label("Open library…", systemImage: "folder")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                        .controlSize(.large)
                        .help("Choose your .machii on the volume where you keep the library and Skagway-cache.")

                        Button(action: { DatabaseExportImport.createNewLibrary() }) {
                            Label("Create library…", systemImage: "folder.badge.plus")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appAccent)
                        .controlSize(.large)
                    } else if DatabaseExportImport.homeLibraryExists {
                        Button(action: {
                            DatabaseExportImport.openHomeLibrary()
                            appState.noteRecentLibrariesChanged()
                        }) {
                            Label("Open home library", systemImage: "building.columns.fill")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                        .controlSize(.large)
                        .help(DatabaseExportImport.homeLibraryPathForDisplay)

                        Button(action: { DatabaseExportImport.createNewLibrary() }) {
                            Label("Create library…", systemImage: "folder.badge.plus")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appAccent)
                        .controlSize(.large)

                        Button(action: { DatabaseExportImport.openLibraryFromUserSelection() }) {
                            Label("Open library…", systemImage: "folder")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appAccent)
                        .controlSize(.large)
                    } else {
                        Button(action: { DatabaseExportImport.createHomeLibraryIfNeeded() }) {
                            Label("Create home library", systemImage: "plus.circle.fill")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                        .controlSize(.large)
                        .help("Creates \(DatabaseExportImport.homeLibraryPathForDisplay)")

                        Button(action: { DatabaseExportImport.createNewLibrary() }) {
                            Label("Create library…", systemImage: "folder.badge.plus")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appAccent)
                        .controlSize(.large)

                        Button(action: { DatabaseExportImport.openLibraryFromUserSelection() }) {
                            Label("Open library…", systemImage: "folder")
                                .frame(maxWidth: 260)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appAccent)
                        .controlSize(.large)
                    }
                }

                // Recents — bookmark-backed in Remember mode; path-backed otherwise.
                if !appState.recentLibraryItems().isEmpty {
                    Rectangle()
                        .fill(Color.appDivider)
                        .frame(height: 1)
                        .padding(.vertical, AppSpacing.xs)

                    Text("Open recent")
                        .font(.headline)
                        .foregroundStyle(Color.appTextSecondary)

                    VStack(spacing: AppSpacing.xs) {
                        ForEach(appState.recentLibraryItems()) { item in
                            Button(action: { DatabaseExportImport.switchToLibrary(item) }) {
                                HStack {
                                    Label(item.displayName, systemImage: "clock.arrow.circlepath")
                                    Spacer()
                                }
                                .frame(maxWidth: 260)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .fill(Color.appHover)
                                )
                                // Must be inside the label, not chained after .buttonStyle(.plain)
                                // below — a .plain button's hit-testing is otherwise limited to the
                                // rendered icon/text glyphs, leaving the gap and the Spacer's stretch
                                // area unclickable despite looking like part of the row.
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.appTextPrimary)
                        }
                    }
                }
            }
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(Material.appSubtleGlass)
                    .background(Color.appSurface.opacity(0.75))
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .stroke(Color.appAccent.opacity(0.15), lineWidth: 1)
            )
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}
