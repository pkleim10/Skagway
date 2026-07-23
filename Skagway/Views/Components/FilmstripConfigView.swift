import SwiftUI

/// Sheet payload for Modify Filmstrip (one or many videos from the current selection).
struct FilmstripModifySession: Identifiable {
    let id = UUID()
    let videos: [Video]
}

struct FilmstripConfigView: View {
    let videos: [Video]
    let thumbnailService: ThumbnailService
    var defaultRows: Int = 2
    var defaultColumns: Int = 5
    /// Called after a successful run (including partial multi-select success) so the inspector can reload.
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rows: Int = 2
    @State private var columns: Int = 5
    @State private var isGenerating = false
    @State private var completedCount = 0
    @State private var failureCount = 0
    @State private var generateErrorMessage: String?
    @State private var generateTask: Task<Void, Never>?

    private var totalFrames: Int { rows * columns }
    private var isMulti: Bool { videos.count > 1 }

    private var subtitle: String {
        if videos.count == 1 {
            return videos[0].fileName
        }
        return "\(videos.count) videos"
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("Modify Filmstrip")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(1)

            HStack(spacing: AppSpacing.xxl) {
                labeledSettingsStepper("Rows", value: $rows, range: 1...6)
                labeledSettingsStepper("Columns", value: $columns, range: 1...8)
            }
            .disabled(isGenerating)

            Text("\(totalFrames) frames")
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)

            if let generateErrorMessage {
                Text(generateErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(isGenerating ? "Stop" : "Cancel") {
                    if isGenerating {
                        generateTask?.cancel()
                        generateTask = nil
                        isGenerating = false
                        if completedCount > 0 {
                            onComplete()
                        }
                    } else {
                        dismiss()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Generate") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isGenerating || videos.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
            }

            if isGenerating {
                ProgressView(
                    value: Double(completedCount),
                    total: Double(max(videos.count, 1))
                ) {
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
                .controlSize(.small)
                .tint(Color.appAccent)
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(Material.appSubtleGlass)
                .background(Color.appSurface.opacity(0.75))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(Color.appAccent.opacity(0.15), lineWidth: 1)
        )
        .onAppear {
            seedRowsAndColumns()
            generateErrorMessage = nil
        }
        .onDisappear {
            generateTask?.cancel()
            generateTask = nil
        }
    }

    private var progressLabel: String {
        if isMulti {
            return "Generating \(min(completedCount + 1, videos.count)) of \(videos.count)…"
        }
        return "Generating filmstrip…"
    }

    private func labeledSettingsStepper(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.appTextSecondary)
            SettingsIntegerStepper(value: value, range: range)
        }
    }

    private func seedRowsAndColumns() {
        if videos.count == 1,
           let image = thumbnailService.loadFilmstrip(for: videos[0].filePath),
           let grid = ThumbnailService.filmstripGrid(in: image)
        {
            rows = min(max(grid.rows, 1), 6)
            columns = min(max(grid.columns, 1), 8)
        } else {
            rows = defaultRows
            columns = defaultColumns
        }
    }

    private func generate() {
        guard !videos.isEmpty else { return }
        isGenerating = true
        completedCount = 0
        failureCount = 0
        generateErrorMessage = nil

        let targets = videos
        let targetRows = rows
        let targetColumns = columns

        generateTask = Task { @MainActor in
            var failures = 0
            for (index, video) in targets.enumerated() {
                if Task.isCancelled { break }

                do {
                    _ = try await thumbnailService.regenerateFilmstrip(
                        for: video, rows: targetRows, columns: targetColumns
                    )
                } catch is CancellationError {
                    break
                } catch {
                    failures += 1
                    // Single-video: surface the specific error and stay open.
                    if targets.count == 1 {
                        isGenerating = false
                        generateTask = nil
                        if let thumbError = error as? ThumbnailError {
                            generateErrorMessage = thumbError.errorDescription
                                ?? "Couldn’t generate filmstrip."
                        } else {
                            generateErrorMessage =
                                "Couldn’t generate filmstrip. Try a shorter grid or a different video."
                        }
                        return
                    }
                }

                completedCount = index + 1
                failureCount = failures
            }

            let cancelled = Task.isCancelled
            isGenerating = false
            generateTask = nil

            if cancelled {
                if completedCount > 0 { onComplete() }
                return
            }

            if failures == 0 {
                onComplete()
                dismiss()
            } else if failures == targets.count {
                generateErrorMessage = "Couldn’t generate filmstrips for any of the \(targets.count) videos."
            } else {
                onComplete()
                generateErrorMessage =
                    "Generated \(targets.count - failures) of \(targets.count). \(failures) failed (missing or unreadable files)."
            }
        }
    }
}
