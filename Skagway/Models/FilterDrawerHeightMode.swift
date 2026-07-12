import Foundation

/// How the Curated Wall filters drawer decides its height each time it opens.
enum FilterDrawerHeightMode: String, Codable, CaseIterable, Identifiable {
    /// Always open at the drawer's natural content height (capped to what fits in the window).
    /// The resize handle is hidden — height isn't user-adjustable in this mode.
    case fitToContent
    /// Open at (and remember) whatever height the user last dragged the drawer to.
    case lastUsed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fitToContent: return "Fit to content"
        case .lastUsed: return "Last used"
        }
    }
}
