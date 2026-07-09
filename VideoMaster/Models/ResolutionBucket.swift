import Foundation

/// The seven distinct labels `Video.resolutionLabel` can produce, in ascending order — the chip
/// set for the Quality filter attribute. Kept in sync with `Video.resolutionLabel` by hand (both
/// are tiny and rarely change).
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

    /// Encode a multi-select chip set as the comma-separated storage string used by
    /// `FilterCondition.value` for `.quality` rules.
    static func encode(_ buckets: Set<String>) -> String {
        allCases.map(\.rawValue).filter { buckets.contains($0) }.joined(separator: ",")
    }

    /// Decode a Quality rule value into the selected bucket set. Unknown tokens are ignored.
    static func decode(_ raw: String) -> Set<String> {
        let known = Set(allCases.map(\.rawValue))
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return Set(parts.filter { known.contains($0) })
    }
}
