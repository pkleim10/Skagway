import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.hasLibrary {
            LandingView()
                .frame(minWidth: 900, minHeight: 600)
                .appDesignSystem()
        } else if let vm = appState.libraryViewModel {
            LibraryContentView(vm: vm, thumbService: appState.thumbnailService)
                .appDesignSystem()   // Injects VideoMaster design tokens + theme
        }
    }
}

private struct LibraryContentView: View {
    /// Required so `browsingLayout` changes invalidate `NSViewRepresentable` and apply saved split positions.
    @Bindable var vm: LibraryViewModel
    let thumbService: ThumbnailService
    /// Persists across content host rootView replacements (playback/browsing switch, layout changes).
    @State private var listScrollPositionRow: Int?
    /// Must remove when the view goes away; repeated `onAppear` without removal stacks monitors and breaks handling.
    @State private var keyDownMonitor: Any?
    @State private var fullScreenController: FullscreenInlinePlayerWindowController?
    @State private var showListColumnsSheet = false
    @State private var showConversionQueue = false
    @State private var showMoveQueue = false
    @FocusState private var isSearchFocused: Bool

    /// Local presentation flag for the filters drawer (discrete).
    @State private var isFiltersDrawerOpen = false

    /// Interpolated 0...1 value that drives smooth height/offset animations for the drawer well.
    /// Using a CGFloat animated via withAnimation gives the view modifiers interpolated values
    /// each frame, so the drawer grows its height gradually instead of appearing full-size instantly,
    /// and the grid/list below is pushed at a matching rate.
    @State private var drawerReveal: CGFloat = 0
    /// Captured once at the start of a drawer-resize drag so `DragGesture`'s cumulative
    /// `translation` can be applied against a stable baseline instead of the live (already
    /// mutating) height.
    @State private var filtersDrawerDragStartHeight: CGFloat?
    /// Live height while actively dragging the resize handle. Kept local (not written to
    /// `vm.filtersDrawerHeight`) until the drag ends — writing the `@Observable`/persisted
    /// property on every drag delta caused a visible flicker (UserDefaults I/O plus broader
    /// view invalidation on every pixel of movement). `vm.filtersDrawerHeight` is only updated
    /// once, in `onEnded`.
    @State private var filtersDrawerLiveHeight: CGFloat?
    /// The drawer's natural content height (header + cards), reported by `CuratedWallFiltersDrawer`.
    /// Caps how tall the drawer can be dragged — growing past its content would just add a dead
    /// scroll region. `nil` until first measured.
    @State private var filtersDrawerContentHeight: CGFloat?

    /// The video shown in the detail pane / overlay (primary selection). Shared by `detailContent` and the overlay.
    private var selectedVideo: Video? {
        guard let id = vm.lastSelectedVideoId ?? vm.selectedVideoIds.first else { return nil }
        return vm.filteredVideos.first(where: { $0.id == id })
    }

    private var navigationTitle: String {
        let name = DatabaseExportImport.activeLibraryDisplayName
        if name.isEmpty || name == "VideoMaster" { return "VideoMaster" }
        return "VideoMaster — \(name)"
    }

    private var detailID: String {
        vm.lastSelectedVideoId ?? ""
    }


    /// Column targets for the split view always follow browsing layout so toggling playback
    /// does not change effective widths (avoids a layout pulse / grid jump before freeze).
    private var browsingSplitContentWidth: CGFloat {
        CGFloat(vm.browsingLayout.contentColumnWidth(for: vm.viewMode))
    }
    private var browsingSplitDetailWidth: CGFloat {
        CGFloat(vm.browsingLayout.detailColumnWidth(for: vm.viewMode))
    }
    private var browsingSplitTopPaneHeight: CGFloat {
        CGFloat(vm.browsingLayout.browserTopPaneHeight(for: vm.viewMode))
    }

    /// Duration for the Curated Wall top filters drawer slide animation (open and close).
    /// A deliberate, visible slide — was previously too fast at 0.22s.
    private static let drawerAnimationDuration: Double = 0.38

    /// Reusable styled search field (cinematic blue focus ring, clear affordance).
    /// Used both in the regular nav bar and inline in the Curated Wall thin header.
    private var searchField: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.appTextTertiary)
                .font(.callout)
            TextField("Search videos", text: $vm.searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.appTextPrimary)
                .tint(Color.appAccent)
                .focused($isSearchFocused)
                .help("Search videos (⌘F)")
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 4)
        .background(Color.appSurface.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(isSearchFocused ? Color.appAccent.opacity(0.55) : Color.appAccent.opacity(0.18), lineWidth: isSearchFocused ? 1.5 : 1)
        )
        .frame(minWidth: 160, idealWidth: 220)
    }

    /// Thin header bar for Curated Wall: List/Wall toggle + inline search + count + Filters toggle.
    /// Matches the layout in the wireframe mock (search is inline in the same row as the mode selector and filter button).
    /// The same button opens *and* closes the top drawer. Icon and help update with state.
    /// Header status: video count normally, live import progress while scanning, or a transient
    /// scan message (e.g. "No new files found" / "No data sources — add a folder first").
    private var headerStatusText: String {
        if vm.isScanning {
            if vm.scanTotal > 0 { return "Importing \(vm.scanCurrent)/\(vm.scanTotal)" }
            return vm.scanProgress.isEmpty ? "Importing…" : vm.scanProgress
        }
        if !vm.scanProgress.isEmpty { return vm.scanProgress }
        if vm.isFingerprintingInProgress {
            return "Fingerprinting for duplicates \(vm.fingerprintBackfillDone)/\(vm.fingerprintBackfillTotal)"
        }
        let total = "\(vm.filteredVideos.count) videos"
        let sel = vm.selectedVideoIds.count
        return sel > 1 ? "\(total), \(sel) selected" : total
    }

    /// True while the header status is showing a failure (`reportTransientError`/scan `.error`),
    /// so it can be styled to actually draw the eye instead of blending in with normal status text.
    private var isHeaderStatusError: Bool {
        headerStatusText.hasPrefix("Error:")
    }

    /// True while any re-encode job is queued or running (drives the spinner in the pill).
    private var isConversionActive: Bool {
        vm.conversionJobs.contains { $0.isActive }
    }

    /// True when nothing's currently running but at least one job ended in `.failed` — draws the
    /// eye the same way the header status error pill does, instead of blending in with a plain
    /// success summary that happens to have different text.
    private var hasConversionFailure: Bool {
        !isConversionActive && vm.conversionJobs.contains { if case .failed = $0.status { return true }; return false }
    }

    /// True when there's something timely to say (active / queued / failed). The passive "N
    /// re-encoded" completed-only summary is suppressed otherwise, so the pill doesn't linger
    /// with text forever once everything's done — it collapses to an icon-only button that still
    /// opens the queue, until the jobs are actually cleared and the pill disappears entirely.
    private var hasTimelyConversionStatus: Bool {
        isConversionActive || hasConversionFailure || vm.conversionJobs.contains { $0.status == .queued }
    }

    /// Clickable status pill that opens the re-encode queue manager.
    private var conversionPill: some View {
        Button {
            showConversionQueue = true
        } label: {
            HStack(spacing: 5) {
                if isConversionActive {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: hasConversionFailure ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 9, weight: .semibold))
                }
                if hasTimelyConversionStatus {
                    Text(vm.conversionStatusText)
                        .font(.system(size: 10, weight: hasConversionFailure ? .semibold : .regular))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(hasConversionFailure ? .white : (isConversionActive ? Color.appAccent : Color.appTextSecondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    hasConversionFailure ? Color.red.opacity(0.75) : Color.appAccent.opacity(isConversionActive ? 0.14 : 0.08)
                )
            )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .help("Re-encode queue — click to manage")
    }

    /// True while any cross-volume move is queued or running (drives the spinner in the pill).
    private var isMoveActive: Bool {
        vm.moveJobs.contains { $0.isActive }
    }

    /// Same failure-highlighting rationale as `hasConversionFailure`.
    private var hasMoveFailure: Bool {
        !isMoveActive && vm.moveJobs.contains { if case .failed = $0.status { return true }; return false }
    }

    /// Same rationale as `hasTimelyConversionStatus`.
    private var hasTimelyMoveStatus: Bool {
        isMoveActive || hasMoveFailure || vm.moveJobs.contains { $0.status == .queued }
    }

    /// Clickable status pill that opens the move queue manager.
    private var movePill: some View {
        Button {
            showMoveQueue = true
        } label: {
            HStack(spacing: 5) {
                if isMoveActive {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: hasMoveFailure ? "exclamationmark.triangle.fill" : "arrow.right.doc.on.clipboard")
                        .font(.system(size: 9, weight: .semibold))
                }
                if hasTimelyMoveStatus {
                    Text(vm.moveStatusText)
                        .font(.system(size: 10, weight: hasMoveFailure ? .semibold : .regular))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(hasMoveFailure ? .white : (isMoveActive ? Color.appAccent : Color.appTextSecondary))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    hasMoveFailure ? Color.red.opacity(0.75) : Color.appAccent.opacity(isMoveActive ? 0.14 : 0.08)
                )
            )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .help("Move queue — click to manage")
    }

    private var sortCluster: some View {
        let isCustomSort = vm.customSortFieldId != nil
        let currentBuiltinSort = VideoSort.from(keyPath: vm.tableSortOrder.first?.keyPath ?? \Video.dateAdded)
        let currentCustomField = vm.customMetadataFieldDefinitions.first { $0.id == vm.customSortFieldId }
        let isAscending = isCustomSort ? vm.customSortAscending : (vm.tableSortOrder.first?.order == .forward)
        let sortLabel = currentCustomField?.name ?? currentBuiltinSort.displayName
        let sortableCustomFields = vm.customMetadataFieldDefinitions
            .filter { $0.valueType != .text }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return HStack(spacing: 4) {
            Menu {
                ForEach(VideoSort.allCases) { sort in
                    Button {
                        vm.selectBuiltinSort(sort, ascending: isAscending)
                    } label: {
                        if !isCustomSort && sort == currentBuiltinSort {
                            Label(sort.displayName, systemImage: "checkmark")
                        } else {
                            Text(sort.displayName)
                        }
                    }
                }
                if !sortableCustomFields.isEmpty {
                    Divider()
                    ForEach(sortableCustomFields) { field in
                        Button {
                            vm.selectCustomSort(fieldId: field.id, ascending: isAscending)
                        } label: {
                            if vm.customSortFieldId == field.id {
                                Label(field.name, systemImage: "checkmark")
                            } else {
                                Text(field.name)
                            }
                        }
                    }
                }
            } label: {
                Text("Sort: \(sortLabel)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                if isCustomSort, let fieldId = vm.customSortFieldId {
                    vm.selectCustomSort(fieldId: fieldId, ascending: !isAscending)
                } else {
                    vm.tableSortOrder = currentBuiltinSort.comparators(ascending: !isAscending)
                    vm.savePreferences()
                }
            } label: {
                Image(systemName: isAscending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.appTextSecondary)
            }
            .buttonStyle(.plain)
            .help(isAscending ? "Ascending — click for descending" : "Descending — click for ascending")
        }
    }

    private var curatedHeaderBar: some View {
        HStack(spacing: 8) {
            // Library actions (left cluster).
            Button {
                Task { await vm.importNew() }
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appTextSecondary)
            .disabled(vm.isScanning)
            .help("Import New — scan your folders for newly added video files (⌘I)")
            .keyboardShortcut("i", modifiers: .command)

            Button {
                vm.surpriseMePickRandom()
            } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appTextSecondary)
            .disabled(vm.filteredVideos.isEmpty)
            .help("Surprise Me — pick a random video, auto-plays if enabled in Settings (⌘⇧S)")
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider().frame(height: 16)

            AppSegmentedControl(
                selection: Binding(
                    get: { vm.viewMode },
                    set: { newValue in
                        vm.scrollToSelectedOnViewSwitch = true
                        vm.viewMode = newValue
                        vm.savePreferences()
                    }
                ),
                items: [ViewMode.list, .grid],
                tooltip: { mode in
                    switch mode {
                    case .list: "List view (⌘1)"
                    case .grid: "Wall view (⌘2)"
                    }
                }
            ) { mode in
                switch mode {
                case .list: Label("List", systemImage: "list.bullet")
                case .grid: Label("Wall", systemImage: "square.grid.2x2")
                }
            }
            .controlSize(.small)

            Divider().frame(height: 16)

            sortCluster

            Divider().frame(height: 16)

            // Search is placed inline here (after the mode picker, before right-aligned actions)
            // to match the Curated Wall wireframe mockup.
            searchField

            Spacer()

            // Video count (light) — replaced by scan progress while importing, or a red error pill
            // (reportTransientError / scan .error) so a failure actually draws the eye.
            Text(headerStatusText)
                .font(.system(size: 10, weight: isHeaderStatusError ? .semibold : .regular))
                .foregroundStyle(isHeaderStatusError ? .white : Color.appTextTertiary)
                .monospacedDigit()
                .padding(.horizontal, isHeaderStatusError ? 8 : 0)
                .padding(.vertical, isHeaderStatusError ? 3 : 0)
                .background(
                    Capsule().fill(isHeaderStatusError ? Color.red.opacity(0.75) : Color.clear)
                )
                .padding(.trailing, 4)
                .animation(.easeInOut(duration: 0.15), value: isHeaderStatusError)

            // Re-encode queue pill — click to open the queue manager.
            if vm.hasConversionActivity {
                conversionPill
            }

            // Move queue pill — click to open the move manager. Same-volume moves are instant
            // and never appear here; only cross-volume (copy + delete) moves show up.
            if vm.hasMoveActivity {
                movePill
            }

            // The single toggle for the top filters drawer.
            // Closed -> filter icon; Open -> close (X) icon. Always live filters, no Apply step.
            Button {
                // Just flip the model flag. The .onChange below will drive the slide animation
                // (offset + height) with the proper duration and a clean transaction.
                vm.isCuratedWallFiltersDrawerOpen.toggle()
            } label: {
                if vm.isCuratedWallFiltersDrawerOpen {
                    Image(systemName: "xmark.circle")
                } else {
                    Image(systemName: vm.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appTextSecondary)
            .help(vm.isCuratedWallFiltersDrawerOpen
                  ? "Close filters (⌘⇧F)"
                  : "Show filters (⌘⇧F)")
            .keyboardShortcut("f", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Color.appSurface.opacity(0.35))
    }

    /// The full browsing surface for the Curated Wall: header bar + optional top drawer + optional active pills + grid/list.
    /// Replaces the previous vertical split + bottom filter strip for this variant.
    private var wallBrowserPane: some View {
        VStack(spacing: 0) {
            curatedHeaderBar

            // GeometryReader reports whatever's left after the header above — the space the
            // drawer, its resize handle, the pills, and the grid/list all have to share.
            GeometryReader { geo in
                wallDrawerAndContent(availableHeight: geo.size.height)
            }
        }
        // Animate the pane layout (grid/list position) in response to the reveal factor.
        // This makes the wall content rise/fall smoothly as the well above it changes height.
        .animation(.easeInOut(duration: Self.drawerAnimationDuration), value: drawerReveal)
    }

    /// Clamps a requested drawer height. Ceiling is the smaller of: what fits in the window (so the
    /// resize handle stays on screen) and the drawer's own natural content height (so it can't be
    /// dragged taller than its content — past that would just be a dead scroll region). Floor is
    /// `filtersDrawerMinHeight`, which always wins if content/window are somehow shorter.
    private func clampedFiltersDrawerHeight(_ requested: CGFloat, availableHeight: CGFloat) -> CGFloat {
        var ceiling = availableHeight - Self.filtersDrawerHandleHeight
        if let contentH = filtersDrawerContentHeight {
            ceiling = min(ceiling, contentH)
        }
        ceiling = max(ceiling, LibraryViewModel.filtersDrawerMinHeight)
        return min(max(requested, LibraryViewModel.filtersDrawerMinHeight), ceiling)
    }

    private static let filtersDrawerHandleHeight: CGFloat = 12

    @ViewBuilder
    private func wallDrawerAndContent(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Drawer well — the expanding slot directly under the thin header.
            // Goal: a clean, "wow" slide where the filter panel drops down from under the header
            // while smoothly pushing the grid/list below. No full pane flash, no "appears then pushes".
            //
            // How:
            // - The drawer is *always* laid out at its full height (stable layout, no mid-animation reflow of its sections/grids).
            // - We slide it into view with a changing offset: starts fully above the well, moves downward as the well opens.
            // - The well's own height grows from 0→fullH; because it's in the VStack, this reserves space and pushes the wall content down in lockstep.
            // - `.clipped()` hides the portion that is still "above" the visible well rect.
            // - Everything is driven from the single interpolated `drawerReveal` (0...1) so the visual slide and the layout push are perfectly synchronized.
            let reveal = drawerReveal
            // Fit-to-content: always request the natural content height (the clamp caps it to the
            // window). Last-used: request the live drag value, else the persisted height.
            let requestedH: CGFloat = vm.filterDrawerHeightMode == .fitToContent
                ? (filtersDrawerContentHeight ?? LibraryViewModel.filtersDrawerDefaultHeight)
                : (filtersDrawerLiveHeight ?? vm.filtersDrawerHeight)
            let fullH = clampedFiltersDrawerHeight(requestedH, availableHeight: availableHeight)
            let shownH = fullH * reveal

            ZStack(alignment: .top) {
                CuratedWallFiltersDrawer(viewModel: vm, onNaturalHeightChanged: { h in
                    // Round to avoid sub-point jitter re-triggering the clamp.
                    let rounded = h.rounded(.up)
                    if filtersDrawerContentHeight != rounded { filtersDrawerContentHeight = rounded }
                })
                    .frame(height: fullH, alignment: .top)   // full layout (no squish/reflow)
                    .offset(y: shownH - fullH)               // -fullH (above, hidden) → 0 (fully visible in well)
                    .opacity(reveal)
            }
            .frame(height: shownH, alignment: .top)
            .clipped()
            .zIndex(1)   // ensure the sliding drawer draws above the grid/list during the push (prevents any "behind" flash)
            .animation(.easeInOut(duration: Self.drawerAnimationDuration), value: reveal)

            // Resize handle — only in "Last used" mode (Fit to content sizes itself, so there's
            // nothing to drag), and only once the drawer has finished opening (dragging mid-slide
            // isn't a sensible interaction). Adjusts and persists `filtersDrawerHeight`.
            if reveal > 0.99 && vm.filterDrawerHeightMode == .lastUsed {
                filtersDrawerResizeHandle(availableHeight: availableHeight)
                    .transition(.opacity)
            }

            // Pills live in their own slot and only when the drawer is fully closed.
            // Use reveal so pills don't pop in while the drawer is still sliding away.
            if reveal < 0.001 && vm.hasActiveFilters {
                ActiveFilterPills(viewModel: vm)
                    .transition(.opacity)
            }

            if vm.viewMode == .grid {
                CuratedWallGrid(viewModel: vm, thumbnailService: thumbService)
            } else {
                LibraryListView(
                    viewModel: vm,
                    thumbnailService: thumbService,
                    scrollPositionRow: $listScrollPositionRow
                )
            }
        }
    }

    private func filtersDrawerResizeHandle(availableHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color.appTextSecondary.opacity(0.55))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity, minHeight: Self.filtersDrawerHandleHeight)
            // Matches the Inspector hero handle's backdrop exactly (same dark navy) — without an
            // explicit background here, this row shows the plain wall/window background instead,
            // a visibly lighter charcoal that breaks the otherwise-consistent dark surroundings.
            .background(CuratedWallInspector.inspectorBackground)
            .contentShape(Rectangle())
            .gesture(
                // Global coordinate space avoids a feedback loop: the handle is laid out below the
                // drawer it resizes, so it moves as the drawer grows/shrinks. In the default *local*
                // space the moving frame makes `translation` drift even without mouse movement →
                // oscillating flicker. Global space measures against the fixed window frame instead.
                // Round to whole points to avoid sub-pixel layout thrash (same as the player handle).
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = filtersDrawerDragStartHeight
                            ?? clampedFiltersDrawerHeight(vm.filtersDrawerHeight, availableHeight: availableHeight)
                        filtersDrawerDragStartHeight = start
                        filtersDrawerLiveHeight = clampedFiltersDrawerHeight(
                            (start + value.translation.height).rounded(),
                            availableHeight: availableHeight
                        )
                    }
                    .onEnded { _ in
                        if let live = filtersDrawerLiveHeight {
                            vm.filtersDrawerHeight = live
                        }
                        filtersDrawerDragStartHeight = nil
                        filtersDrawerLiveHeight = nil
                    }
            )
            .help("Drag to resize the filters drawer")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Curated Wall layout (bold dedicated implementation)
            // Left: elegant gallery "Wall"  |  Right: focused Inspector
            // Matches the refined mockups as closely as we can get.
            ResizableBrowserDetailSplitView(
                layoutModeKey: vm.viewMode.rawValue,
                contentWidth: browsingSplitContentWidth,
                detailWidth: browsingSplitDetailWidth,
                contentID: "curatedWall",
                detailID: detailID,
                // Playback no longer reshapes the browser, so the wall never needs freezing during play.
                freezeContent: false,
                onSizesChanged: { browserW, detailW in
                    vm.updateCurrentLayoutWithSizes(sidebarWidth: nil, contentWidth: browserW, detailWidth: detailW)
                },
                content: {
                    // Curated Wall uses a top-descending live filters drawer instead of a persistent bottom strip.
                    // Drawer always starts closed; toggle via button or ⌘⇧F. Changes are live.
                    wallBrowserPane
                },
                detail: {
                    CuratedWallInspector(video: selectedVideo, viewModel: vm, thumbnailService: thumbService)
                }
            )
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                guard !providers.isEmpty else { return true }
                let group = DispatchGroup()
                var urls: [URL] = []
                let lock = NSLock()
                for provider in providers {
                    group.enter()
                    _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                        defer { group.leave() }
                        if let data = data,
                           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           let url = URL(string: path)
                        {
                            lock.lock()
                            urls.append(url)
                            lock.unlock()
                        }
                    }
                }
                group.notify(queue: .main) {
                    Task { await vm.importDroppedFiles(urls) }
                }
                return true
            }
            .overlay {
                // The single resizable player: one surface anchored top-right, shown whenever
                // playback is active. Hidden while in true full-screen (the borderless window hosts
                // the same player instead). Floats above the wall/inspector (no freeze/resize).
                if vm.isPlayingInline, !vm.isPlayerFullScreen, let video = selectedVideo {
                    GeometryReader { geo in
                        FloatingPlayerPanel(video: video, viewModel: vm, available: geo.size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            // Drive the shared player lifecycle from state, not from any view's appear/disappear, so
            // the panel can hide for full-screen without tearing down the player.
            .onChange(of: vm.isPlayingInline) { _, isOn in
                if isOn {
                    guard let v = selectedVideo else { vm.isPlayingInline = false; return }
                    let seek = vm.pendingFilmstripSeekSeconds ?? 0
                    vm.pendingFilmstripSeekSeconds = nil
                    let ignoreResume = vm.pendingIgnoreResumeOnNextStart
                    vm.pendingIgnoreResumeOnNextStart = false
                    vm.playback.start(video: v, at: seek, ignoreResume: ignoreResume)
                    // Apply the starting-size preference. `.lastSize` keeps whatever the player was
                    // last left at (including sticky compact mode); `.compact` re-enables compact.
                    switch vm.playerStartPreference {
                    case .fullScreen: vm.isPlayerFullScreen = true
                    case .compact: vm.playerSizeIsCompact = true
                    case .lastSize: if vm.playerLastWasFullScreen { vm.isPlayerFullScreen = true }
                    }
                } else {
                    vm.isPlayerFullScreen = false
                    vm.playback.stop()
                }
            }
            // Surprise Me auto-play: `surpriseMePickRandom()` selects a random video and (if enabled)
            // raises this flag *in the same batch* as the selection change. The selection change also
            // fires the inspector's "video changed → stop playback" handler, so we defer starting to
            // the next runloop — otherwise that stop would immediately cancel the just-started play.
            .onChange(of: vm.pendingAutoPlay) { _, shouldPlay in
                guard shouldPlay else { return }
                vm.pendingAutoPlay = false
                DispatchQueue.main.async {
                    vm.pendingFilmstripSeekSeconds = nil
                    vm.isPlayingInline = true
                }
            }
            // Enter/leave true full-screen by moving the *same* player into a borderless window.
            .onChange(of: vm.isPlayerFullScreen) { _, isFS in
                if isFS {
                    guard fullScreenController == nil else { return }
                    Task { @MainActor in
                        // The controller creates its AVPlayer asynchronously in `start()`, so on the
                        // "open at full screen" path the player isn't ready yet — wait briefly for it
                        // (the manual full-screen button already has a player, so this returns at once).
                        var player = vm.playback.player
                        var waited = 0
                        while player == nil, waited < 3000, vm.isPlayerFullScreen {
                            try? await Task.sleep(for: .milliseconds(40))
                            waited += 40
                            player = vm.playback.player
                        }
                        guard vm.isPlayerFullScreen, fullScreenController == nil, let player else {
                            if player == nil { vm.isPlayerFullScreen = false }
                            return
                        }
                        let controller = FullscreenInlinePlayerWindowController()
                        fullScreenController = controller
                        controller.present(
                            player: player,
                            title: selectedVideo?.fileName ?? "",
                            startWindowInFullscreen: true,
                            subtitleTrack: vm.playback.subtitleTrack
                        ) {
                            vm.isPlayerFullScreen = false
                        }
                    }
                } else {
                    fullScreenController?.closeWindow()
                    fullScreenController = nil
                    // The borderless full-screen window occluded the grid; nudge it to repaint any
                    // cells the occlusion left blank once it's revealed again.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        vm.issueScrollCommand(.retile)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                vm.playback.persistPosition()
            }

            // Hidden for Curated Wall to keep the gallery + inspector clean (per mock aesthetic)
            // statusBar(vm: vm)
        }
        .task {
            vm.startObserving()
            // Curated Wall: always start with the top filters drawer closed (per spec).
            // Drawer state is intentionally not persisted. Set both directly (no animation on init).
            vm.isCuratedWallFiltersDrawerOpen = false
            isFiltersDrawerOpen = false
            drawerReveal = 0
            // On launch the window makes the search field the first responder, so Space would type
            // into it instead of starting playback. Clear that unintended focus once the window has
            // settled, so Space starts playback until the user deliberately clicks the search field.
            try? await Task.sleep(for: .milliseconds(120))
            if let window = NSApp.keyWindow, window.firstResponder is NSText {
                window.makeFirstResponder(nil)
            }
        }
        .sheet(isPresented: $showConversionQueue) {
            ConversionQueueView(vm: vm)
        }
        .sheet(isPresented: $showMoveQueue) {
            MoveQueueView(vm: vm)
        }
        .onChange(of: vm.focusSearchFieldToken) { _, _ in
            isSearchFocused = true
        }
        .onChange(of: vm.isCuratedWallFiltersDrawerOpen) { _, newValue in
            // Animate the reveal factor. The well and drawer heights are driven from this CGFloat,
            // so we get smooth per-frame interpolated sizes instead of a full-height pop followed by a push.
            withAnimation(.easeInOut(duration: Self.drawerAnimationDuration)) {
                isFiltersDrawerOpen = newValue
                drawerReveal = newValue ? 1 : 0
            }
        }
        .onAppear {
            guard keyDownMonitor == nil else { return }
            let lvm = vm
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                Self.processLibraryKeyDown(event, lvm: lvm)
            }
        }
        .onDisappear {
            if let m = keyDownMonitor {
                NSEvent.removeMonitor(m)
                keyDownMonitor = nil
            }
        }
    }

    /// Returns `nil` to consume the key event (do not deliver to the app).
    private static func processLibraryKeyDown(_ event: NSEvent, lvm: LibraryViewModel) -> NSEvent? {
        // Enter key (without modifiers) — start inline rename in list or grid mode
        if event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [], !lvm.isEditingText {
            if (lvm.viewMode == .list || lvm.viewMode == .grid),
               lvm.selectedVideoIds.count == 1,
               let videoId = lvm.selectedVideoIds.first,
               !lvm.activeMoveVideoIds.contains(videoId),
               let video = lvm.filteredVideos.first(where: { $0.id == videoId })
            {
                DispatchQueue.main.async {
                    lvm.renameText = video.fileName
                    lvm.renamingVideoId = videoId
                }
                return nil
            }
            return event
        }
        // Escape key — cancel rename, defocus text input, or stop playback (priority order).
        if event.keyCode == 53 {
            if lvm.renamingTagId != nil {
                DispatchQueue.main.async {
                    lvm.renamingTagId = nil
                    lvm.tagRenameText = ""
                    lvm.isEditingText = false
                }
                return nil
            }
            if lvm.renamingVideoId != nil {
                DispatchQueue.main.async {
                    lvm.renamingVideoId = nil
                    lvm.renameText = ""
                }
                return nil
            }
            // Defocus any active text input (search field, inspector fields). SwiftUI TextFields
            // handle Escape themselves before this monitor sees it; this catches NSTextView-backed
            // fields (TabbableTextEditor handles its own via doCommandBy, but this is a fallback).
            if let first = NSApp.keyWindow?.firstResponder,
               first is NSText {
                DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
                return nil
            }
            if lvm.isPlayingInline {
                DispatchQueue.main.async {
                    lvm.isPlayingInline = false
                }
                return nil
            }
            return event
        }
        // Space — play/pause (or start playback). ⌥-Space — "Play from Beginning": starts (or, if
        // already playing, restarts) from 0, ignoring any saved resume position. ⌥-Space replaces the
        // old ⌥⌘B "Restart from Beginning" shortcut for the already-playing case.
        if event.keyCode == 49 {
            // A focused text field (e.g. Notes) wins so a space can be typed.
            if let first = NSApp.keyWindow?.firstResponder,
               first is NSTextView || first is NSTextField
            {
                return event
            }
            guard !lvm.isEditingText else { return event }
            let optionHeld = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            if lvm.isPlayingInline {
                DispatchQueue.main.async {
                    if optionHeld {
                        lvm.playback.restartFromBeginning()
                    } else {
                        lvm.playback.togglePlayPause()
                    }
                }
                return nil
            }
            guard !lvm.selectedVideoIds.isEmpty else { return event }
            DispatchQueue.main.async {
                if optionHeld { lvm.pendingIgnoreResumeOnNextStart = true }
                lvm.isPlayingInline = true
            }
            return nil
        }

        // ⌃⌘F — toggle full-screen inline playback (enter when playing, exit when already fullscreen).
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.control, .command],
           event.keyCode == 3 /* 'f' */ {
            if lvm.isPlayingInline {
                DispatchQueue.main.async { lvm.isPlayerFullScreen.toggle() }
                return nil
            }
            return event
        }

        // ⌘F — focus the search field (matches system-wide Find convention).
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 3 /* 'f' */ {
            DispatchQueue.main.async { lvm.requestFocusSearchField() }
            return nil
        }

        // ⌘⇧F — toggle the Curated Wall top filters drawer (live filters, always starts closed).
        // This is a fallback in addition to the .keyboardShortcut on the button.
        if event.modifierFlags.contains([.command, .shift]), event.keyCode == 3 /* 'f' */ {
            // Just set the flag; the onChange handler will start the slide animation with the right duration.
            DispatchQueue.main.async {
                lvm.isCuratedWallFiltersDrawerOpen.toggle()
            }
            return nil
        }

        // Arrow keys — grid navigation. Handled here (same local monitor as Space/Enter/Escape) because
        // SwiftUI `.onKeyPress` on the grid's `ScrollView` doesn't reliably receive keys inside the
        // NSHostingView+NSSplitView the Curated Wall is hosted in. ←/→ step one video; ↑/↓ step one row.
        // keyCodes: 123 ←, 124 →, 125 ↓, 126 ↑.
        // NB: arrow events always carry `.function` + `.numericPad`, so we must test only the real
        // command/option/control/shift modifiers — a `.deviceIndependentFlagsMask` check never matches.
        let commandModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        if [123, 124, 125, 126].contains(event.keyCode),
           event.modifierFlags.intersection(commandModifiers).isEmpty,
           lvm.viewMode == .grid,
           !lvm.isEditingText {
            // Let a focused text field (search, inspector fields) keep its own caret navigation.
            if let first = NSApp.keyWindow?.firstResponder, first is NSTextView || first is NSTextField {
                return event
            }
            let step: Int
            switch event.keyCode {
            case 123: step = -1                     // ← previous
            case 124: step = 1                      // → next
            case 126: step = -CuratedWallGrid.columns   // ↑ one row up
            default:  step = CuratedWallGrid.columns    // ↓ one row down
            }
            DispatchQueue.main.async { lvm.navigateFilteredVideoStep(step) }
            return nil
        }

        // Home / End — "Go to first" / "Go to last": select the first/last video in the current
        // filtered order and scroll it into view. Works in both list and grid (unlike the arrow-key
        // block above, which is grid-only since List's Table already handles its own arrow keys).
        // Handled here rather than a SwiftUI `.keyboardShortcut(.home/.end)` for the same reason as
        // arrow-key navigation: Table's own responder chain can intercept Home/End for plain
        // scrolling before a menu-level shortcut would ever see the event.
        // NB: like arrow keys, Home/End always carry `.function` (+ often `.numericPad`), so a
        // `.deviceIndependentFlagsMask` emptiness check never matches — test only the real modifiers.
        if event.keyCode == 115 || event.keyCode == 119,  // 115 Home, 119 End
           event.modifierFlags.intersection(commandModifiers).isEmpty,
           !lvm.isEditingText {
            if let first = NSApp.keyWindow?.firstResponder, first is NSTextView || first is NSTextField {
                return event
            }
            DispatchQueue.main.async {
                if event.keyCode == 115 { lvm.goToFirstVideo() } else { lvm.goToLastVideo() }
            }
            return nil
        }

        // ⌘A — Select All in the Wall grid. Grid-only: List's `Table` responds to ⌘A natively.
        // A focused text field keeps ⌘A as "select the field's text" — but only when it actually
        // has text. An *empty* focused field (e.g. the search box, which quietly holds focus until
        // the user clicks a card) would otherwise swallow ⌘A as an invisible no-op, making Select
        // All appear randomly dead.
        if event.keyCode == 0,  // 'a'
           event.modifierFlags.intersection(commandModifiers) == .command,
           lvm.viewMode == .grid,
           !lvm.isEditingText {
            if let first = NSApp.keyWindow?.firstResponder {
                let hasText = ((first as? NSTextView)?.string.isEmpty == false)
                    || ((first as? NSTextField)?.stringValue.isEmpty == false)
                if hasText { return event }
            }
            DispatchQueue.main.async { lvm.selectAllVideos() }
            return nil
        }

        // ⌘⇧A — Deselect All. Works in both List and grid (unlike ⌘A, `Table` has no native
        // "deselect all" to defer to, so this needs to be handled here for List too).
        if event.keyCode == 0,  // 'a'
           event.modifierFlags.intersection(commandModifiers) == [.command, .shift],
           !lvm.isEditingText {
            if let first = NSApp.keyWindow?.firstResponder, first is NSTextView || first is NSTextField {
                return event
            }
            DispatchQueue.main.async { lvm.deselectAllVideos() }
            return nil
        }

        return event
    }

}
