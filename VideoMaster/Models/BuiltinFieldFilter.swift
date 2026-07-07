import Foundation

/// A built-in `Video` field exposed as a simple, AND-combined "quick filter" row in the Filters
/// Drawer (Tier 1 of the layered-filtering design — see `LayeredFiltering_Design_2026-07-06.md`).
///
/// These are the fields NOT already pinned as their own dedicated quick control: Rating, Duration,
/// and Tags keep their own cards; everything here is reached through the shared "Add filter" menu,
/// exactly like custom fields. Phase 1 deliberately does not touch the Collections rule engine —
/// each field maps to one live, AND-combined criterion via `BuiltinFilterCriterion`.
enum BuiltinFilterField: String, CaseIterable, Identifiable, Hashable {
    case quality        // resolution bucket (SD…8K+), derived from `Video.resolutionLabel`
    case fileSize       // bytes
    case dateAdded      // `Video.dateAdded`
    case dateCreated    // `Video.creationDate`
    case plays          // `Video.playCount` (unplayed vs. played)
    case codec          // `Video.codec`
    case fileExtension  // derived from the path
    case folder         // immediate parent folder name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality: return "Quality"
        case .fileSize: return "File Size"
        case .dateAdded: return "Date Added"
        case .dateCreated: return "Date Created"
        case .plays: return "Plays"
        case .codec: return "Codec"
        case .fileExtension: return "Extension"
        case .folder: return "Folder"
        }
    }

    /// The inert default criterion inserted when this field is picked from the "Add filter" menu —
    /// an empty, editable row that doesn't yet narrow results (`isActive` is false) until the user
    /// fills it in. Mirrors how custom-field rows start inert.
    var defaultCriterion: BuiltinFilterCriterion {
        switch self {
        case .quality: return .quality([])
        case .fileSize: return .sizeRange(minBytes: nil, maxBytes: nil)
        case .dateAdded, .dateCreated: return .dateRange(min: nil, max: nil)
        case .plays: return .plays(nil)
        case .codec, .fileExtension, .folder: return .contains("")
        }
    }
}

/// The seven distinct labels `Video.resolutionLabel` can produce, in ascending order — the chip
/// set for the Quality quick filter. Kept in sync with `Video.resolutionLabel` by hand (both are
/// tiny and rarely change).
enum ResolutionBucket: String, CaseIterable, Identifiable {
    case sd = "SD"
    case p480 = "480p"
    case p720 = "720p"
    case p1080 = "1080p"
    case p1440 = "1440p"
    case k4 = "4K"
    case k8 = "8K+"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Which subset of a video's play history a `.plays` filter matches.
enum PlaysFilter: Equatable {
    case unplayed   // playCount == 0
    case played     // playCount > 0
}

/// One active built-in-field filter criterion. Like `CustomFieldFilterCriterion`, associated values
/// are the already-typed bounds/needle/selection the user configured — never raw strings.
enum BuiltinFilterCriterion: Equatable {
    /// Video's `resolutionLabel` is in the selected set. OR *within* the set (a video matches if it
    /// falls in any selected bucket), like multi-star rating; empty set = inactive.
    case quality(Set<String>)
    /// File size in bytes; inclusive range, either bound optional (open-ended).
    case sizeRange(minBytes: Double?, maxBytes: Double?)
    /// Date range; inclusive, either bound optional. The max bound is treated as "through the end
    /// of that day" by the matcher, since a `.date` DatePicker returns midnight.
    case dateRange(min: Date?, max: Date?)
    /// Unplayed / played. `nil` = not yet chosen (inert row).
    case plays(PlaysFilter?)
    /// Case-insensitive substring match against a string field (codec / extension / folder).
    case contains(String)
}
