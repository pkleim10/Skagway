import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Sheet for choosing export format and columns. Scope is fixed by the entry point.
struct ExportMetadataSheet: View {
    @Bindable var viewModel: LibraryViewModel
    let scope: MetadataExportScope
    let videoCount: Int

    @Environment(\.dismiss) private var dismiss

    @State private var format: MetadataExportFormat = .csv
    /// Full field list order (checked and unchecked).
    @State private var listOrder: [String] = []
    /// Currently checked field ids.
    @State private var includedIDs: Set<String> = []
    @State private var availableColumns: [MetadataExportColumn] = []

    private var isExporting: Bool { viewModel.metadataExportProgress != nil }

    /// Checked fields in list order — what actually gets written.
    private var exportColumnIDs: [String] {
        listOrder.filter { includedIDs.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Metadata")
                .font(.title2.weight(.semibold))

            Text(scopeSummary)
                .foregroundStyle(Color.appTextSecondary)

            Picker("Format", selection: $format) {
                ForEach(MetadataExportFormat.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isExporting)

            Text("Fields")
                .font(.headline)

            Text("Check fields to include. Drag to reorder. Optional fields start unchecked at the bottom.")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)

            List {
                ForEach(listOrder, id: \.self) { id in
                    if let col = availableColumns.first(where: { $0.id == id }) {
                        Toggle(isOn: inclusionBinding(for: id)) {
                            Text(col.label)
                                .foregroundStyle(includedIDs.contains(id) ? Color.primary : Color.appTextSecondary)
                        }
                        .disabled(isExporting)
                    }
                }
                .onMove(perform: isExporting ? { _, _ in } : moveColumns)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 320)

            if let progress = viewModel.metadataExportProgress {
                ProgressView(value: Double(progress.current), total: Double(max(progress.total, 1))) {
                    Text("Exporting \(progress.current) of \(progress.total)…")
                }
            }

            if let error = viewModel.metadataExportErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    if isExporting {
                        viewModel.cancelMetadataExport()
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Button("Export…") {
                    beginExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting || exportColumnIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480, height: 560)
        .onAppear {
            format = viewModel.loadMetadataExportFormat()
            availableColumns = MetadataExportColumnRegistry.allColumns(
                customFields: viewModel.customMetadataFieldDefinitions
            )
            listOrder = viewModel.loadMetadataExportColumnOrder()
            includedIDs = viewModel.loadMetadataExportIncludedColumnIDs()
        }
        .onDisappear {
            viewModel.cancelMetadataExport()
            viewModel.metadataExportErrorMessage = nil
        }
    }

    private var scopeSummary: String {
        let noun = scope.summaryNoun
        let unit = videoCount == 1 ? "video" : "videos"
        return "Exporting \(videoCount) \(noun) \(unit)"
    }

    private func inclusionBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { includedIDs.contains(id) },
            set: { included in
                if included {
                    includedIDs.insert(id)
                } else {
                    includedIDs.remove(id)
                }
            }
        )
    }

    private func moveColumns(from source: IndexSet, to destination: Int) {
        listOrder.move(fromOffsets: source, toOffset: destination)
    }

    private func beginExport() {
        viewModel.saveMetadataExportFormat(format)
        viewModel.saveMetadataExportColumnOrder(listOrder)
        viewModel.saveMetadataExportIncludedColumnIDs(includedIDs)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFileName()
        switch format {
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
        case .jsonl:
            if let jsonl = UTType(filenameExtension: "jsonl") {
                panel.allowedContentTypes = [jsonl]
            } else {
                panel.allowedContentTypes = [.json]
            }
        }
        panel.begin { response in
            guard response == .OK, var url = panel.url else { return }
            // Ensure correct extension if the user cleared it.
            if url.pathExtension.lowercased() != format.fileExtension {
                url = url.deletingPathExtension().appendingPathExtension(format.fileExtension)
            }
            viewModel.runMetadataExport(
                scope: scope,
                format: format,
                orderedColumnIDs: exportColumnIDs,
                destinationURL: url
            )
        }
    }

    /// Basename only — `NSSavePanel` appends the extension from `allowedContentTypes`,
    /// so including `.jsonl` / `.csv` here would produce `….jsonl.jsonl`.
    private func defaultFileName() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return "VideoMaster-metadata-\(stamp)"
    }
}
