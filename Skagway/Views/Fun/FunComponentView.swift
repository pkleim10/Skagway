import SwiftUI

/// Playground window for experimenting with custom chrome (independent of Settings).
/// Library / Video sheets bind to the same `LibraryViewModel` as Settings.
struct FunComponentView: View {
    @Bindable var appState: AppState

    /// Window fill (hidden once sidebar + content cover the window).
    var backgroundColor: Color = Color(red: 135 / 255, green: 206 / 255, blue: 235 / 255) // sky blue

    /// Sidebar fill — Settings-sidebar width, full height including title-bar safe area.
    var sidebarColor: Color = Color(red: 22 / 255, green: 24 / 255, blue: 26 / 255)
    private let sidebarWidth: CGFloat = 200

    /// Content pane fill — everything not occupied by the sidebar.
    var contentColor: Color = Color(red: 36 / 255, green: 40 / 255, blue: 42 / 255)

    /// Inset between content edges and cards / title.
    private let contentPadding: CGFloat = 22
    /// Header strip above the first card (layout height below the safe area).
    private let titleBandHeight: CGFloat = 56
    private let cardCornerRadius: CGFloat = 10

    /// Card fill inside the content pane.
    var cardColor: Color = Color(red: 43 / 255, green: 47 / 255, blue: 48 / 255)
    /// Inset row separator inside a card.
    private let separatorColor = Color(red: 53 / 255, green: 56 / 255, blue: 58 / 255)

    @State private var selectedCategory: SettingsCategory? = .library
    @State private var searchText = ""

    /// Extensions sheet (wired to `VideoExtensionManager.shared`).
    @State private var newExtensionText = ""
    @State private var hoveredExtension: String?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [SettingsSearchItem] {
        SettingsSearchCatalog.matches(for: searchText)
    }

    private var contentTitle: String {
        selectedCategory?.title ?? "Library"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(sidebarColor.ignoresSafeArea(edges: .top))

            contentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(contentColor.ignoresSafeArea(edges: .top))
        }
        .frame(minWidth: 720, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor.ignoresSafeArea())
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)

            List(selection: $selectedCategory) {
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
                        .tag(item.category)
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
            .overlay {
                if isSearching && searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    // MARK: - Content

    private var contentPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                let safeTop = geo.safeAreaInsets.top
                let visualBandHeight = safeTop + titleBandHeight
                Text(contentTitle)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, contentPadding)
                    .frame(width: geo.size.width, height: visualBandHeight, alignment: .leading)
                    .offset(y: -safeTop)
            }
            .frame(height: titleBandHeight)

            ScrollView {
                Group {
                    switch selectedCategory {
                    case .library, .none:
                        if let viewModel = appState.libraryViewModel {
                            librarySettingsContent(viewModel: viewModel)
                        } else {
                            libraryRequiredPlaceholder
                        }
                    case .video:
                        if let viewModel = appState.libraryViewModel {
                            videoSettingsContent(viewModel: viewModel)
                        } else {
                            libraryRequiredPlaceholder
                        }
                    case .fileExt:
                        extensionsSettingsContent
                    case .dataSources, .tools, .customMetadata:
                        EmptyView()
                    }
                }
                .padding(.horizontal, contentPadding)
                .padding(.bottom, contentPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var libraryRequiredPlaceholder: some View {
        ContentUnavailableView(
            "Open a Library",
            systemImage: "books.vertical",
            description: Text("Library and Video settings appear once a library is open.")
        )
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - Library

    @ViewBuilder
    private func librarySettingsContent(viewModel: LibraryViewModel) -> some View {
        @Bindable var viewModel = viewModel
        let listableCustomDefinitions = viewModel.customMetadataFieldDefinitions
            .filter { $0.valueType != .text }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        VStack(alignment: .leading, spacing: 20) {
            settingsCard {
                describedToggleRow(
                    title: "Exclude corrupt files from filters",
                    description: "Corrupt files (missing duration and resolution) will be hidden from Library, Collections, Rating, and Tag filters. They remain visible in the Corrupt filter and name search.",
                    isOn: $viewModel.excludeCorrupt
                )
                cardSeparator
                describedToggleRow(
                    title: "Confirm deletions",
                    description: "When enabled, a confirmation dialog will appear before moving files to Trash.",
                    isOn: $viewModel.confirmDeletions
                )
            }

            sectionBlock(title: "Updates") {
                settingsCard {
                    describedToggleRow(
                        title: "Automatically check for updates",
                        description: "Occasionally checks downloads.machiilabs.com for a newer Skagway build. Does not send usage analytics.",
                        isOn: Binding(
                            get: { UpdateChecker.shared.automaticallyChecksForUpdates },
                            set: { UpdateChecker.shared.automaticallyChecksForUpdates = $0 }
                        )
                    )
                }
            }

            sectionBlock(title: "Smart Libraries") {
                settingsCard {
                    smartLibraryRow("Recently Added", isOn: $viewModel.showRecentlyAdded) {
                        SettingsIntegerStepper(value: $viewModel.recentlyAddedDays, range: 1...365, unit: "days")
                            .disabled(!viewModel.showRecentlyAdded)
                            .opacity(viewModel.showRecentlyAdded ? 1 : 0.45)
                    }
                    cardSeparator
                    smartLibraryRow("Recently Played", isOn: $viewModel.showRecentlyPlayed) {
                        SettingsIntegerStepper(value: $viewModel.recentlyPlayedDays, range: 1...365, unit: "days")
                            .disabled(!viewModel.showRecentlyPlayed)
                            .opacity(viewModel.showRecentlyPlayed ? 1 : 0.45)
                    }
                    cardSeparator
                    smartLibraryRow("Top Rated", isOn: $viewModel.showTopRated) {
                        RatingView(rating: viewModel.topRatedMinRating, size: 14) { newRating in
                            viewModel.topRatedMinRating = max(newRating, 1)
                        }
                        .disabled(!viewModel.showTopRated)
                        .opacity(viewModel.showTopRated ? 1 : 0.4)
                    }
                    cardSeparator
                    plainToggleRow("Duplicates", isOn: $viewModel.showDuplicates)
                    cardSeparator
                    plainToggleRow("Corrupt", isOn: $viewModel.showCorrupt)
                    cardSeparator
                    plainToggleRow("Missing", isOn: $viewModel.showMissing)
                    cardSeparator
                    plainToggleRow("Recently Converted", isOn: $viewModel.showRecentlyConverted)
                }
            }

            sectionBlock(title: "List view columns") {
                settingsCard {
                    listColumnNameRow
                    cardSeparator
                    plainToggleRow("Duration", isOn: standardColumnBinding(viewModel, id: "duration"))
                    cardSeparator
                    plainToggleRow("Resolution", isOn: standardColumnBinding(viewModel, id: "resolution"))
                    cardSeparator
                    plainToggleRow("File size", isOn: standardColumnBinding(viewModel, id: "size"))
                    cardSeparator
                    plainToggleRow("Rating", isOn: standardColumnBinding(viewModel, id: "rating"))
                    cardSeparator
                    plainToggleRow("Date added", isOn: standardColumnBinding(viewModel, id: "dateAdded"))
                    cardSeparator
                    plainToggleRow("Plays", isOn: standardColumnBinding(viewModel, id: "playCount"))
                    cardSeparator
                    plainToggleRow("Created", isOn: standardColumnBinding(viewModel, id: "created"))
                    cardSeparator
                    plainToggleRow("Last played", isOn: standardColumnBinding(viewModel, id: "lastPlayed"))

                    if listableCustomDefinitions.isEmpty {
                        cardSeparator
                        Text("No listable custom metadata fields (multiline “Text” fields are excluded). Add fields in Custom Metadata settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(listableCustomDefinitions) { field in
                            cardSeparator
                            plainToggleRow(field.name, isOn: customColumnBinding(viewModel, id: field.id))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Video

    @ViewBuilder
    private func videoSettingsContent(viewModel: LibraryViewModel) -> some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 20) {
            sectionBlock(title: "Default Filmstrip Size") {
                settingsCard {
                    describedTrailingRow(
                        title: "Rows",
                        description: "Default grid size when generating new filmstrips. Override per video with Modify Filmstrip."
                    ) {
                        SettingsIntegerStepper(value: $viewModel.defaultFilmstripRows, range: 1...6)
                    }
                    cardSeparator
                    plainTrailingRow("Columns") {
                        SettingsIntegerStepper(value: $viewModel.defaultFilmstripColumns, range: 1...8)
                    }
                    cardSeparator
                    plainTrailingRow("Frames per filmstrip") {
                        Text("\(viewModel.defaultFilmstripRows * viewModel.defaultFilmstripColumns)")
                            .foregroundStyle(Color.secondary)
                            .monospacedDigit()
                    }
                    cardSeparator
                    Button("Regenerate filmstrips") {
                        Task { await viewModel.clearFilmstripCacheAndMarkApplied() }
                    }
                    .disabled(!viewModel.filmstripLayoutChanged)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            settingsCard {
                describedToggleRow(
                    title: "Surprise Me! auto-plays selected video",
                    description: "Updates selection immediately, loads or generates the filmstrip for the detail pane, starts auto-play if enabled, then scrolls the grid or list to the selection.",
                    isOn: $viewModel.surpriseMeAutoPlays
                )
                cardSeparator
                describedToggleRow(
                    title: "Hover preview on Grid cards",
                    description: "Plays a muted cycling scrub when the pointer rests on a Grid card (disabled automatically while the floating player is open).",
                    isOn: $viewModel.gridHoverPreviewEnabled
                )
            }

            sectionBlock(title: "Tags") {
                settingsCard {
                    describedPickerRow(
                        title: "Tag blind default state",
                        description: "Controls the Inspector’s “Add tags” blind (the unassigned-tags list) each time you select a different video: always start closed, always start open, or leave it exactly as you last set it.",
                        selection: $viewModel.tagBlindDefaultState
                    ) {
                        ForEach(TagBlindDefaultState.allCases) { state in
                            Text(state.label).tag(state)
                        }
                    }
                }
            }

            sectionBlock(title: "Filters") {
                settingsCard {
                    describedPickerRow(
                        title: "Filter drawer height",
                        description: "How the filters drawer sizes itself when opened. Fit to content sizes it to just show all the filter cards (no scrollbar) and hides the resize handle; Last used reopens it at whatever height you last dragged it to.",
                        selection: $viewModel.filterDrawerHeightMode
                    ) {
                        ForEach(FilterDrawerHeightMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }
            }

            settingsCard {
                describedPickerRow(
                    title: "Player opens at",
                    description: "When you start inline playback, the resizable player opens at this size. Compact fits the inspector still/filmstrip area; Full screen opens borderless edge-to-edge; Last used size reopens the player at whatever size you last left it. You can always resize, snap, or go full-screen from the player's own controls.",
                    selection: $viewModel.playerStartPreference
                ) {
                    ForEach(PlayerStartPreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
            }

            sectionBlock(title: "Playback") {
                settingsCard {
                    describedToggleRow(
                        title: "Fade resume banner after delay",
                        description: "After resuming inline playback from a remembered position, Skagway shows a banner with Start at beginning. When fade is enabled, that banner fades out after the delay; playback keeps going from the resumed time.",
                        isOn: $viewModel.fadeResumeBannerAutomatically
                    )
                    cardSeparator
                    plainTrailingRow("Seconds before fade") {
                        SettingsIntegerStepper(
                            value: $viewModel.resumeBannerFadeDelaySeconds,
                            range: 1...120,
                            unit: "sec"
                        )
                    }
                    .disabled(!viewModel.fadeResumeBannerAutomatically)
                    .opacity(viewModel.fadeResumeBannerAutomatically ? 1 : 0.45)
                }
            }
        }
    }

    private func standardColumnBinding(_ viewModel: LibraryViewModel, id: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.isStandardListColumnVisible(id) },
            set: { viewModel.setStandardListColumnVisible(id, visible: $0) }
        )
    }

    private func customColumnBinding(_ viewModel: LibraryViewModel, id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.isCustomListFieldVisible(id) },
            set: { viewModel.setCustomListFieldVisible(fieldId: id, visible: $0) }
        )
    }

    // MARK: - Extensions

    private var extensionsSettingsContent: some View {
        @Bindable var manager = VideoExtensionManager.shared

        return VStack(alignment: .leading, spacing: 20) {
            sectionBlock(title: "Extensions") {
                Text("Turn the toggle off to temporarily exclude an extension from folder scans. Hover a row and click Remove to delete it from the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)

                settingsCard {
                    ForEach(Array(manager.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { cardSeparator }
                        extensionRow(entry, manager: manager)
                    }
                }
            }

            sectionBlock(title: "Add Extension") {
                settingsCard {
                    describedTrailingRow(
                        title: "Extension",
                        description: "Add a file extension Skagway should treat as video when scanning folders."
                    ) {
                        HStack(spacing: 8) {
                            TextField("e.g. mp4", text: $newExtensionText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .onSubmit { addExtension(to: manager) }
                            Button("Add") { addExtension(to: manager) }
                                .disabled(newExtensionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }

            settingsCard {
                Button("Reset to Defaults") {
                    manager.resetToDefaults()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func extensionRow(_ entry: VideoExtensionEntry, manager: VideoExtensionManager) -> some View {
        let isHovered = hoveredExtension == entry.ext
        return HStack(spacing: 12) {
            Text(".\(entry.ext)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(entry.enabled ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Remove") {
                manager.remove(entry.ext)
                if hoveredExtension == entry.ext {
                    hoveredExtension = nil
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .help("Remove .\(entry.ext)")
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            .accessibilityHidden(!isHovered)

            Toggle(
                "",
                isOn: Binding(
                    get: { entry.enabled },
                    set: { manager.setEnabled(entry.ext, $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredExtension = entry.ext
            } else if hoveredExtension == entry.ext {
                hoveredExtension = nil
            }
        }
    }

    private func addExtension(to manager: VideoExtensionManager) {
        let trimmed = newExtensionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        manager.add(trimmed)
        newExtensionText = ""
    }

    // MARK: - Card / row helpers

    private func sectionBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardColor, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
    }

    private var cardSeparator: some View {
        Rectangle()
            .fill(separatorColor)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func describedToggleRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plainToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smartLibraryRow<Trailing: View>(
        _ title: String,
        isOn: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var listColumnNameRow: some View {
        HStack(alignment: .firstTextBaseline) {
            SettingsLabel(
                "Name",
                description: "Always visible. Choose which metadata columns appear in list view. Up to 16 custom columns can be shown at once (alphabetically). Reorder and resize visible columns from the table header."
            )
            Spacer(minLength: 8)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.secondary)
                .help("Always visible")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plainTrailingRow<Trailing: View>(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func describedTrailingRow<Trailing: View>(
        title: String,
        description: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func describedPickerRow<Selection: Hashable, Options: View>(
        title: String,
        description: String,
        selection: Binding<Selection>,
        @ViewBuilder options: () -> Options
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Same chrome Settings Form uses for pickers (borderless popup).
            Picker("", selection: selection) {
                options()
            }
            .labelsHidden()
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
