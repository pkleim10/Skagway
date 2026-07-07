import SwiftUI

/// Elegant top-descending filters drawer for the Curated Wall variant.
/// Always presented above the wall content when open. Changes are live (no Apply).
/// Styled to feel part of the cinematic gallery experience (blue accents, refined materials, generous breathing).
struct CuratedWallFiltersDrawer: View {
    @Bindable var viewModel: LibraryViewModel
    /// Reports the drawer's natural content height (header + cards at the current width) so the
    /// resize handle can cap the height there — dragging taller than this would just add empty
    /// space / a pointless scroll region. Recomputed when the width (column packing) or the number
    /// of filter items changes.
    var onNaturalHeightChanged: ((CGFloat) -> Void)? = nil

    @State private var tagSearch: String = ""
    @State private var newTagText: String = ""
    @State private var hoverRating: Int?
    @State private var showNewCollectionSheet = false
    @State private var editingCollection: VideoCollection?
    @State private var tagPendingRename: Tag?
    @State private var tagPendingDelete: Tag?
    @State private var measuredHeaderHeight: CGFloat = 0
    @State private var measuredCardsHeight: CGFloat = 0
    @State private var renameText: String = ""
    /// Set right after "Add Filter" adds a new custom-field row, so its primary input grabs focus
    /// immediately instead of requiring an extra click.
    @FocusState private var focusedCustomFieldFilterId: UUID?
    /// Same, for a newly-added built-in field row (text/number kinds).
    @FocusState private var focusedBuiltinFilterField: BuiltinFilterField?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .background(GeometryReader { p in
                    Color.clear.preference(key: DrawerHeaderHeightKey.self, value: p.size.height)
                })

            // Cards pack column-major (stacked top→bottom within a column, columns left→right)
            // so reading order is preserved as the wall restacks: at full width the four units
            // sit 4-across; as the wall narrows they collapse to fewer columns — e.g. at 3
            // columns: [Smart Libraries + Collections] [Rating + Duration] [Tags].
            GeometryReader { geo in
                ScrollView(.vertical) {
                    cardColumns(availableWidth: geo.size.width)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        // Fill the full drawer width (columns stay left-aligned) so the vertical
                        // scrollbar sits at the right edge of the drawer, not against the last card.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Measure the cards' *natural* height (the ScrollView gives its content its
                        // ideal size) so the call site can cap resizing at "no scrollbar needed".
                        .background(GeometryReader { p in
                            Color.clear.preference(key: DrawerCardsHeightKey.self, value: p.size.height)
                        })
                }
            }
            // Height is controlled by the presentation site (Animated well in ContentView)
            // so the drawer can participate in smooth height transitions. Capped at call site.
        }
        .onPreferenceChange(DrawerHeaderHeightKey.self) { h in
            measuredHeaderHeight = h
            reportNaturalHeight()
        }
        .onPreferenceChange(DrawerCardsHeightKey.self) { h in
            measuredCardsHeight = h
            reportNaturalHeight()
        }
        .background(
            Color.appSurface
                .opacity(0.96)
                .background(Material.ultraThin)
        )
        .overlay(
            Rectangle()
                .fill(Color.appDivider)
                .frame(height: 1),
            alignment: .bottom
        )
        .sheet(isPresented: $showNewCollectionSheet) {
            CollectionEditorView(
                dbPool: viewModel.dbPool,
                collection: nil,
                onSave: { Task { await viewModel.loadCollections() } }
            )
        }
        .sheet(item: $editingCollection) { collection in
            CollectionEditorView(
                dbPool: viewModel.dbPool,
                collection: collection,
                onSave: { Task { await viewModel.loadCollections() } }
            )
        }
    }

    // MARK: - Responsive column packing

    // The five filter units in reading order. Rating + Duration are grouped so they always travel
    // together. The natural (max) width of each is used to decide how many columns fit. The 5th
    // unit ("More Filters") is always present -- it hosts the shared "Add filter" menu for every
    // built-in field (Quality/Size/Date/Plays/Codec/…) plus custom fields.
    private let unitWidths: [CGFloat] = [260, 240, 320, 360, 340]

    @ViewBuilder
    private func unitView(_ index: Int) -> some View {
        switch index {
        case 0: smartLibrariesCard
        case 1: collectionsCard
        case 2: ratingDurationColumn
        case 3: tagsCard
        default: moreFiltersCard
        }
    }

    /// Distribute `count` ordered units into `columns` groups, preserving order and giving
    /// earlier columns the surplus (e.g. 4 units / 3 columns -> [[0,1], [2], [3]]).
    private func distribute(count: Int, into columns: Int) -> [[Int]] {
        var result: [[Int]] = []
        var idx = 0
        for col in 0..<columns {
            let remainingUnits = count - idx
            let remainingCols = columns - col
            let take = Int((Double(remainingUnits) / Double(remainingCols)).rounded(.up))
            result.append(Array(idx..<(idx + take)))
            idx += take
        }
        return result
    }

    /// Column-major layout: picks the largest column count (1...4) whose combined width fits
    /// the available drawer width, then stacks the ordered units into those columns. Each
    /// column is as wide as its widest unit, and cards fill that width.
    private func cardColumns(availableWidth: CGFloat) -> some View {
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 16
        let usable = availableWidth - horizontalPadding * 2
        let count = unitWidths.count

        func layoutWidth(_ groups: [[Int]]) -> CGFloat {
            let columnsWidth = groups.reduce(CGFloat(0)) { sum, idxs in
                sum + (idxs.map { unitWidths[$0] }.max() ?? 0)
            }
            return columnsWidth + spacing * CGFloat(max(0, groups.count - 1))
        }

        var chosen = 1
        for columns in stride(from: count, through: 1, by: -1) {
            if layoutWidth(distribute(count: count, into: columns)) <= usable {
                chosen = columns
                break
            }
        }

        let groups = distribute(count: count, into: chosen)

        return HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(groups.enumerated()), id: \.offset) { offset, idxs in
                let columnWidth = idxs.map { unitWidths[$0] }.max() ?? 0
                // The last column always stretches to fill the remaining width so its cards
                // reach the drawer's right edge instead of leaving a gap beside them.
                let isLastColumn = offset == groups.count - 1
                VStack(spacing: spacing) {
                    ForEach(idxs, id: \.self) { i in
                        unitView(i)
                    }
                }
                .frame(
                    minWidth: columnWidth,
                    maxWidth: isLastColumn ? .infinity : columnWidth,
                    alignment: .leading
                )
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Filters")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            Spacer()

            if viewModel.hasActiveFilters {
                Button("Clear all") {
                    viewModel.resetAllFilters()
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(Color.appAccent)
                .help("Clear all filters (sidebar, tags, rating, duration)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.appBackground.opacity(0.6))
    }

    // Reusable card container for a filter category.
    // Used so Smart Libraries / Collections / Rating / Duration / Tags appear as distinct cards.
    private func makeFilterCard<Content: View, Accessory: View>(
        title: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                sectionLabel(title)
                Spacer()
                accessory()
            }
            content()
        }
        .padding(10)
        // Fill the allotted column width so the card background stretches edge-to-edge
        // instead of shrinkwrapping to its content (keeps equal-width columns equal).
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.appSurface.opacity(0.5)
                .background(Material.ultraThin)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appDivider.opacity(0.4), lineWidth: 1)
        )
    }

    private func libraryRow(_ title: String, icon: String, count: Int, filter: SidebarFilter) -> some View {
        let isSelected = viewModel.sidebarFilter == filter
        return Button {
            viewModel.sidebarFilter = filter
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isSelected ? Color.appAccent : Color.appTextSecondary)
                    .frame(width: 16)
                Text(title)
                    .foregroundStyle(isSelected ? Color.appTextPrimary : Color.appTextSecondary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Like `libraryRow`, but with a trailing rescan button — the missing-file count is a
    /// point-in-time filesystem check (`refreshMissingCount()`), not something kept live, so it
    /// can go stale (a drive gets reconnected, a file moves back). This lets you force a fresh
    /// scan without switching away from and back to the Missing filter.
    private func missingLibraryRow(count: Int) -> some View {
        let isSelected = viewModel.sidebarFilter == .missing
        return HStack(spacing: 4) {
            Button {
                viewModel.sidebarFilter = .missing
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(isSelected ? Color.appAccent : Color.appTextSecondary)
                        .frame(width: 16)
                    Text("Missing")
                        .foregroundStyle(isSelected ? Color.appTextPrimary : Color.appTextSecondary)
                    Spacer()
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.appTextTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.refreshMissingCount() }
            } label: {
                if viewModel.isRefreshingMissing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appTextTertiary)
            .disabled(viewModel.isRefreshingMissing)
            .help("Rescan for missing files")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.appAccent.opacity(0.12) : Color.clear)
        )
    }

    // MARK: - Cards (horizontal wrapping layout in the drawer)

    private var smartLibrariesCard: some View {
        makeFilterCard(title: "SMART LIBRARIES") {
            VStack(spacing: 2) {
                libraryRow("All Videos", icon: "film.stack", count: viewModel.libraryCounts.all, filter: .all)

                if viewModel.showRecentlyAdded {
                    libraryRow("Recently Added", icon: "clock", count: viewModel.libraryCounts.recentlyAdded, filter: .recentlyAdded)
                }
                if viewModel.showRecentlyPlayed {
                    libraryRow("Recently Played", icon: "play.circle", count: viewModel.libraryCounts.recentlyPlayed, filter: .recentlyPlayed)
                }
                if viewModel.showTopRated {
                    libraryRow("Top Rated", icon: "star.fill", count: viewModel.libraryCounts.topRated, filter: .topRated)
                }
                if viewModel.showDuplicates {
                    libraryRow("Duplicates", icon: "doc.on.doc", count: viewModel.libraryCounts.duplicates, filter: .duplicates)
                }
                if viewModel.showCorrupt {
                    libraryRow("Corrupt", icon: "exclamationmark.triangle", count: viewModel.libraryCounts.corrupt, filter: .corrupt)
                }
                if viewModel.showMissing {
                    missingLibraryRow(count: viewModel.libraryCounts.missing)
                }
                if viewModel.showRecentlyConverted {
                    libraryRow("Recently Converted", icon: "arrow.triangle.2.circlepath", count: viewModel.libraryCounts.recentlyConverted, filter: .recentlyConverted)
                }
            }
        }
    }

    private var collectionsCard: some View {
        makeFilterCard(title: "COLLECTIONS", accessory: {
            clearFilterAccessory {
                if case .collection = viewModel.sidebarFilter {
                    viewModel.sidebarFilter = .all
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.collections.isEmpty {
                    Text("No collections yet")
                        .font(.caption)
                        .foregroundStyle(Color.appTextTertiary)
                } else if viewModel.collections.count > 6 {
                    // Alphabetical, not ranked — there's no meaningful "top" subset to prefer,
                    // so always show everything and scroll internally past the usual height
                    // instead of growing this card unbounded.
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(viewModel.collections, id: \.listId) { collection in
                                collectionRow(collection)
                            }
                        }
                    }
                    .frame(maxHeight: 168)
                    .scrollIndicators(.visible)
                } else {
                    ForEach(viewModel.collections, id: \.listId) { collection in
                        collectionRow(collection)
                    }
                }

                // Add a new (smart) collection.
                Button { showNewCollectionSheet = true } label: {
                    Label("New Collection", systemImage: "plus")
                        .font(.caption)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func collectionRow(_ collection: VideoCollection) -> some View {
        let isSelected: Bool = {
            if case .collection(let c) = viewModel.sidebarFilter, c.id == collection.id { return true }
            return false
        }()
        Button {
            viewModel.sidebarFilter = .collection(collection)
        } label: {
            HStack {
                Text(collection.name)
                    .foregroundStyle(isSelected ? Color.appTextPrimary : Color.appTextSecondary)
                Spacer()
                if let id = collection.id, let c = viewModel.collectionCounts[id] {
                    Text("\(c)").font(.caption.monospacedDigit()).foregroundStyle(Color.appTextTertiary)
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.appAccent.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Collection\u{2026}") { editingCollection = collection }
            Divider()
            Button("Delete Collection", role: .destructive) {
                Task { await viewModel.deleteCollection(collection) }
            }
        }
    }

    // Rating and Duration are grouped into a single fixed-width column so they wrap as one
    // unit and keep matching widths.
    private var ratingDurationColumn: some View {
        VStack(spacing: 12) {
            ratingCard
            durationCard
        }
    }

    private var ratingCard: some View {
        makeFilterCard(title: "RATING") {
            let level = viewModel.selectedRatingStars.first ?? 0
            let preview = hoverRating ?? level

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    let isActive = preview > 0 && star <= preview
                    Button {
                        if star == level {
                            viewModel.clearRatingFilter()
                        } else {
                            viewModel.selectedRatingStars = [star]
                        }
                        hoverRating = nil
                    } label: {
                        Image(systemName: isActive ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundStyle(isActive ? .yellow : Color.appTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Rating \(star)")
                    .onHover { hovering in
                        hoverRating = hovering ? star : nil
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationCard: some View {
        makeFilterCard(title: "DURATION") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Min")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    TextField("0", value: Binding(
                        get: { (viewModel.minDurationSeconds ?? 0) / 60.0 },
                        set: { viewModel.minDurationSeconds = $0 > 0 ? $0 * 60 : nil }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("min")

                    Spacer().frame(width: 12)

                    Text("Max")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                    TextField("", value: Binding(
                        get: { viewModel.maxDurationSeconds.map { $0 / 60 } ?? 0 },
                        set: { viewModel.maxDurationSeconds = ($0 > 0 ? $0 * 60 : nil) }
                    ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("min")

                    if viewModel.minDurationSeconds != nil || viewModel.maxDurationSeconds != nil {
                        Spacer()
                        Button("Clear") {
                            viewModel.clearDurationFilter()
                        }
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                        .buttonStyle(.plain)
                    }
                }

                // Presets
                HStack(spacing: 6) {
                    durationPreset("Any", min: nil, max: nil)
                    durationPreset("< 1 min", min: nil, max: 60)
                    durationPreset("1–5 min", min: 60, max: 5 * 60)
                    durationPreset("5–30 min", min: 5 * 60, max: 30 * 60)
                    durationPreset("> 30 min", min: 30 * 60, max: nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagsCard: some View {
        makeFilterCard(title: "TAGS", accessory: {
            clearFilterAccessory { viewModel.clearTagFilters() }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // Any / All mode
                Picker("Match", selection: $viewModel.tagFilterMode) {
                    Text("Any").tag(MatchMode.any)
                    Text("All").tag(MatchMode.all)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 140)
                .padding(.bottom, 2)

                // Tag search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.appTextTertiary)
                    TextField("Search tags", text: $tagSearch)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Color.appTextPrimary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.appSurface.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 4)

                // New tag — creates a standalone tag (not assigned to any video yet), so it's
                // ready to apply later. Field clears on each add so several can be created in a
                // row without re-focusing or reopening anything.
                HStack(spacing: 6) {
                    TextField("Tag name", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.appTextPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.appSurface.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onSubmit { createNewTag() }

                    Button { createNewTag() } label: {
                        Label("New Tag", systemImage: "plus")
                            .font(.caption)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appAccent)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.bottom, 4)

                // Tags in a compact grid suitable for card width (wraps via outer FlowLayout of cards)
                let filteredTags = viewModel.tags
                    .filter { t in
                        guard let id = t.id else { return false }
                        if tagSearch.trimmingCharacters(in: .whitespaces).isEmpty {
                            return true
                        }
                        return t.name.localizedCaseInsensitiveContains(tagSearch)
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                if filteredTags.isEmpty {
                    Text("No matching tags")
                        .font(.caption)
                        .foregroundStyle(Color.appTextTertiary)
                        .padding(.vertical, 2)
                } else {
                    let tagColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
                    LazyVGrid(columns: tagColumns, alignment: .leading, spacing: 4) {
                        ForEach(filteredTags, id: \.id) { tag in
                            tagFilterRow(tag)
                        }
                    }
                }
            }
        }
        .alert("Rename Tag",
               isPresented: Binding(get: { tagPendingRename != nil },
                                    set: { if !$0 { tagPendingRename = nil } })) {
            TextField("Tag name", text: $renameText)
            Button("Rename") {
                if let tag = tagPendingRename {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { Task { await viewModel.renameTag(tag, to: name) } }
                }
                tagPendingRename = nil
            }
            Button("Cancel", role: .cancel) { tagPendingRename = nil }
        }
        .alert("Delete tag \u{201C}\(tagPendingDelete?.name ?? "")\u{201D}?",
               isPresented: Binding(get: { tagPendingDelete != nil },
                                    set: { if !$0 { tagPendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let tag = tagPendingDelete { Task { await viewModel.deleteTag(tag) } }
                tagPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { tagPendingDelete = nil }
        } message: {
            Text("This removes the tag from your library and unassigns it from every video. This can\u{2019}t be undone.")
        }
    }

    // MARK: - Custom Fields

    /// The shared "Add filter" surface (Tier 1): one menu offering every built-in field not already
    /// active (Quality/Size/Date/Plays/Codec/Extension/Folder) plus every custom field not already
    /// active, and a removable, type-appropriate row for each active one. All rows AND together with
    /// each other and with the pinned Rating/Duration/Tags/sidebar filters.
    private var moreFiltersCard: some View {
        makeFilterCard(title: "MORE FILTERS", accessory: {
            if !viewModel.builtinFilters.isEmpty || !viewModel.customFieldFilters.isEmpty {
                clearFilterAccessory {
                    viewModel.clearBuiltinFilters()
                    viewModel.clearCustomFieldFilters()
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                let availableBuiltins = BuiltinFilterField.allCases
                    .filter { viewModel.builtinFilters[$0] == nil }
                let availableCustom = viewModel.customMetadataFieldDefinitions
                    .filter { viewModel.customFieldFilters[$0.id] == nil }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                Menu {
                    ForEach(availableBuiltins) { field in
                        Button(field.label) {
                            viewModel.addBuiltinFilter(field)
                            focusedBuiltinFilterField = field
                        }
                    }
                    if !availableBuiltins.isEmpty && !availableCustom.isEmpty {
                        Divider()
                    }
                    ForEach(availableCustom) { field in
                        Button(field.name) {
                            viewModel.addCustomFieldFilter(fieldId: field.id, valueType: field.valueType)
                            focusedCustomFieldFilterId = field.id
                        }
                    }
                } label: {
                    Label("Add filter", systemImage: "plus")
                        .font(.caption)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .disabled(availableBuiltins.isEmpty && availableCustom.isEmpty)

                // Active built-in rows first (in field declaration order), then active custom-field
                // rows (alphabetical). Both orders are stable across recomputes -- dictionary
                // iteration order isn't.
                let activeBuiltins = BuiltinFilterField.allCases.filter { viewModel.builtinFilters[$0] != nil }
                let activeCustom = viewModel.customMetadataFieldDefinitions
                    .filter { viewModel.customFieldFilters[$0.id] != nil }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                if !activeBuiltins.isEmpty || !activeCustom.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(activeBuiltins) { field in
                            builtinFilterRow(field)
                        }
                        ForEach(activeCustom) { field in
                            customFieldFilterRow(field)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func customFieldFilterRow(_ field: CustomMetadataFieldDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                Button {
                    viewModel.removeCustomFieldFilter(fieldId: field.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appTextTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            switch field.valueType {
            case .string, .text:
                TextField("Contains…", text: customFieldContainsBinding(for: field.id))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .focused($focusedCustomFieldFilterId, equals: field.id)

            case .number:
                HStack(spacing: 6) {
                    TextField("Min", value: customFieldNumberBinding(for: field.id, isMin: true), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .focused($focusedCustomFieldFilterId, equals: field.id)
                    Text("–").foregroundStyle(Color.appTextSecondary)
                    TextField("Max", value: customFieldNumberBinding(for: field.id, isMin: false), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }
                .font(.caption)

            case .date, .dateTime:
                let showsTime = field.valueType == .dateTime
                VStack(alignment: .leading, spacing: 4) {
                    customFieldDateBoundRow(fieldId: field.id, isMin: true, label: "From", showsTime: showsTime)
                    customFieldDateBoundRow(fieldId: field.id, isMin: false, label: "To", showsTime: showsTime)
                }
            }
        }
        .padding(8)
        .background(Color.appSurface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func customFieldDateBoundRow(fieldId: UUID, isMin: Bool, label: String, showsTime: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 32, alignment: .leading)
            if customFieldDateBound(for: fieldId, isMin: isMin) != nil {
                DatePicker(
                    "",
                    selection: customFieldDateBinding(for: fieldId, isMin: isMin),
                    displayedComponents: showsTime ? [.date, .hourAndMinute] : [.date]
                )
                .labelsHidden()
                .font(.caption)
                Button {
                    customFieldSetDateBound(for: fieldId, isMin: isMin, to: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appTextTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if isMin {
                // Date rows have no text input to focus until a bound is set (DatePicker has no
                // "empty" state), so on add, give keyboard focus to the "From" side's "Set…"
                // button instead -- Space/Return then creates the bound and reveals the DatePicker.
                // (Only the "From" row applies the focus binding -- the "To" row's button must
                // never be considered focused just because nothing else currently is.)
                Button("Set…") {
                    customFieldSetDateBound(for: fieldId, isMin: isMin, to: Date())
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .focused($focusedCustomFieldFilterId, equals: fieldId)
            } else {
                Button("Set…") {
                    customFieldSetDateBound(for: fieldId, isMin: isMin, to: Date())
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
            }
        }
    }

    // MARK: - Custom Fields bindings

    private func customFieldContainsBinding(for fieldId: UUID) -> Binding<String> {
        Binding(
            get: {
                if case .contains(let s) = viewModel.customFieldFilters[fieldId] { return s }
                return ""
            },
            set: { viewModel.setCustomFieldContainsFilter(fieldId: fieldId, text: $0) }
        )
    }

    private func customFieldNumberBinding(for fieldId: UUID, isMin: Bool) -> Binding<Double?> {
        Binding(
            get: {
                guard case .numberRange(let min, let max) = viewModel.customFieldFilters[fieldId] else { return nil }
                return isMin ? min : max
            },
            set: { newValue in
                guard case .numberRange(let min, let max) = viewModel.customFieldFilters[fieldId] else { return }
                viewModel.setCustomFieldNumberRangeFilter(
                    fieldId: fieldId,
                    min: isMin ? newValue : min,
                    max: isMin ? max : newValue
                )
            }
        )
    }

    private func customFieldDateBound(for fieldId: UUID, isMin: Bool) -> Date? {
        guard case .dateRange(let min, let max) = viewModel.customFieldFilters[fieldId] else { return nil }
        return isMin ? min : max
    }

    private func customFieldSetDateBound(for fieldId: UUID, isMin: Bool, to newValue: Date?) {
        guard case .dateRange(let min, let max) = viewModel.customFieldFilters[fieldId] else { return }
        viewModel.setCustomFieldDateRangeFilter(
            fieldId: fieldId,
            min: isMin ? newValue : min,
            max: isMin ? max : newValue
        )
    }

    /// `DatePicker` needs a non-optional binding; only shown once a bound has been set via "Set…",
    /// so the `?? Date()` fallback here is never actually exercised by the UI.
    private func customFieldDateBinding(for fieldId: UUID, isMin: Bool) -> Binding<Date> {
        Binding(
            get: { customFieldDateBound(for: fieldId, isMin: isMin) ?? Date() },
            set: { customFieldSetDateBound(for: fieldId, isMin: isMin, to: $0) }
        )
    }

    // MARK: - Built-in field filter rows

    @ViewBuilder
    private func builtinFilterRow(_ field: BuiltinFilterField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.appTextPrimary)
                Spacer()
                Button {
                    viewModel.removeBuiltinFilter(field)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appTextTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            builtinFilterControl(field)
        }
        .padding(8)
        .background(Color.appSurface.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func builtinFilterControl(_ field: BuiltinFilterField) -> some View {
        switch field {
        case .quality: builtinQualityControl()
        case .fileSize: builtinSizeControl()
        case .dateAdded, .dateCreated: builtinDateControl(field)
        case .plays: builtinPlaysControl()
        case .codec, .fileExtension, .folder: builtinContainsControl(field)
        }
    }

    // Quality — resolution-bucket chips (OR within the selected set).
    private func builtinQualityControl() -> some View {
        let selected = builtinQualityBuckets
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(ResolutionBucket.allCases) { bucket in
                let on = selected.contains(bucket.rawValue)
                Button {
                    toggleBuiltinQualityBucket(bucket.rawValue)
                } label: {
                    Text(bucket.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? Color.appAccent.opacity(0.85) : Color.appSurface.opacity(0.6)))
                        .foregroundStyle(on ? Color.white : Color.appTextSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var builtinQualityBuckets: Set<String> {
        if case .quality(let s) = viewModel.builtinFilters[.quality] { return s }
        return []
    }

    private func toggleBuiltinQualityBucket(_ label: String) {
        var s = builtinQualityBuckets
        if s.contains(label) { s.remove(label) } else { s.insert(label) }
        viewModel.setBuiltinQualityFilter(buckets: s)
    }

    // File size — Min/Max in GB (converted to bytes in the criterion).
    private func builtinSizeControl() -> some View {
        HStack(spacing: 6) {
            TextField("Min", value: builtinSizeBinding(isMin: true), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .focused($focusedBuiltinFilterField, equals: .fileSize)
            Text("–").foregroundStyle(Color.appTextSecondary)
            TextField("Max", value: builtinSizeBinding(isMin: false), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            Text("GB").foregroundStyle(Color.appTextSecondary)
        }
        .font(.caption)
    }

    private func builtinSizeBinding(isMin: Bool) -> Binding<Double?> {
        Binding(
            get: {
                guard case .sizeRange(let min, let max) = viewModel.builtinFilters[.fileSize] else { return nil }
                return (isMin ? min : max).map { $0 / 1_000_000_000 }   // bytes -> GB
            },
            set: { newGB in
                guard case .sizeRange(let min, let max) = viewModel.builtinFilters[.fileSize] else { return }
                let newBytes = newGB.map { $0 * 1_000_000_000 }
                viewModel.setBuiltinSizeRangeFilter(
                    minBytes: isMin ? newBytes : min,
                    maxBytes: isMin ? max : newBytes
                )
            }
        )
    }

    // Plays — Unplayed / Played (single-select; tapping the active one clears it).
    private func builtinPlaysControl() -> some View {
        HStack(spacing: 6) {
            builtinPlaysChip("Unplayed", value: .unplayed)
            builtinPlaysChip("Played", value: .played)
        }
    }

    private func builtinPlaysChip(_ label: String, value: PlaysFilter) -> some View {
        let on = builtinPlaysValue == value
        return Button {
            viewModel.setBuiltinPlaysFilter(on ? nil : value)
        } label: {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Capsule().fill(on ? Color.appAccent.opacity(0.85) : Color.appSurface.opacity(0.6)))
                .foregroundStyle(on ? Color.white : Color.appTextSecondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var builtinPlaysValue: PlaysFilter? {
        if case .plays(let p) = viewModel.builtinFilters[.plays] { return p }
        return nil
    }

    // Codec / Extension / Folder — case-insensitive contains.
    private func builtinContainsControl(_ field: BuiltinFilterField) -> some View {
        let placeholder: String = {
            switch field {
            case .codec: return "h264, hevc…"
            case .fileExtension: return "mp4, mkv…"
            case .folder: return "Folder name"
            default: return "Contains…"
            }
        }()
        return TextField(placeholder, text: builtinContainsBinding(field))
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .focused($focusedBuiltinFilterField, equals: field)
    }

    private func builtinContainsBinding(_ field: BuiltinFilterField) -> Binding<String> {
        Binding(
            get: {
                if case .contains(let s) = viewModel.builtinFilters[field] { return s }
                return ""
            },
            set: { viewModel.setBuiltinContainsFilter(field: field, text: $0) }
        )
    }

    // Date added / created — quick presets + a From/To custom range.
    @ViewBuilder
    private func builtinDateControl(_ field: BuiltinFilterField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button("Any time") { viewModel.setBuiltinDateRangeFilter(field: field, min: nil, max: nil) }
                Button("Today") { setBuiltinDatePresetDays(field, 0) }
                Button("Last 7 days") { setBuiltinDatePresetDays(field, 7) }
                Button("Last 30 days") { setBuiltinDatePresetDays(field, 30) }
                Button("This year") { setBuiltinDateThisYear(field) }
            } label: {
                Label("Quick range", systemImage: "calendar")
                    .font(.caption2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.appAccent)

            builtinDateBoundRow(field: field, isMin: true, label: "From")
            builtinDateBoundRow(field: field, isMin: false, label: "To")
        }
    }

    @ViewBuilder
    private func builtinDateBoundRow(field: BuiltinFilterField, isMin: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 32, alignment: .leading)
            if builtinDateBound(field: field, isMin: isMin) != nil {
                DatePicker("", selection: builtinDateBinding(field: field, isMin: isMin), displayedComponents: [.date])
                    .labelsHidden()
                    .font(.caption)
                Button {
                    builtinSetDateBound(field: field, isMin: isMin, to: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appTextTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button("Set…") {
                    builtinSetDateBound(field: field, isMin: isMin, to: Date())
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
            }
        }
    }

    private func builtinDateBound(field: BuiltinFilterField, isMin: Bool) -> Date? {
        guard case .dateRange(let min, let max) = viewModel.builtinFilters[field] else { return nil }
        return isMin ? min : max
    }

    private func builtinSetDateBound(field: BuiltinFilterField, isMin: Bool, to newValue: Date?) {
        guard case .dateRange(let min, let max) = viewModel.builtinFilters[field] else { return }
        viewModel.setBuiltinDateRangeFilter(field: field, min: isMin ? newValue : min, max: isMin ? max : newValue)
    }

    private func builtinDateBinding(field: BuiltinFilterField, isMin: Bool) -> Binding<Date> {
        Binding(
            get: { builtinDateBound(field: field, isMin: isMin) ?? Date() },
            set: { builtinSetDateBound(field: field, isMin: isMin, to: $0) }
        )
    }

    /// `days == 0` means "today" (start of today → now). Sets only the lower bound (open-ended max).
    private func setBuiltinDatePresetDays(_ field: BuiltinFilterField, _ days: Int) {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        viewModel.setBuiltinDateRangeFilter(field: field, min: cal.startOfDay(for: base), max: nil)
    }

    private func setBuiltinDateThisYear(_ field: BuiltinFilterField) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year], from: Date()))
        viewModel.setBuiltinDateRangeFilter(field: field, min: start, max: nil)
    }

    @ViewBuilder
    private func tagFilterRow(_ tag: Tag) -> some View {
        let id = tag.id ?? -1
        let isActive = viewModel.selectedTagIds.contains(id)
        TagToggleChip(tag: tag, isActive: isActive, count: viewModel.tagCounts[id] ?? 0) { adding in
            if adding {
                viewModel.selectedTagIds.insert(id)
            } else {
                viewModel.selectedTagIds.remove(id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Rename Tag\u{2026}") { renameText = tag.name; tagPendingRename = tag }
            Divider()
            Button("Delete Tag", role: .destructive) { tagPendingDelete = tag }
        }
    }

    /// Natural drawer height = header + padded cards. Reported once both have measured (> 0) so
    /// the call site never caps against a transient half-measured value.
    private func reportNaturalHeight() {
        guard measuredHeaderHeight > 0, measuredCardsHeight > 0 else { return }
        onNaturalHeightChanged?(measuredHeaderHeight + measuredCardsHeight)
    }

    private func createNewTag() {
        let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newTagText = ""
        Task { await viewModel.createTag(name) }
    }

    // MARK: - Sections (kept for any internal reuse; content now lives in the cards above)

    private func durationPreset(_ label: String, min: Double?, max: Double?) -> some View {
        let isActive = (viewModel.minDurationSeconds == min) && (viewModel.maxDurationSeconds == max)
        // Restructured from the `Button(label) { action }` shorthand to an explicit label closure
        // so `.contentShape` can be applied directly to the label content — a `.plain` button's
        // hit-testing otherwise only covers the rendered text glyphs, not the padded capsule
        // around it, leaving a dead zone a user would expect to be clickable.
        return Button {
            viewModel.minDurationSeconds = min
            viewModel.maxDurationSeconds = max
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isActive ? Color.appAccent.opacity(0.18) : Color.appSurface.opacity(0.6))
                )
                .overlay(
                    Capsule().stroke(isActive ? Color.appAccent.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appAccent)
            .padding(.leading, 4)
    }

    /// Small "Clear filter" link for a card's header row, right-aligned next to its title.
    private func clearFilterAccessory(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Clear filter", systemImage: "xmark")
                .font(.caption2)
                .labelStyle(.titleAndIcon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appTextSecondary)
    }
}

private struct DrawerHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct DrawerCardsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
