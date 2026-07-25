import SwiftUI

/// Centered empty-catalog invite in the browser (grid/list area). The whole browser remains
/// a drop target; this is the visual cue when there are no videos yet.
struct EmptyLibraryBrowserPlaceholder: View {
    var isDropTargeted: Bool
    var onAddFiles: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            dropZone
                .frame(maxWidth: 480)
                .padding(.horizontal, 32)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.opacity(0.35))
    }

    private var dropZone: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(isDropTargeted ? 0.22 : 0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "film.stack")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Color.appAccent.opacity(0.95))
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), isActive: isDropTargeted)
            }

            VStack(spacing: AppSpacing.sm) {
                Text(isDropTargeted ? "Drop to add to your library" : "Drag videos here")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.appTextPrimary)
                    .multilineTextAlignment(.center)

                Text("Drop video files or folders onto this area to import them.")
                    .font(.body)
                    .foregroundStyle(Color.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("or")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appTextTertiary)

            VStack(spacing: AppSpacing.md) {
                Button(action: onAddFiles) {
                    Label("Add Files…", systemImage: "plus.rectangle.on.folder")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)
                .controlSize(.large)

                Text("File → Add Folder… (⇧⌘O)")
                    .font(.caption)
                    .foregroundStyle(Color.appTextTertiary)
            }

            Text(
                "Folders you add (or the parent folders of files you add) are saved as Data Sources in Settings, so Skagway can scan and watch them later."
            )
            .font(.caption)
            .foregroundStyle(Color.appTextTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, AppSpacing.xs)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(Color.appSurface.opacity(isDropTargeted ? 0.55 : 0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2.5 : 1.75, dash: [10, 7])
                )
                .foregroundStyle(
                    isDropTargeted
                        ? Color.appAccent
                        : Color.appAccent.opacity(0.45)
                )
        )
        .scaleEffect(isDropTargeted ? 1.02 : 1)
        .animation(.easeInOut(duration: 0.18), value: isDropTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Empty library. Drag videos here, or add files. Folders you add become Data Sources in Settings."
        )
    }
}
