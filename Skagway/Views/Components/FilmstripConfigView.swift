import SwiftUI

struct FilmstripConfigView: View {
    let video: Video
    let thumbnailService: ThumbnailService
    var defaultRows: Int = 2
    var defaultColumns: Int = 5
    let onComplete: (NSImage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rows: Int = 2
    @State private var columns: Int = 5
    @State private var isGenerating = false
    @State private var generateErrorMessage: String?

    private var totalFrames: Int { rows * columns }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("Modify Filmstrip")
                .font(.headline)
                .foregroundStyle(Color.appTextPrimary)

            Text(video.fileName)
                .font(.callout)
                .foregroundStyle(Color.appTextSecondary)
                .lineLimit(1)

            HStack(spacing: AppSpacing.xxl) {
                labeledSettingsStepper("Rows", value: $rows, range: 1...6)
                labeledSettingsStepper("Columns", value: $columns, range: 1...8)
            }

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
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Generate") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isGenerating)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
            }

            if isGenerating {
                ProgressView("Generating filmstrip...")
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
            rows = defaultRows
            columns = defaultColumns
            generateErrorMessage = nil
        }
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

    private func generate() {
        isGenerating = true
        generateErrorMessage = nil
        Task { @MainActor in
            do {
                let image = try await thumbnailService.regenerateFilmstrip(
                    for: video, rows: rows, columns: columns
                )
                onComplete(image)
                dismiss()
            } catch {
                isGenerating = false
                if let thumbError = error as? ThumbnailError {
                    generateErrorMessage = thumbError.errorDescription
                        ?? "Couldn’t generate filmstrip."
                } else {
                    generateErrorMessage =
                        "Couldn’t generate filmstrip. Try a shorter grid or a different video."
                }
            }
        }
    }
}
