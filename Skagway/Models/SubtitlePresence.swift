import Foundation

/// How captions relate to a video. Stored in the `hasSubtitles` integer column
/// (legacy bool remapped: old `1` → `.sidecar`).
enum SubtitlePresence: Int, Codable, CaseIterable, Sendable, Hashable {
    case none = 0
    case burnedIn = 1
    case sidecar = 2
    case burnedInAndSidecar = 3

    var displayName: String {
        switch self {
        case .none: return "None"
        case .burnedIn: return "Burned-in"
        case .sidecar: return "Sidecar"
        case .burnedInAndSidecar: return "Burned-in + Sidecar"
        }
    }

    /// Show the CC badge in grid/list for any non-empty presence.
    var showsBadge: Bool { self != .none }

    var badgeHelp: String {
        switch self {
        case .none: return "No subtitles"
        case .burnedIn: return "Burned-in subtitles"
        case .sidecar: return "Sidecar subtitle file"
        case .burnedInAndSidecar: return "Burned-in subtitles and sidecar file"
        }
    }

    /// Apply the result of a sidecar file presence check without wiping a user-set burned-in mark.
    func applying(sidecarPresent: Bool) -> SubtitlePresence {
        if sidecarPresent {
            switch self {
            case .none, .sidecar: return .sidecar
            case .burnedIn, .burnedInAndSidecar: return .burnedInAndSidecar
            }
        } else {
            switch self {
            case .none, .sidecar: return .none
            case .burnedIn, .burnedInAndSidecar: return .burnedIn
            }
        }
    }

    /// Parse export/import cells. Accepts display names and legacy Yes/No/true/false.
    static func parse(_ raw: String) -> SubtitlePresence? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        switch lower {
        case "none", "no", "false", "0":
            return .none
        case "burned-in", "burnedin", "burned_in":
            return .burnedIn
        case "sidecar", "srt", "yes", "true", "1":
            return .sidecar
        case "burned-in + sidecar", "burned-in+sidecar", "burnedinandsidecar",
             "burned_in_and_sidecar", "both":
            return .burnedInAndSidecar
        default:
            return nil
        }
    }
}
