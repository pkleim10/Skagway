import AppKit
import SwiftUI

@main
struct VideoMasterApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    DatabaseExportImport.checkpointAndCleanWAL()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("List View") {
                    appState.libraryViewModel?.scrollToSelectedOnViewSwitch = true
                    appState.libraryViewModel?.viewMode = .list
                    appState.libraryViewModel?.savePreferences()
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!appState.hasLibrary)

                Button("Wall View") {
                    appState.libraryViewModel?.scrollToSelectedOnViewSwitch = true
                    appState.libraryViewModel?.viewMode = .grid
                    appState.libraryViewModel?.savePreferences()
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appState.hasLibrary)

                Divider()

                Button("Scroll to Selection") {
                    appState.libraryViewModel?.scrollToSelected()
                }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(appState.libraryViewModel?.selectedVideoIds.isEmpty != false)

                Button("Surprise Me!") {
                    appState.libraryViewModel?.surpriseMePickRandom()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.libraryViewModel?.filteredVideos.isEmpty ?? true)

                Button("Clear Filters") {
                    appState.libraryViewModel?.clearFilters()
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!appState.hasLibrary
                    || ((appState.libraryViewModel?.selectedTagIds.isEmpty ?? true)
                        && !(appState.libraryViewModel?.isRatingFilterActive ?? false)))

                Button("Toggle Thumbnail / Filmstrip") {
                    appState.libraryViewModel?.showThumbnailInDetail.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!appState.hasLibrary)

                Divider()

                Button("Compact") {
                    guard let vm = appState.libraryViewModel else { return }
                    if vm.isPlayerFullScreen { vm.isPlayerFullScreen = false }
                    vm.playerSizeIsCompact = true
                    vm.playerLastWasFullScreen = false
                    vm.playerFloatingPosition = nil   // compact always anchors top-right
                }
                .keyboardShortcut("c", modifiers: [.command, .control])
                .disabled(appState.libraryViewModel?.isPlayingInline != true)

                Button("Windowed") {
                    guard let vm = appState.libraryViewModel else { return }
                    if vm.isPlayerFullScreen { vm.isPlayerFullScreen = false }
                    vm.playerSizeIsCompact = false
                    vm.playerLastWasFullScreen = false
                }
                .keyboardShortcut("w", modifiers: [.command, .control])
                .disabled(appState.libraryViewModel?.isPlayingInline != true)

                Button("Toggle Full Screen") {
                    appState.libraryViewModel?.isPlayerFullScreen.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
                .disabled(appState.libraryViewModel?.isPlayingInline != true)

                // Restart from Beginning is reachable via ⌥-Space while a video is playing
                // (see the Space key handler in ContentView); the menu item stays for discoverability.
                Button("Restart from Beginning") {
                    appState.libraryViewModel?.playback.restartFromBeginning()
                }
                .disabled(appState.libraryViewModel?.isPlayingInline != true)

                Button("Make Thumbnail from Current Frame") {
                    appState.libraryViewModel?.playback.makeThumbnailFromCurrentFrame()
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
                .disabled(appState.libraryViewModel?.isPlayingInline != true)
            }
            // Fully replaces .pasteboard rather than composing "default + custom" via `after:` --
            // that approach previously produced a real, structural duplicate (the default group's
            // own Select All, stacked with a custom one) because its exact default contents aren't
            // something we control or fully know ahead of time. Specifying every item here removes
            // that ambiguity entirely.
            //
            // Cut/Copy/Paste forward to the standard responder-chain actions (same behavior as the
            // system default) so they still work correctly wherever a text field is focused (rename,
            // notes, custom metadata fields, search) -- nothing in the app implements clipboard
            // operations on videos themselves, but these are real, working text-editing commands,
            // not dead weight.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(Selector(("cut:")), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button("Copy") {
                    NSApp.sendAction(Selector(("copy:")), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button("Paste") {
                    NSApp.sendAction(Selector(("paste:")), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Divider()

                // Select All routes through the responder chain first — which is exactly what the
                // system's own Edit ▸ Select All is (a nil-targeted `selectAll:`): a focused text
                // field selects its own text (rename, notes, custom fields, search), List's table
                // selects all rows. Only when nothing in the chain claims the action does ⌘A mean
                // "select all videos." The decision MUST happen here at action time — gating via
                // `.disabled(...)` on the current first responder cannot work, because SwiftUI
                // only re-evaluates these commands when *observed* state changes, and AppKit
                // focus is not observable state, so such a check is permanently stale. (That
                // stale check is also why ⌘A kept stealing "select all text" from focused fields
                // no matter how the key monitor's deferral logic was adjusted.)
                Button("Select All") {
                    if !NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) {
                        appState.libraryViewModel?.selectAllVideos()
                    }
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect All") {
                    appState.libraryViewModel?.deselectAllVideos()
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(appState.libraryViewModel?.selectedVideoIds.isEmpty != false)

                Divider()

                Button("Delete\u{2026}") {
                    guard let vm = appState.libraryViewModel,
                          !vm.selectedVideoIds.isEmpty
                    else { return }
                    if vm.confirmDeletions {
                        vm.pendingDeleteIds = vm.selectedVideoIds
                        vm.showDeleteConfirmation = true
                    } else {
                        let ids = vm.selectedVideoIds
                        Task { await vm.deleteVideos(ids) }
                    }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.libraryViewModel?.selectedVideoIds.isEmpty != false)

                Button("Remove from Library") {
                    guard let vm = appState.libraryViewModel,
                          !vm.selectedVideoIds.isEmpty
                    else { return }
                    let ids = vm.selectedVideoIds
                    Task { await vm.removeVideosFromLibrary(ids) }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(appState.libraryViewModel?.selectedVideoIds.isEmpty != false)
            }
            // These default groups (Undo/Redo, Find/Spelling/Substitutions/Transformations/Speech,
            // the entire Format menu, Print) have no relevance to a video library and nothing in
            // the app implements their underlying actions — replacing each with empty content
            // removes the dead menu clutter instead of leaving it permanently disabled.
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .textEditing) { }
            CommandGroup(replacing: .textFormatting) { }
            CommandGroup(replacing: .printItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("About VideoMaster") {
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .version: "build \(build)"
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Folder\u{2026}") {
                    appState.libraryViewModel?.showFolderPicker()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!appState.hasLibrary)

                Button("Import New") {
                    Task { await appState.libraryViewModel?.importNew() }
                }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!appState.hasLibrary || (appState.libraryViewModel?.isScanning ?? false))

                Button("Scan for Subtitles") {
                    Task { await appState.libraryViewModel?.scanForSubtitles() }
                }
                .disabled(!appState.hasLibrary
                    || (appState.libraryViewModel?.isScanning ?? false)
                    || (appState.libraryViewModel?.videos.isEmpty ?? true))
            }
            CommandGroup(replacing: .importExport) {
                Button("Play in External Player") {
                    guard let vm = appState.libraryViewModel,
                          let videoId = vm.selectedVideoIds.first,
                          let video = vm.filteredVideos.first(where: { $0.id == videoId })
                    else { return }
                    NSWorkspace.shared.open(video.url)
                    Task { await vm.recordPlay(for: video) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.libraryViewModel?.selectedVideoIds.first == nil)

                Button("Show in Finder") {
                    guard let vm = appState.libraryViewModel,
                          let videoId = vm.selectedVideoIds.first,
                          let video = vm.filteredVideos.first(where: { $0.id == videoId })
                    else { return }
                    NSWorkspace.shared.selectFile(video.filePath, inFileViewerRootedAtPath: "")
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(appState.libraryViewModel?.selectedVideoIds.first == nil)

                if let vm = appState.libraryViewModel,
                   let videoId = vm.selectedVideoIds.first,
                   let video = vm.filteredVideos.first(where: { $0.id == videoId })
                {
                    Menu("Open With") {
                        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: video.url)
                        ForEach(appURLs, id: \.self) { appURL in
                            Button(appURL.deletingPathExtension().lastPathComponent) {
                                NSWorkspace.shared.open(
                                    [video.url],
                                    withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration()
                                )
                                Task { await vm.recordPlay(for: video) }
                            }
                        }
                    }
                }

                Divider()

                if !DatabaseExportImport.defaultLibraryExists {
                    Button("Create library in default location") {
                        DatabaseExportImport.createLibraryInDefaultLocation()
                    }
                    .disabled(appState.hasLibrary)
                }
                Button("New Library\u{2026}") {
                    DatabaseExportImport.createNewLibrary()
                }
                Button("Open Library\u{2026}") {
                    DatabaseExportImport.openLibraryFromUserSelection()
                }
                Menu("Open Recent") {
                    ForEach(DatabaseExportImport.recentLibraryItems()) { item in
                        Button(item.displayName) {
                            DatabaseExportImport.switchToLibrary(item)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        DatabaseExportImport.clearRecentLibraries()
                    }
                    .disabled(DatabaseExportImport.recentLibraryItems().isEmpty)
                }
                .disabled(DatabaseExportImport.recentLibraryItems().isEmpty)
                Divider()
                Button("Save Copy\u{2026}") {
                    if let pool = appState.dbManager?.dbPool {
                        DatabaseExportImport.saveCopy(dbPool: pool)
                    }
                }
                .disabled(!appState.hasLibrary)
                Divider()
                Button("Close Library\u{2026}") {
                    DatabaseExportImport.closeLibrary()
                }
                .disabled(!appState.hasLibrary)
                Button("Delete This Library\u{2026}") {
                    guard let url = DatabaseExportImport.activeLibraryURL() else { return }
                    let alert = NSAlert()
                    alert.messageText = "Delete This Library?"
                    alert.informativeText = "This will permanently delete the library file from disk. This action cannot be undone."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Delete")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        DatabaseExportImport.deleteThisLibrary(at: url)
                    }
                }
                .disabled(!appState.hasLibrary)
            }
        }

        Settings {
            SettingsView(appState: appState)
        }
    }
}
