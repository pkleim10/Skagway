import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Summary after Import Metadata Pass 1. Optional Pass 2 for unmatched review.
struct ApplyMetadataSummarySheet: View {
    @Bindable var viewModel: LibraryViewModel
    let summary: LibraryViewModel.MetadataApplySummary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Metadata")
                .font(.title2.weight(.semibold))

            Text(summary.sourceURL.lastPathComponent)
                .foregroundStyle(Color.appTextSecondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                statRow("Matched", "\(summary.matchedCount)")
                statRow("Updated", "\(summary.updatedVideoCount)")
                statRow("Unmatched", "\(summary.unmatchedCount)")
            }

            if !summary.skippedUnknownColumns.isEmpty {
                Text("Skipped unknown columns: \(summary.skippedUnknownColumns.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            if !summary.ignoredReadOnlyColumns.isEmpty {
                Text("Ignored read-only columns: \(summary.ignoredReadOnlyColumns.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color.appTextSecondary)
            }
            if !summary.rowErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Row issues")
                        .font(.headline)
                    ForEach(summary.rowErrors.prefix(8), id: \.self) { err in
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if summary.rowErrors.count > 8 {
                        Text("…and \(summary.rowErrors.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(Color.appTextSecondary)
                    }
                }
            }

            if let unmatched = viewModel.metadataApplyUnmatchedRows {
                Divider()
                Text("Unmatched rows (\(unmatched.count))")
                    .font(.headline)
                List(unmatched) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Line \(row.lineNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.appTextSecondary)
                        Text(row.preview)
                            .lineLimit(2)
                    }
                }
                .frame(minHeight: 160, maxHeight: 240)
            }

            if let err = viewModel.metadataApplyErrorMessage, summary.matchedCount == 0 {
                Text(err)
                    .foregroundStyle(.red)
            }

            HStack {
                if summary.unmatchedCount > 0, viewModel.metadataApplyUnmatchedRows == nil {
                    Button("Review unmatched…") {
                        viewModel.loadUnmatchedForCurrentApply()
                    }
                }
                Spacer()
                Button("Done") {
                    viewModel.dismissMetadataApplySummary()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: viewModel.metadataApplyUnmatchedRows == nil ? 320 : 480)
        .onDisappear {
            // Keep summary dismissed when sheet closes via ESC
            if viewModel.metadataApplySummary?.id == summary.id {
                viewModel.dismissMetadataApplySummary()
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(Color.appTextSecondary)
            Text(value)
                .font(.body.monospacedDigit().weight(.semibold))
        }
    }
}

enum ApplyMetadataFilePicker {
    @MainActor
    static func present(onPicked: @escaping (URL, Data) -> Void, onReadError: ((String) -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a CSV or JSON Lines metadata file to import (updates existing videos by Path or Content Fingerprint)."
        var types: [UTType] = [.commaSeparatedText, .json]
        if let jsonl = UTType(filenameExtension: "jsonl") {
            types.insert(jsonl, at: 0)
        }
        panel.allowedContentTypes = types
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Read while security-scoped access is active; Apply keeps the bytes in memory.
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                onPicked(url, data)
            } catch {
                onReadError?(error.localizedDescription)
            }
        }
    }
}
