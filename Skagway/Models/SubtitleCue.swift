import Foundation

/// One timed subtitle entry parsed from an SRT file.
struct SubtitleCue: Equatable, Hashable, Identifiable {
    let id: Int
    /// Start time in seconds from the beginning of the media.
    let start: Double
    /// End time in seconds from the beginning of the media.
    let end: Double
    /// Original lines (with their SRT-authored line breaks preserved) — translators
    /// often break for rhythm, so we display as authored rather than rejoining.
    let lines: [String]

    var text: String { lines.joined(separator: "\n") }
    var duration: Double { max(0, end - start) }
}
