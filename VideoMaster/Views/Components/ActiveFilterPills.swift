import SwiftUI

/// Very lightweight removable pill row shown under the header when the Curated Wall filters drawer is closed
/// but some filters (smart lib / collection / tags / rating / duration) are active.
/// Matches the refined, low-chrome aesthetic of the wall.
struct ActiveFilterPills: View {
    @Bindable var viewModel: LibraryViewModel

    var body: some View {
        if viewModel.hasActiveFilters {
            HStack(spacing: 6) {
                // Scrollable pills only — "Clear all" lives outside this ScrollView (below) so it
                // stays reachable even when there are enough pills to overflow the visible width,
                // instead of scrolling out of view as just another trailing item.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        // Sidebar / smart filter pill
                        if let f = viewModel.sidebarFilter, f != .all {
                            pill(text: pillText(for: f), systemImage: icon(for: f)) {
                                viewModel.sidebarFilter = .all
                            }
                        } else if case .collection(let c) = viewModel.sidebarFilter {
                            pill(text: "Collection: \(c.name)", systemImage: "folder") {
                                viewModel.sidebarFilter = .all
                            }
                        }

                        // Rating
                        if let rating = viewModel.selectedRatingStars.first {
                            pill(text: "Rating \(rating)", systemImage: "star") {
                                viewModel.clearRatingFilter()
                            }
                        }

                        // Tags
                        if !viewModel.selectedTagIds.isEmpty {
                            let count = viewModel.selectedTagIds.count
                            pill(text: count == 1 ? "1 tag" : "\(count) tags", systemImage: "tag") {
                                viewModel.clearTagFilters()
                            }
                        }

                        // Duration
                        if viewModel.minDurationSeconds != nil || viewModel.maxDurationSeconds != nil {
                            let txt: String = {
                                if let mn = viewModel.minDurationSeconds, let mx = viewModel.maxDurationSeconds {
                                    return "\(Int(mn/60))–\(Int(mx/60)) min"
                                } else if let mn = viewModel.minDurationSeconds {
                                    return "≥\(Int(mn/60)) min"
                                } else if let mx = viewModel.maxDurationSeconds {
                                    return "≤\(Int(mx/60)) min"
                                }
                                return "Duration"
                            }()
                            pill(text: txt, systemImage: "clock") {
                                viewModel.clearDurationFilter()
                            }
                        }
                    }
                }

                Button("Clear all") {
                    viewModel.resetAllFilters()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.appAccent)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.appSurface.opacity(0.4))
            .transition(.opacity)
        }
    }

    private func pill(text: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(text)
                    .font(.caption)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.appAccent.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(Color.appAccent.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appTextPrimary)
    }

    private func pillText(for filter: SidebarFilter) -> String {
        switch filter {
        case .all: return "All"
        case .recentlyAdded: return "Recently Added"
        case .recentlyPlayed: return "Recently Played"
        case .topRated: return "Top Rated"
        case .duplicates: return "Duplicates"
        case .corrupt: return "Corrupt"
        case .missing: return "Missing"
        case .recentlyConverted: return "Recently Converted"
        case .collection(let c): return c.name
        }
    }

    private func icon(for filter: SidebarFilter) -> String {
        switch filter {
        case .all: return "film.stack"
        case .recentlyAdded: return "clock"
        case .recentlyPlayed: return "play.circle"
        case .topRated: return "star.fill"
        case .duplicates: return "doc.on.doc"
        case .corrupt: return "exclamationmark.triangle"
        case .missing: return "questionmark.circle"
        case .recentlyConverted: return "arrow.triangle.2.circlepath"
        case .collection: return "folder"
        }
    }
}