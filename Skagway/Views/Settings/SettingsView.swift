import GRDB
import SwiftUI
import UniformTypeIdentifiers

/// Settings window chrome (sampled from System Settings).
enum SettingsChrome {
    /// Sidebar background — RGB 21, 24, 26.
    static let sidebar = Color(red: 21 / 255, green: 24 / 255, blue: 26 / 255)
    /// Detail sheet + heading strip — RGB 35, 39, 40.
    static let detail = Color(red: 35 / 255, green: 39 / 255, blue: 40 / 255)
}

// MARK: - Categories

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case library
    case video
    case dataSources
    case fileExt
    case tools
    case customMetadata

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "Library"
        case .video: return "Video"
        case .dataSources: return "Data Sources"
        case .fileExt: return "Extensions"
        case .tools: return "Tools"
        case .customMetadata: return "Custom Metadata"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical"
        case .video: return "film"
        case .dataSources: return "folder"
        case .fileExt: return "doc.badge.gearshape"
        case .tools: return "wrench.and.screwdriver"
        case .customMetadata: return "square.grid.3x3.square.badge.ellipsis"
        }
    }
}

// MARK: - Shell

struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.pixelLength) private var pixelLength

    @State private var selectedCategory: SettingsCategory? = .library
    @State private var searchText = ""

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchCatalog.matches(for: searchText)
    }

    var body: some View {
        Group {
            if let pool = appState.dbManager?.dbPool, let vm = appState.libraryViewModel {
                NavigationSplitView {
                    settingsSidebar
                } detail: {
                    settingsDetail(pool: pool, viewModel: vm)
                }
                .navigationSplitViewStyle(.balanced)
                // Hide the system toolbar fill so each column’s background shows under
                // the title strip (detail heading matches sheet; sidebar stays charcoal).
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
                .onAppear {
                    if selectedCategory == nil {
                        selectedCategory = .library
                    }
                }
            } else {
                ContentUnavailableView(
                    "Open a Library",
                    systemImage: "books.vertical",
                    description: Text("Library settings appear once a library is open.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    /// Single stable `List` — swapping Lists when search starts steals focus from the search field.
    private var settingsSidebar: some View {
        List(selection: $selectedCategory) {
            // Explicit spacer under Search (~1 rem). contentMargins does not sit between
            // `.searchable` and the first row the way System Settings spacing does.
            Color.clear
                .frame(height: 16)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .accessibilityHidden(true)

            if isSearching {
                ForEach(searchResults) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                        Text(item.category.title)
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCategory = item.category
                        searchText = ""
                    }
                }
            } else {
                ForEach(SettingsCategory.allCases) { category in
                    Label(category.title, systemImage: category.systemImage)
                        .tag(category)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .padding(.top, pixelLength)
        .background(SettingsChrome.sidebar)
        .navigationTitle("Settings")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        .overlay {
            if isSearching && searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private func settingsDetail(pool: DatabasePool, viewModel: LibraryViewModel) -> some View {
        Group {
            switch selectedCategory {
            case .library:
                LibrarySettingsView(viewModel: viewModel)
            case .video:
                VideoSettingsView(viewModel: viewModel)
            case .dataSources:
                DataSourcesSettingsView(dbPool: pool)
            case .fileExt:
                FileExtSettingsView()
            case .tools:
                ToolsSettingsView(viewModel: viewModel)
            case .customMetadata:
                CustomMetadataSettingsView(viewModel: viewModel)
            case .none:
                ContentUnavailableView(
                    "Select a Category",
                    systemImage: "sidebar.left",
                    description: Text("Choose a settings category from the sidebar.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, pixelLength)
        .background(SettingsChrome.detail)
        .navigationTitle(selectedCategory?.title ?? "Settings")
    }
}


// MARK: - Library

struct LibrarySettingsView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $viewModel.excludeCorrupt) {
                    SettingsLabel(
                        "Exclude corrupt files from filters",
                        description: "Corrupt files (missing duration and resolution) will be hidden from Library, Collections, Rating, and Tag filters. They remain visible in the Corrupt filter and name search."
                    )
                }
                Toggle(isOn: $viewModel.confirmDeletions) {
                    SettingsLabel(
                        "Confirm deletions",
                        description: "When enabled, a confirmation dialog will appear before moving files to Trash."
                    )
                }
            }

            Section("Smart Libraries") {
                smartLibraryToggle(
                    "Recently Added",
                    isOn: $viewModel.showRecentlyAdded
                ) {
                    SettingsIntegerStepper(
                        value: $viewModel.recentlyAddedDays,
                        range: 1...365,
                        unit: "days"
                    )
                    .disabled(!viewModel.showRecentlyAdded)
                    .opacity(viewModel.showRecentlyAdded ? 1 : 0.45)
                }

                smartLibraryToggle(
                    "Recently Played",
                    isOn: $viewModel.showRecentlyPlayed
                ) {
                    SettingsIntegerStepper(
                        value: $viewModel.recentlyPlayedDays,
                        range: 1...365,
                        unit: "days"
                    )
                    .disabled(!viewModel.showRecentlyPlayed)
                    .opacity(viewModel.showRecentlyPlayed ? 1 : 0.45)
                }

                smartLibraryToggle(
                    "Top Rated",
                    isOn: $viewModel.showTopRated
                ) {
                    RatingView(rating: viewModel.topRatedMinRating, size: 14) { newRating in
                        viewModel.topRatedMinRating = max(newRating, 1)
                    }
                    .disabled(!viewModel.showTopRated)
                    .opacity(viewModel.showTopRated ? 1 : 0.4)
                }

                Toggle("Duplicates", isOn: $viewModel.showDuplicates)
                Toggle("Corrupt", isOn: $viewModel.showCorrupt)
                Toggle("Missing", isOn: $viewModel.showMissing)
                Toggle("Recently Converted", isOn: $viewModel.showRecentlyConverted)
            }

            Section {
                ListColumnsSettingsContent(viewModel: viewModel)
            } header: {
                Text("List view columns")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func smartLibraryToggle<C: View>(
        _ title: String,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: () -> C
    ) -> some View {
        HStack(spacing: 12) {
            Toggle(title, isOn: isOn)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

// MARK: - Video

struct VideoSettingsView: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    SettingsIntegerStepper(
                        value: $viewModel.defaultFilmstripRows,
                        range: 1...6
                    )
                } label: {
                    SettingsLabel(
                        "Rows",
                        description: "Default grid size when generating new filmstrips. Override per video with Modify Filmstrip."
                    )
                }
                LabeledContent("Columns") {
                    SettingsIntegerStepper(
                        value: $viewModel.defaultFilmstripColumns,
                        range: 1...8
                    )
                }
                LabeledContent("Frames per filmstrip") {
                    Text("\(viewModel.defaultFilmstripRows * viewModel.defaultFilmstripColumns)")
                        .foregroundStyle(Color.secondary)
                        .monospacedDigit()
                }

                Button("Regenerate filmstrips") {
                    Task { await viewModel.clearFilmstripCacheAndMarkApplied() }
                }
                .disabled(!viewModel.filmstripLayoutChanged)
            } header: {
                Text("Default Filmstrip Size")
            }

            Section {
                Toggle(isOn: $viewModel.surpriseMeAutoPlays) {
                    SettingsLabel(
                        "Surprise Me! auto-plays selected video",
                        description: "Updates selection immediately, loads or generates the filmstrip for the detail pane, starts auto-play if enabled, then scrolls the grid or list to the selection."
                    )
                }
                Toggle(isOn: $viewModel.gridHoverPreviewEnabled) {
                    SettingsLabel(
                        "Hover preview on Grid cards",
                        description: "Plays a muted cycling scrub when the pointer rests on a Grid card (disabled automatically while the floating player is open)."
                    )
                }
            }

            Section {
                Picker(selection: $viewModel.tagBlindDefaultState) {
                    ForEach(TagBlindDefaultState.allCases) { state in
                        Text(state.label).tag(state)
                    }
                } label: {
                    SettingsLabel(
                        "Tag blind default state",
                        description: "Controls the Inspector’s “Add tags” blind (the unassigned-tags list) each time you select a different video: always start closed, always start open, or leave it exactly as you last set it."
                    )
                }
            } header: {
                Text("Tags")
            }

            Section {
                Picker(selection: $viewModel.filterDrawerHeightMode) {
                    ForEach(FilterDrawerHeightMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    SettingsLabel(
                        "Filter drawer height",
                        description: "How the filters drawer sizes itself when opened. Fit to content sizes it to just show all the filter cards (no scrollbar) and hides the resize handle; Last used reopens it at whatever height you last dragged it to."
                    )
                }
            } header: {
                Text("Filters")
            }

            Section {
                Picker(selection: $viewModel.playerStartPreference) {
                    ForEach(PlayerStartPreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                } label: {
                    SettingsLabel(
                        "Player opens at",
                        description: "When you start inline playback, the resizable player opens at this size. Compact fits the inspector still/filmstrip area; Full screen opens borderless edge-to-edge; Last used size reopens the player at whatever size you last left it. You can always resize, snap, or go full-screen from the player's own controls."
                    )
                }
            }

            Section {
                Toggle(isOn: $viewModel.fadeResumeBannerAutomatically) {
                    SettingsLabel(
                        "Fade resume banner after delay",
                        description: "After resuming inline playback from a remembered position, Skagway shows a banner with Start at beginning. When fade is enabled, that banner fades out after the delay; playback keeps going from the resumed time."
                    )
                }
                LabeledContent("Seconds before fade") {
                    SettingsIntegerStepper(
                        value: $viewModel.resumeBannerFadeDelaySeconds,
                        range: 1...120,
                        unit: "sec"
                    )
                }
                .disabled(!viewModel.fadeResumeBannerAutomatically)
                .opacity(viewModel.fadeResumeBannerAutomatically ? 1 : 0.45)
            } header: {
                Text("Playback")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

// MARK: - Tools

struct ToolsSettingsView: View {
    @Bindable var viewModel: LibraryViewModel
    @State private var showingFilePicker = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsLabel(
                        "Status",
                        description: "FFmpeg repairs videos that won’t play in Skagway’s built-in player (“Fix for Built-in Player” in the video context menu)."
                    )
                    ffmpegStatusLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    SettingsLabel(
                        "Path",
                        description: "Skagway auto-discovers ffmpeg at standard Homebrew and system paths. Set a custom path if yours is installed elsewhere."
                    )
                    HStack(spacing: 8) {
                        TextField("", text: $viewModel.ffmpegUserPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout.monospaced())
                            .multilineTextAlignment(.leading)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose\u{2026}") { showingFilePicker = true }
                        if !viewModel.ffmpegUserPath.isEmpty {
                            Button("Clear") { viewModel.ffmpegUserPath = "" }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("FFmpeg")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.unixExecutable, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                viewModel.ffmpegUserPath = url.path
            }
        }
    }

    @ViewBuilder
    private var ffmpegStatusLabel: some View {
        if let resolved = viewModel.resolvedFFmpegPath {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(resolved)
                    .font(.callout.monospaced())
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(resolved)
                if viewModel.ffmpegUserPath.isEmpty {
                    Text("Auto")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(viewModel.ffmpegUserPath.isEmpty ? "Not found at standard paths" : "Not found at configured path")
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
