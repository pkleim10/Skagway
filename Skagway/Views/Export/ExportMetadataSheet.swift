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
    /// Full field list order (checked and unchecked), sectioned Match keys → Importable → Export only.
    @State private var listOrder: [String] = []
    /// Currently checked field ids.
    @State private var includedIDs: Set<String> = []
    @State private var availableColumns: [MetadataExportColumn] = []

    private var isExporting: Bool { viewModel.metadataExportProgress != nil }

    private var columnsByID: [String: MetadataExportColumn] {
        Dictionary(uniqueKeysWithValues: availableColumns.map { ($0.id, $0) })
    }

    /// Checked fields in list order — section-then-checked order for the writers.
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

            Text("Check fields to include. Checked fields stay at the top of each section; drag to reorder within a section.")
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)

            List {
                ForEach(MetadataExportColumnKind.allCases, id: \.self) { kind in
                    let ids = sectionIDs(kind)
                    if !ids.isEmpty {
                        Section {
                            ForEach(ids, id: \.self) { id in
                                if let col = columnsByID[id] {
                                    Toggle(isOn: inclusionBinding(for: id)) {
                                        Text(col.label)
                                            .foregroundStyle(
                                                includedIDs.contains(id) ? Color.primary : Color.appTextSecondary
                                            )
                                    }
                                    .disabled(isExporting)
                                }
                            }
                            .onMove(perform: isExporting ? { _, _ in } : { from, to in
                                moveColumns(in: kind, from: from, to: to)
                            })
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                Text(kind.caption)
                                    .font(.caption)
                                    .foregroundStyle(Color.appTextSecondary)
                                    .textCase(nil)
                            }
                            .padding(.bottom, 2)
                        }
                    }
                }
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
        .frame(width: 520, height: 600)
        .onAppear {
            format = viewModel.loadMetadataExportFormat()
            availableColumns = MetadataExportColumnRegistry.allColumns(
                customFields: viewModel.customMetadataFieldDefinitions
            )
            listOrder = viewModel.loadMetadataExportColumnOrder()
            includedIDs = viewModel.loadMetadataExportIncludedColumnIDs()
            pinCheckedColumnsToTop()
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

    private func sectionIDs(_ kind: MetadataExportColumnKind) -> [String] {
        listOrder.filter { MetadataExportColumnRegistry.kind(forColumnID: $0) == kind }
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
                pinCheckedColumnsToTop()
            }
        )
    }

    private func moveColumns(in kind: MetadataExportColumnKind, from source: IndexSet, to destination: Int) {
        var section = sectionIDs(kind)
        section.move(fromOffsets: source, toOffset: destination)
        listOrder = MetadataExportColumnKind.allCases.flatMap { sectionKind in
            sectionKind == kind ? section : sectionIDs(sectionKind)
        }
        pinCheckedColumnsToTop()
    }

    /// Keep checked fields above unchecked within each kind section.
    private func pinCheckedColumnsToTop() {
        let pinned = MetadataExportColumnRegistry.pinCheckedWithinSections(
            order: listOrder,
            includedIDs: includedIDs
        )
        if pinned != listOrder {
            listOrder = pinned
        }
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
        return "Skagway-metadata-\(stamp)"
    }
}
