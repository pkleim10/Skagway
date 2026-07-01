import AVFoundation
import AVKit
import SwiftUI
import AppKit

/// Dedicated (trimmed for speed-to-visible) Inspector for the Curated Wall variant.
/// We are delivering the left Wall (easiest high-fidelity piece) first per "the easiest one".
/// Still a purpose-built surface: medium hero, title+actions, facts, rating, tall notes, footer.
/// Matches the refined mock visual hierarchy as closely as we can while staying compilable.
struct CuratedWallInspector: View {
    let video: Video?
    @Bindable var viewModel: LibraryViewModel
    let thumbnailService: ThumbnailService

    private var selectedIds: Set<String> { viewModel.selectedVideoIds }

    @State private var hero: NSImage?
    @State private var filmstrip: NSImage?
    @State private var customFieldValues: [UUID: String] = [:]
    @State private var customFieldMixed: Set<UUID> = []
    @FocusState private var focusedCustomFieldId: UUID?


    var body: some View {
        GeometryReader { geo in
            let heroH = max(140, min(geo.size.height * 0.40, 260))

            VStack(spacing: 0) {
                if let v = video {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            // Medium hero (the visual weight from the mock)
                            heroView(for: v, height: heroH)

                            // Title + icon actions
                            titleAndActions(for: v)

                            // Compact facts
                            factsRow(for: v)

                            // Rating (accented treatment)
                            ratingBlock(for: selectedIds)

                            // Tags (restored)
                            tagsBlock()

                            // Custom metadata fields (if any defined)
                            if !viewModel.customMetadataFieldDefinitions.isEmpty {
                                customMetadataBlock()
                            }

                        }
                        .padding(14)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Solid inspector background (exact RGB) instead of the translucent panel material.
            .background(Self.inspectorBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .stroke(Color.appAccent.opacity(0.10), lineWidth: 1)
            )
        }
        .frame(minWidth: 300)
        .onAppear { loadCustomFieldValues() }
        .onChange(of: video?.filePath) { _, _ in
            // Selection changed: stop any in-progress playback and refresh hero assets.
            if viewModel.isPlayingInline { viewModel.isPlayingInline = false }
            loadCustomFieldValues()
            hero = nil
            filmstrip = nil
            // The unassigned-tags "blind" is transient — collapse it on each new selection.
            showUnassigned = false
            newTagText = ""
        }
        .onChange(of: viewModel.selectedVideoIds) { _, _ in loadCustomFieldValues() }
        .onChange(of: focusedCustomFieldId) { old, _ in
            guard let fieldId = old, let value = customFieldValues[fieldId] else { return }
            Task { await viewModel.persistCustomMetadata(fieldId: fieldId, value: value, forVideoPaths: selectedIds) }
        }
        .onChange(of: viewModel.showThumbnailInDetail) { _, _ in
            filmstrip = nil
            Task { await loadHero() }
        }
        .task(id: video?.filePath) {
            await loadHero()
        }
    }

    // MARK: - Hero

    private func heroView(for v: Video, height: CGFloat) -> some View {
        // The hero is always the still/filmstrip preview now; playback renders in the floating
        // player panel that overlays this area while playing.
        let isPlaying = viewModel.isPlayingInline

        // Core media view with consistent sizing and clipping.
        let media: some View = Group {
            if viewModel.showThumbnailInDetail {
                if let img = hero {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(Color.appSurface)
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundStyle(Color.appTextTertiary.opacity(0.4))
                        }
                }
            } else if let fs = filmstrip {
                Image(nsImage: fs)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .local) { location in
                                    filmstripSeekAndPlay(at: location, size: geo.size, video: v)
                                }
                        }
                    }
            } else {
                Rectangle()
                    .fill(Color.appSurface)
                    .overlay {
                        Image(systemName: "filmstrip")
                            .font(.largeTitle)
                            .foregroundStyle(Color.appTextTertiary.opacity(0.4))
                    }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.appDivider.opacity(0.3), lineWidth: 1)
        )
        .onTapGesture {
            // Start in whatever mode the setting indicates (don't force detail-pane).
            if !viewModel.isPlayingInline {
                viewModel.pendingFilmstripSeekSeconds = nil
                viewModel.isPlayingInline = true
            }
        }

        // Attach controls to the media first (so they hug the image corners),
        // then center the whole decorated media horizontally in the inspector.
        let decorated = media
            .overlay(alignment: .topTrailing) {
                if !isPlaying {
                    HStack(spacing: 2) {
                        Button { viewModel.showThumbnailInDetail = true } label: {
                            Text("Still").font(.caption2)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(viewModel.showThumbnailInDetail ? Color.appAccent.opacity(0.28) : .clear)
                        .clipShape(Capsule())
                        Button { viewModel.showThumbnailInDetail = false } label: {
                            Text("Filmstrip").font(.caption2)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(!viewModel.showThumbnailInDetail ? Color.appAccent.opacity(0.28) : .clear)
                        .clipShape(Capsule())
                    }
                    .padding(3)
                    .background(Material.ultraThinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isPlaying, let d = v.formattedDuration {
                    Text(d)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(6)
                }
            }

        // Center the (decorated) media in the inspector width.
        return decorated
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func filmstripSeekAndPlay(at location: CGPoint, size: CGSize, video: Video) {
        // Seek to the clicked time and play in whatever mode the setting indicates (the host that
        // mounts for that mode consumes `pendingFilmstripSeekSeconds`).
        let w = max(1.0, size.width)
        let progress = max(0.0, min(1.0, location.x / w))
        let dur = video.duration ?? 0.0
        viewModel.pendingFilmstripSeekSeconds = progress * dur
        viewModel.isPlayingInline = true
    }

    private func loadHero() async {
        guard let v = video else { return }
        if let lo = thumbnailService.loadThumbnail(for: v.filePath) {
            await MainActor.run { hero = lo }
        }
        if viewModel.showThumbnailInDetail {
            if let hi = await thumbnailService.detailPreviewImage(for: v, longEdge: 720) {
                await MainActor.run { hero = hi }
            }
        } else {
            if let img = thumbnailService.loadFilmstrip(for: v.filePath) {
                await MainActor.run { filmstrip = img }
            } else if let img = try? await thumbnailService.generateFilmstrip(for: v) {
                await MainActor.run { filmstrip = img }
            }
        }
    }

    // MARK: - Title + icon actions

    private func titleAndActions(for v: Video) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if selectedIds.count > 1 {
                Text("\(selectedIds.count) Videos Selected")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)
            } else {
                Text(v.fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(2)

                // File path (folder icon + path) — click to reveal in Finder.
                Button {
                    NSWorkspace.shared.selectFile(v.filePath, inFileViewerRootedAtPath: "")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(v.filePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")

                HStack(spacing: 14) {
                    Button { viewModel.isPlayingInline = true } label: {
                        Label("Play", systemImage: "play.fill")
                    }.buttonStyle(.plain).foregroundStyle(Color.appAccent)

                    Spacer()
                }
                .font(.callout)
            }
        }
    }

    // MARK: - Compact facts (bordered 3-column table, per the mock)

    static let inspectorBackground = Color(red: 10 / 255, green: 21 / 255, blue: 35 / 255)
    private static let factCellBackground = Color(red: 16 / 255, green: 30 / 255, blue: 45 / 255)
    private static let factLineColor = Color(red: 25 / 255, green: 36 / 255, blue: 50 / 255)
    // Shared inset field chrome (New Tag + Notes): #15212E fill with a recessed "3D" bezel.
    private static let fieldBackground = Color(red: 21 / 255, green: 33 / 255, blue: 46 / 255)

    private func insetFieldBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(Self.fieldBackground)
            // Top-down inner shadow → recessed look.
            .overlay(
                shape
                    .stroke(Color.black.opacity(0.55), lineWidth: 2)
                    .blur(radius: 2)
                    .mask(shape.fill(LinearGradient(colors: [.black, .clear],
                                                    startPoint: .top, endPoint: .bottom)))
            )
            // Faint upper light edge to complete the bezel.
            .overlay(shape.stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    // MARK: - Common-fact helpers (multi-select)

    private func commonString(_ values: [String?]) -> String {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return "—" }
        return first ?? "—"
    }

    private func commonResFps(in videos: [Video]) -> String {
        guard videos.count > 1 else {
            let v = videos[0]
            let res = v.resolutionLabel ?? v.resolution ?? "—"
            if let fr = v.frameRate, fr > 0 { return "\(res) \(Int(fr.rounded()))fps" }
            return res
        }
        let resVals = videos.map { $0.resolutionLabel ?? $0.resolution }
        guard let first = resVals.first, resVals.allSatisfy({ $0 == first }), let res = first else { return "—" }
        let fpsVals = videos.map(\.frameRate)
        if let fps = fpsVals[0], fps > 0, fpsVals.allSatisfy({ $0 == fps }) {
            return "\(res) \(Int(fps.rounded()))fps"
        }
        return res
    }

    private func commonDate(_ values: [Date]) -> String {
        let days = values.map { Calendar.current.startOfDay(for: $0) }
        guard let first = days.first, days.allSatisfy({ $0 == first }) else { return "—" }
        return first.formatted(date: .numeric, time: .omitted)
    }

    private func factsRow(for v: Video) -> some View {
        let videos: [Video] = selectedIds.count > 1
            ? viewModel.filteredVideos.filter { selectedIds.contains($0.id) }
            : [v]
        let multi = videos.count > 1

        let resFps    = commonResFps(in: videos)
        let duration  = commonString(videos.map(\.formattedDuration))
        let fileSize  = multi ? "—" : v.formattedFileSize
        let codec     = commonString(videos.map(\.codec))
        let dateStr   = commonDate(videos.map(\.dateAdded))
        let plays     = multi ? "—" : (v.playCount == 1 ? "1 play" : "\(v.playCount) plays")
        let subtitles = videos.map(\.hasSubtitles)
        let subLabel  = (subtitles.allSatisfy { $0 == subtitles[0] })
            ? "Subtitle: \(subtitles[0] ? "Yes" : "No")"
            : "Subtitle: —"

        return VStack(spacing: 0) {
            factGridRow([resFps, duration, fileSize])
            hLine()
            factGridRow([codec, dateStr, plays])
            hLine()
            factCell(subLabel)
        }
        .background(Self.factCellBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Self.factLineColor, lineWidth: 1)
        )
    }

    private func factGridRow(_ values: [String]) -> some View {
        HStack(spacing: 0) {
            factCell(values[0])
            vLine()
            factCell(values[1])
            vLine()
            factCell(values[2])
        }
    }

    private func factCell(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.appTextSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }

    private func vLine() -> some View { Rectangle().fill(Self.factLineColor).frame(width: 1) }
    private func hLine() -> some View { Rectangle().fill(Self.factLineColor).frame(height: 1) }

    // MARK: - Rating

    private func ratingBlock(for ids: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Rectangle().fill(Color.appAccent).frame(width: 3, height: 12).cornerRadius(2)
                Text("RATING").font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Color.appAccent)
            }
            RatingView(rating: currentRating(for: ids), size: 18) { r in
                viewModel.applyRating(to: ids, rating: r)
                Task { await viewModel.persistRating(for: ids, rating: r) }
            }
        }
    }

    private func currentRating(for ids: Set<String>) -> Int {
        let vals = viewModel.filteredVideos.filter { ids.contains($0.id) }.map(\.rating)
        if let first = vals.first, vals.allSatisfy({ $0 == first }) { return first }
        return video?.rating ?? 0
    }

    // MARK: - Custom Metadata

    private func loadCustomFieldValues() {
        let defs = viewModel.customMetadataFieldDefinitions
        customFieldMixed = []
        customFieldValues = [:]
        guard !defs.isEmpty else { return }

        if selectedIds.count == 1, let dbId = video?.databaseId {
            for field in defs {
                customFieldValues[field.id] = viewModel.listCustomMetadataByVideoId[dbId]?[field.id] ?? ""
            }
        } else if selectedIds.count > 1 {
            let sel = viewModel.filteredVideos.filter { selectedIds.contains($0.id) }
            for field in defs {
                let vals = sel.map { v -> String? in
                    guard let id = v.databaseId else { return nil }
                    return viewModel.listCustomMetadataByVideoId[id]?[field.id]
                }
                if let first = vals.first, vals.allSatisfy({ $0 == first }) {
                    customFieldValues[field.id] = first ?? ""
                } else {
                    customFieldMixed.insert(field.id)
                    customFieldValues[field.id] = ""
                }
            }
        }
    }

    private func customMetadataBlock() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Rectangle().fill(Color.appAccent).frame(width: 3, height: 12).cornerRadius(2)
                Text("CUSTOM").font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Color.appAccent)
            }
            ForEach(viewModel.customMetadataFieldDefinitions) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.name)
                        .font(.caption2)
                        .foregroundStyle(Color.appTextTertiary)
                    customFieldEditor(for: field)
                }
            }
        }
    }

    @ViewBuilder
    private func customFieldEditor(for field: CustomMetadataFieldDefinition) -> some View {
        let isMixed = customFieldMixed.contains(field.id)
        let binding = Binding<String>(
            get: { customFieldValues[field.id] ?? "" },
            set: { customFieldValues[field.id] = $0; customFieldMixed.remove(field.id) }
        )
        let placeholder = isMixed ? "Multiple values" : field.name

        switch field.valueType {
        case .string, .number:
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(insetFieldBackground(cornerRadius: 6))
                .focused($focusedCustomFieldId, equals: field.id)
        case .text:
            TabbableTextEditor(text: binding) {
                // Advance to next custom field, or clear focus if last.
                let defs = viewModel.customMetadataFieldDefinitions
                if let idx = defs.firstIndex(where: { $0.id == field.id }), idx + 1 < defs.count {
                    focusedCustomFieldId = defs[idx + 1].id
                } else {
                    focusedCustomFieldId = nil
                }
            }
            .frame(minHeight: 56)
            .padding(6)
            .background(insetFieldBackground(cornerRadius: 8))
            .focused($focusedCustomFieldId, equals: field.id)
        case .date, .dateTime:
            let fmt = ISO8601DateFormatter()
            let dateBinding = Binding<Date>(
                get: { fmt.date(from: customFieldValues[field.id] ?? "") ?? Date() },
                set: { newDate in
                    let s = fmt.string(from: newDate)
                    customFieldValues[field.id] = s
                    customFieldMixed.remove(field.id)
                    Task { await viewModel.persistCustomMetadata(fieldId: field.id, value: s, forVideoPaths: selectedIds) }
                }
            )
            DatePicker("", selection: dateBinding,
                       displayedComponents: field.valueType == .dateTime ? [.date, .hourAndMinute] : .date)
                .datePickerStyle(.compact)
                .labelsHidden()
        }
    }

    // MARK: - Tags — two lists: assigned, plus (behind a "blind") the unassigned tags.
    private func tagsBlock() -> some View {
        let all = viewModel.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let assigned = all.filter { isTagAppliedToSelection($0) }
        let unassigned = all.filter { !isTagAppliedToSelection($0) }

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Rectangle().fill(Color.appAccent).frame(width: 3, height: 12).cornerRadius(2)
                Text("TAGS").font(.caption.weight(.semibold)).tracking(0.5).foregroundStyle(Color.appAccent)
                Spacer()
            }

            // List 1 — tags on this video; tap a chip to unassign it. Packed flow (not a grid).
            if assigned.isEmpty {
                Text("Select a tag from the list below to assign it to this video")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary)
            } else {
                FlowLayout(spacing: 4) {
                    ForEach(assigned) { tag in
                        InspectorTagChip(tag: tag, applied: true, fillWidth: false) {
                            Task { await viewModel.removeTag(tag, fromVideos: selectedIds) }
                        }
                    }
                }
            }

            // The "blind" that reveals the unassigned list.
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showUnassigned.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showUnassigned ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Add tags (\(unassigned.count))").font(.caption2.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            if showUnassigned {
                // New tag — creates it and assigns it to the current selection.
                HStack(spacing: 4) {
                    TextField("New tag", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(insetFieldBackground(cornerRadius: 6))
                        .onSubmit { createAndApplyNewTag() }
                    Button { createAndApplyNewTag() } label: { Image(systemName: "plus.circle") }
                        .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.plain)
                }

                // List 2 — unassigned tags; tap to assign, right-click to rename/delete.
                if unassigned.isEmpty {
                    Text("Every tag is already assigned to this video.")
                        .font(.caption2)
                        .foregroundStyle(Color.appTextTertiary)
                } else {
                    tagChipGrid(unassigned, applied: false, withMenu: true)
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

    /// A flexible grid of tag chips. `applied` sets the tap action (unassign vs assign) and styling;
    /// `withMenu` adds the rename/delete context menu (used on the unassigned list only).
    private func tagChipGrid(_ tags: [Tag], applied: Bool, withMenu: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(tags) { tag in
                let chip = InspectorTagChip(tag: tag, applied: applied) {
                    Task {
                        if applied {
                            await viewModel.removeTag(tag, fromVideos: selectedIds)
                        } else {
                            await viewModel.addTag(tag.name, toVideos: selectedIds)
                        }
                    }
                }
                if withMenu {
                    chip.contextMenu {
                        Button("Rename\u{2026}") { renameText = tag.name; tagPendingRename = tag }
                        Divider()
                        Button("Delete Tag", role: .destructive) { tagPendingDelete = tag }
                    }
                } else {
                    chip
                }
            }
        }
    }

    @State private var newTagText: String = ""
    @State private var showUnassigned = false
    @State private var tagPendingDelete: Tag?
    @State private var tagPendingRename: Tag?
    @State private var renameText: String = ""

    private func isTagAppliedToSelection(_ tag: Tag) -> Bool {
        let applied = viewModel.tagsForVideos(selectedIds)
        return applied.contains { $0.id == tag.id }
    }

    private func createAndApplyNewTag() {
        let name = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await viewModel.createTag(name)
            await viewModel.addTag(name, toVideos: selectedIds)
            newTagText = ""
        }
    }

    // MARK: - Footer

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(Color.appTextTertiary)
            Text("Select a video on the wall")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A tag chip in the inspector's Tags section. Preserves the existing capsule appearance and,
/// like the filters-drawer chip, reveals the full tag name in a small popover on hover — but
/// only when the name is actually truncated, so it never just duplicates a name that fits.
private struct InspectorTagChip: View {
    let tag: Tag
    let applied: Bool
    /// Fill the container width (grid cells) vs. hug the content (packed flow layout).
    var fillWidth: Bool = true
    let onToggle: () -> Void

    @State private var isHovering = false
    @State private var visibleTextWidth: CGFloat = 0
    @State private var fullTextWidth: CGFloat = 0

    private var isTruncated: Bool {
        fullTextWidth > visibleTextWidth + 1
    }

    var body: some View {
        Button(action: onToggle) {
            Text(tag.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                // Measure rendered width vs. the full intrinsic width to detect truncation.
                .background(widthReader($visibleTextWidth))
                .background(
                    Text(tag.name)
                        .font(.caption)
                        .fixedSize()
                        .hidden()
                        .background(widthReader($fullTextWidth))
                )
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(applied ? Color.appAccent.opacity(0.18) : Color.appSurface.opacity(0.65))
                .overlay(
                    Capsule().stroke(applied ? Color.appAccent.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(
            isPresented: Binding(
                get: { isHovering && isTruncated },
                set: { newValue in if !newValue { isHovering = false } }
            ),
            arrowEdge: .top
        ) {
            Text(tag.name)
                .font(.caption)
                .foregroundStyle(Color.appTextPrimary)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
    }

    /// Reports the rendered width of the view it backs into `width` (kept current on resize).
    private func widthReader(_ width: Binding<CGFloat>) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width.wrappedValue = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newValue in
                    width.wrappedValue = newValue
                }
        }
    }
}

/// NSTextView wrapper that intercepts Tab to advance focus instead of inserting a tab character.
private struct TabbableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 11
    var onTab: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onTab: onTab) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.font = .systemFont(ofSize: fontSize)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let tv = scrollView.documentView as! NSTextView
        context.coordinator.onTab = onTab
        if tv.string != text { tv.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onTab: () -> Void

        init(text: Binding<String>, onTab: @escaping () -> Void) {
            _text = text
            self.onTab = onTab
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                onTab()
                return true
            }
            return false
        }
    }
}
