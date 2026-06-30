import SwiftUI

/// Elegant top-descending filters drawer for the Curated Wall variant.
/// Always presented above the wall content when open. Changes are live (no Apply).
/// Styled to feel part of the cinematic gallery experience (blue accents, refined materials, generous breathing).
struct CuratedWallFiltersDrawer: View {
    @Bindable var viewModel: LibraryViewModel

    @State private var tagSearch: String = ""
    @State private var hoverRating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

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
                }
            }
            // Height is controlled by the presentation site (Animated well in ContentView)
            // so the drawer can participate in smooth height transitions. Capped at call site.
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
    }

    // MARK: - Responsive column packing

    // The four filter units in reading order. Rating + Duration are grouped so they always
    // travel together. The natural (max) width of each is used to decide how many columns fit.
    private let unitWidths: [CGFloat] = [260, 240, 320, 360]

    @ViewBuilder
    private func unitView(_ index: Int) -> some View {
        switch index {
        case 0: smartLibrariesCard
        case 1: collectionsCard
        case 2: ratingDurationColumn
        default: tagsCard
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
    private func makeFilterCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(title)
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
        }
        .buttonStyle(.plain)
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
                    libraryRow("Missing", icon: "questionmark.circle", count: viewModel.libraryCounts.missing, filter: .missing)
                }
                if viewModel.showRecentlyConverted {
                    libraryRow("Recently Converted", icon: "arrow.triangle.2.circlepath", count: viewModel.libraryCounts.recentlyConverted, filter: .recentlyConverted)
                }
            }
        }
    }

    private var collectionsCard: some View {
        makeFilterCard(title: "COLLECTIONS") {
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.collections.isEmpty {
                    Text("No collections yet")
                        .font(.caption)
                        .foregroundStyle(Color.appTextTertiary)
                } else {
                    let maxShow = 6
                    let shown = Array(viewModel.collections.prefix(maxShow))
                    ForEach(shown, id: \.listId) { collection in
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
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Quick clear for the collection filter (kept local to the card for convenience)
                Button {
                    if case .collection = viewModel.sidebarFilter {
                        viewModel.sidebarFilter = .all
                    }
                } label: {
                    Label("Clear collection filter", systemImage: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appTextSecondary)
                .padding(.top, 2)
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
        makeFilterCard(title: "TAGS") {
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
                            let id = tag.id ?? -1
                            let isActive = viewModel.selectedTagIds.contains(id)
                            TagToggleChip(tag: tag, isActive: isActive) { adding in
                                if adding {
                                    viewModel.selectedTagIds.insert(id)
                                } else {
                                    viewModel.selectedTagIds.remove(id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections (kept for any internal reuse; content now lives in the cards above)

    private func durationPreset(_ label: String, min: Double?, max: Double?) -> some View {
        let isActive = (viewModel.minDurationSeconds == min) && (viewModel.maxDurationSeconds == max)
        return Button(label) {
            viewModel.minDurationSeconds = min
            viewModel.maxDurationSeconds = max
        }
        .font(.caption)
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(isActive ? Color.appAccent.opacity(0.18) : Color.appSurface.opacity(0.6))
        )
        .overlay(
            Capsule().stroke(isActive ? Color.appAccent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appAccent)
            .padding(.leading, 4)
    }
}
