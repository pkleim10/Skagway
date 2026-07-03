import Foundation

/// User preference for the Inspector's "Add tags" blind (the collapsible unassigned-tags list)
/// each time the selection changes.
enum TagBlindDefaultState: String, Codable, CaseIterable, Identifiable {
    /// Collapse the blind on every new selection (the original, hardcoded behavior).
    case alwaysClosed
    /// Expand the blind on every new selection — convenient for libraries with few tags, where
    /// the unassigned list is short and useful to see at a glance.
    case alwaysOpen
    /// Don't touch the blind's state on selection change — it keeps whatever the user last set.
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alwaysClosed: return "Always closed"
        case .alwaysOpen: return "Always open"
        case .lastUsed: return "Leave as is (last used)"
        }
    }
}
