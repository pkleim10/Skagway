import SwiftUI
import AppKit

/// Sheet for pattern-based bulk file rename with preview.
struct BulkRenameSheet: View {
    @Bindable var viewModel: LibraryViewModel
    let scope: MetadataExportScope
    let videoCount: Int

    @Environment(\.dismiss) private var dismiss

    @State private var pattern: String = BulkRenameTokenCatalog.defaultPattern
    @State private var fieldSearch: String = ""
    @State private var tokens: [BulkRenameToken] = []
    @State private var planRows: [BulkRenamePlanRow] = []
    @State private var selectedPreviewIDs: Set<BulkRenamePlanRow.ID> = []
    @State private var previewDetailRow: BulkRenamePlanRow?
    @StateObject private var patternField = BulkRenamePatternFieldModel()

    private var isApplying: Bool { viewModel.bulkRenameProgress != nil }

    private var actionableCount: Int {
        planRows.filter(\.status.isActionable).count
    }

    private var skippedCount: Int {
        planRows.filter {
            if case .skipped = $0.status { return true }
            return false
        }.count
    }

    private var filteredTokens: [BulkRenameToken] {
        let q = fieldSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return tokens }
        return tokens.filter {
            $0.label.localizedCaseInsensitiveContains(q)
                || $0.insertText.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bulk Rename")
                .font(.title2.weight(.semibold))

            Text(scopeSummary)
                .foregroundStyle(Color.appTextSecondary)

            HStack(alignment: .top, spacing: 16) {
                fieldsPane
                    .frame(width: 260)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Name pattern")
                        .font(.headline)
                    BulkRenamePatternField(model: patternField, isEnabled: !isApplying)
                        .frame(height: 22)
                        .onChange(of: patternField.text) { _, newValue in
                            pattern = newValue
                            recomputePlan()
                        }

                    Text("Insert at the caret. Optional args: date format (`{Date Created MMM-yyyy}`), duration (`{Duration mmm}`), case (`{Title lower}` / `{Title U}` / `{Title N}`). Special: `{Inc 015}`, `{Conflict -1}`, `{Stem}`, `{Date …}`, `{UUID8}`.")
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    previewTable
                }
            }

            if let progress = viewModel.bulkRenameProgress {
                ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1))) {
                    Text(progress.statusText)
                }
            }

            footer
        }
        .padding(20)
        .frame(minWidth: 880, minHeight: 560)
        .onAppear {
            tokens = BulkRenameTokenCatalog.tokens(
                customFields: viewModel.customMetadataFieldDefinitions
            )
            let loaded = viewModel.loadBulkRenamePattern()
            pattern = loaded
            patternField.text = loaded
            patternField.noteSelection(NSRange(location: (loaded as NSString).length, length: 0))
            recomputePlan()
        }
    }

    private var scopeSummary: String {
        "\(videoCount) \(scope.summaryNoun) video\(videoCount == 1 ? "" : "s") · Preview before applying"
    }

    private var fieldsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fields")
                .font(.headline)
            TextField("Search fields…", text: $fieldSearch)
                .textFieldStyle(.roundedBorder)
                .disabled(isApplying)

            List {
                ForEach(BulkRenameTokenSection.allCases) { section in
                    let sectionTokens = filteredTokens.filter { $0.section == section }
                    if !sectionTokens.isEmpty {
                        Section(section.title) {
                            ForEach(sectionTokens) { token in
                                Button {
                                    insertToken(token)
                                } label: {
                                    HStack {
                                        Text(token.label)
                                            .foregroundStyle(Color.appTextPrimary)
                                        Spacer(minLength: 8)
                                        Text(token.insertText)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(Color.appTextSecondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(isApplying)
                            }
                        }
                    }
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
        }
    }

    private var previewTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.headline)

            Table(planRows, selection: $selectedPreviewIDs) {
                TableColumn("Current File Name") { row in
                    Text(row.currentFileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 140, ideal: 200)

                TableColumn("New File Name") { row in
                    Text(row.proposedFileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(row.status.isActionable ? Color.appTextPrimary : Color.appTextSecondary)
                }
                .width(min: 160, ideal: 240)

                TableColumn("Status") { row in
                    Text(row.status.label)
                        .foregroundStyle(statusColor(row.status))
                }
                .width(min: 90, ideal: 110)
            }
            .frame(minHeight: 280)
            .disabled(isApplying)
            .onChange(of: selectedPreviewIDs) { _, ids in
                guard let id = ids.first,
                      let row = planRows.first(where: { $0.id == id })
                else {
                    previewDetailRow = nil
                    return
                }
                previewDetailRow = row
            }
            .popover(item: $previewDetailRow, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) { row in
                BulkRenamePreviewDetailPopover(row: row) {
                    previewDetailRow = nil
                    selectedPreviewIDs = []
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(summaryText)
                .foregroundStyle(Color.appTextSecondary)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)

            Button(actionableCount == 1 ? "Rename 1 File" : "Rename \(actionableCount) Files") {
                Task { await apply() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isApplying || actionableCount == 0)
        }
    }

    private var summaryText: String {
        let unchanged = planRows.filter { $0.status == .unchanged }.count
        let warnings = planRows.filter(\.status.hasWarning).count
        var parts: [String] = []
        parts.append("\(actionableCount) will rename")
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        if skippedCount > 0 { parts.append("\(skippedCount) skipped") }
        if unchanged > 0 { parts.append("\(unchanged) unchanged") }
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ status: BulkRenameRowStatus) -> Color {
        switch status {
        case .willRename(let warning):
            return warning == nil ? Color.appAccent : .orange
        case .unchanged: return Color.appTextTertiary
        case .skipped: return .orange
        }
    }

    private func insertToken(_ token: BulkRenameToken) {
        patternField.insert(token.insertText)
        pattern = patternField.text
        recomputePlan()
    }

    private func recomputePlan() {
        let videos = viewModel.videosForMetadataExport(scope: scope)
        let context = viewModel.makeMetadataExportContext()
        planRows = BulkRenamePlanner.plan(
            videos: videos,
            pattern: pattern,
            context: context,
            tokens: tokens
        )
    }

    private func apply() async {
        viewModel.saveBulkRenamePattern(pattern)
        let targets = planRows.filter(\.status.isActionable)
        await viewModel.applyBulkRename(targets)
        dismiss()
    }
}

// MARK: - Preview row detail

private struct BulkRenamePreviewDetailPopover: View {
    let row: BulkRenamePlanRow
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Preview")
                .font(.headline)

            detailBlock(title: "Current File Name", value: row.currentFileName)

            detailBlock(
                title: "New File Name",
                value: row.proposedFileName,
                valueColor: row.status.isActionable ? Color.appTextPrimary : Color.appTextSecondary
            )

            HStack(spacing: 8) {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
                Text(row.status.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }

            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 640)
    }

    private var statusColor: Color {
        switch row.status {
        case .willRename(let warning):
            return warning == nil ? Color.appAccent : .orange
        case .unchanged: return Color.appTextTertiary
        case .skipped: return .orange
        }
    }

    private func detailBlock(title: String, value: String, valueColor: Color = Color.appTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pattern field (insert at caret)

/// Finds `{…}` token UTF-16 ranges in a bulk-rename pattern.
enum BulkRenamePatternSelection {
    private static let tokenRegex = try! NSRegularExpression(pattern: #"\{[^{}]+\}"#, options: [])

    /// Range of the `{token}` that contains `utf16Index`, if any.
    /// Index at the end of a token (right after `}`) is treated as outside.
    static func tokenRange(containing utf16Index: Int, in text: String) -> NSRange? {
        let ns = text as NSString
        guard utf16Index >= 0, utf16Index < ns.length else { return nil }
        let full = NSRange(location: 0, length: ns.length)
        var found: NSRange?
        tokenRegex.enumerateMatches(in: text, options: [], range: full) { match, _, stop in
            guard let match else { return }
            let r = match.range
            if utf16Index >= r.location, utf16Index < r.location + r.length {
                found = r
                stop.pointee = true
            }
        }
        return found
    }
}

@MainActor
final class BulkRenamePatternFieldModel: ObservableObject {
    @Published var text: String = BulkRenameTokenCatalog.defaultPattern

    /// Last known selection in UTF-16 units (NSString / NSTextField).
    private(set) var selectedRange: NSRange = NSRange(location: 0, length: 0)
    /// When set, overrides AppKit’s select-all-on-focus until applied.
    private(set) var pendingSelection: NSRange?
    weak var textField: NSTextField?

    func noteSelection(_ range: NSRange) {
        // Ignore select-all while we are forcing an insert highlight.
        if let pending = pendingSelection,
           let field = textField,
           range.length == (field.stringValue as NSString).length,
           range.length > pending.length
        {
            applyPendingSelection()
            return
        }
        selectedRange = range
    }

    func insert(_ snippet: String) {
        let ns = text as NSString
        var range = selectedRange
        if range.location == NSNotFound || range.location > ns.length {
            range = NSRange(location: ns.length, length: 0)
        }
        if range.location + range.length > ns.length {
            range = NSRange(location: ns.length, length: 0)
        }

        let updated = ns.replacingCharacters(in: range, with: snippet)
        let insertLength = (snippet as NSString).length
        let highlight = NSRange(location: range.location, length: insertLength)

        pendingSelection = highlight
        selectedRange = highlight
        text = updated

        if let field = textField as? BulkRenamePatternNSTextField {
            field.stringValue = updated
            field.pendingSelection = highlight
            field.window?.makeFirstResponder(field)
            applyPendingSelection()
            // AppKit often select-alls after becomeFirstResponder; re-apply on the next turn.
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingSelection()
                self?.clearPendingSelectionSoon()
            }
        }
    }

    func applyPendingSelection() {
        guard let pending = pendingSelection, let field = textField else { return }
        let len = (field.stringValue as NSString).length
        guard pending.location + pending.length <= len else { return }
        selectedRange = pending
        if let field = field as? BulkRenamePatternNSTextField {
            field.pendingSelection = pending
        }
        if let editor = field.currentEditor() {
            editor.selectedRange = pending
        }
    }

    private func clearPendingSelectionSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Keep pending through one more cycle of focus/select-all, then release.
            self.applyPendingSelection()
            (self.textField as? BulkRenamePatternNSTextField)?.pendingSelection = nil
            self.pendingSelection = nil
        }
    }
}

private final class BulkRenamePatternNSTextField: NSTextField {
    var onSelectionChange: ((NSRange) -> Void)?
    /// Preferred selection after becoming first responder (insert highlight).
    var pendingSelection: NSRange?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let pending = pendingSelection, let editor = currentEditor() {
            let len = (stringValue as NSString).length
            if pending.location + pending.length <= len {
                editor.selectedRange = pending
            }
        }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        pendingSelection = nil
        let previousSelection = (currentEditor() as? NSText)?.selectedRange
        super.mouseDown(with: event)
        guard let editor = currentEditor() as? NSTextView else { return }

        // Dragging / multi-character selection: leave alone.
        guard editor.selectedRange.length == 0 else {
            onSelectionChange?(editor.selectedRange)
            return
        }

        let clickIndex = editor.selectedRange.location
        guard let tokenRange = BulkRenamePatternSelection.tokenRange(
            containing: clickIndex,
            in: stringValue
        ) else {
            onSelectionChange?(editor.selectedRange)
            return
        }

        // Second click on an already-selected token: keep caret for in-token editing.
        if let previousSelection, NSEqualRanges(previousSelection, tokenRange) {
            onSelectionChange?(editor.selectedRange)
            return
        }

        editor.selectedRange = tokenRange
        onSelectionChange?(tokenRange)
    }
}

private struct BulkRenamePatternField: NSViewRepresentable {
    @ObservedObject var model: BulkRenamePatternFieldModel
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> BulkRenamePatternNSTextField {
        let field = BulkRenamePatternNSTextField(string: model.text)
        field.delegate = context.coordinator
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.focusRingType = .default
        field.onSelectionChange = { [weak model] range in
            model?.noteSelection(range)
        }
        model.textField = field
        context.coordinator.observeFieldEditor(for: field)
        return field
    }

    func updateNSView(_ field: BulkRenamePatternNSTextField, context: Context) {
        model.textField = field
        field.isEnabled = isEnabled
        field.onSelectionChange = { [weak model] range in
            model?.noteSelection(range)
        }
        if let pending = model.pendingSelection {
            field.pendingSelection = pending
        }
        if field.stringValue != model.text {
            field.stringValue = model.text
        }
        // Always re-assert pending/insert selection after SwiftUI updates.
        if model.pendingSelection != nil {
            model.applyPendingSelection()
        } else if let editor = field.currentEditor() {
            let saved = model.selectedRange
            if saved.location != NSNotFound,
               saved.location + saved.length <= (model.text as NSString).length
            {
                editor.selectedRange = saved
            }
        }
        context.coordinator.observeFieldEditor(for: field)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: BulkRenamePatternFieldModel
        private var selectionObservation: NSObjectProtocol?

        init(model: BulkRenamePatternFieldModel) {
            self.model = model
        }

        func observeFieldEditor(for field: NSTextField) {
            selectionObservation.map { NotificationCenter.default.removeObserver($0) }
            selectionObservation = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { [weak self, weak field] note in
                guard let self, let field,
                      let editor = note.object as? NSTextView,
                      field.currentEditor() === editor
                else { return }
                self.model.noteSelection(editor.selectedRange)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            model.text = field.stringValue
            if let editor = field.currentEditor() {
                model.noteSelection(editor.selectedRange)
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if let editor = field.currentEditor() {
                model.noteSelection(editor.selectedRange)
            } else {
                let len = (field.stringValue as NSString).length
                if model.selectedRange.location > len {
                    model.noteSelection(NSRange(location: len, length: 0))
                }
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if model.pendingSelection != nil {
                model.applyPendingSelection()
                return
            }
            if let editor = field.currentEditor() {
                model.noteSelection(editor.selectedRange)
            }
        }
    }
}
