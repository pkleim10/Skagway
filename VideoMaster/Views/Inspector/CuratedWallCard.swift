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
    let isSelected: Bool
    let thumbnailService: ThumbnailService

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    private let thumbHeight: CGFloat = 188   // taller, more gallery presence per the mock
    private let corner: CGFloat = 8

    var body: some View {
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
                            .stroke(isSelected ? Color.appAccent.opacity(0.65) : Color.appDivider.opacity(isHovering ? 0.45 : 0.18),
                                    lineWidth: isSelected ? 2 : 1)
                    )

                // Selection checkmark inside the image (per mock treatment)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .padding(6)
                }

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

            // Very light metadata row (exactly as described in mocks + plan)
            VStack(alignment: .leading, spacing: 2) {
                Text(video.fileName)
                    .font(.system(size: 11))
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(Color.appTextPrimary)
                    .lineLimit(1)

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
                ? Color.appAccent.opacity(0.07)
                : (isHovering ? Color.appSurface.opacity(0.6) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner + 2, style: .continuous))
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
