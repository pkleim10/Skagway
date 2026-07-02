import SwiftUI
import AppKit

/// Dedicated elegant gallery card for the Curated Wall.
/// Designed to match the refined mockups as closely as possible:
/// - Large, prominent thumbnail area with clean framing
/// - Minimal metadata underneath: short title + date + tiny stars
/// - Soft selection treatment (ring + checkmark)
/// - Generous breathing room, gallery feel
struct CuratedWallCard: View {
    let video: Video
    let selectionState: CardSelectionState
    let isRenaming: Bool
    @Binding var renameText: String
    let thumbnailService: ThumbnailService
    var renameFocus: FocusState<Bool>.Binding
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void
    var onRenameEditingChanged: (Bool) -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    private let thumbHeight: CGFloat = 188   // taller, more gallery presence per the mock
    private let corner: CGFloat = 8

    var body: some View {
        let isSelected = selectionState.isSelected
        VStack(alignment: .leading, spacing: 6) {
            // Image area - the star of the card
            ZStack(alignment: .bottomTrailing) {
                Color.appSurface
                    .frame(height: thumbHeight)
                    .overlay {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(Color.appSurface)
                                .overlay {
                                    Image(systemName: "film")
                                        .font(.title2)
                                        .foregroundStyle(Color.appTextTertiary.opacity(0.5))
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color.appDivider.opacity(isHovering ? 0.45 : 0.18), lineWidth: 1)
                    )

                if let dur = video.formattedDuration {
                    Text(dur)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
            }
            // Selection checkmark — white check in a blue circle, upper-left corner.
            .overlay(alignment: .topLeading) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.appAccent)
                        .padding(6)
                }
            }

            // Very light metadata row (exactly as described in mocks + plan)
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.appAccent, lineWidth: 1.5)
                        )
                        .focused(renameFocus)
                        .onSubmit { onCommitRename() }
                        .onExitCommand { onCancelRename() }
                        .onAppear { onRenameEditingChanged(true) }
                        .onDisappear { onRenameEditingChanged(false) }
                } else {
                    Text(video.fileName)
                        .font(.system(size: 11))
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(1)
                }

                HStack {
                    Text(video.dateAdded.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.appTextTertiary)

                    Spacer()

                    if video.rating > 0 {
                        HStack(spacing: 1) {
                            ForEach(0..<video.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            isSelected
                ? Color(red: 12 / 255, green: 20 / 255, blue: 30 / 255)   // #0C141E
                : (isHovering ? Color.appSurface.opacity(0.6) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner + 2, style: .continuous))
        // Blue selection border around the whole card (not just the thumbnail).
        .overlay(
            RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                .stroke(isSelected ? Color.appAccent : Color.clear, lineWidth: 2)
        )
        .onHover { hovering in
            isHovering = hovering
        }
        .task(id: video.filePath) {
            if thumbnail == nil {
                if let lo = thumbnailService.loadThumbnail(for: video.filePath) {
                    thumbnail = lo
                }
                // Upgrade to nicer detail preview asynchronously when available (no blocking the card)
                Task {
                    if let hi = await thumbnailService.detailPreviewImage(for: video, longEdge: 720) {
                        await MainActor.run {
                            if self.thumbnail == nil || self.thumbnail?.size.width ?? 0 < 400 {
                                self.thumbnail = hi
                            }
                        }
                    }
                }
            }
        }
    }
}
