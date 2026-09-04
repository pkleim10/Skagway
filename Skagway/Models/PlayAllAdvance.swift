import Foundation

/// Next-index rules for Play All: skip missing files; loop only when requested.
enum PlayAllAdvance {
    /// Index of the next playable item after `currentIndex`, or `nil` if the session should end.
    static func nextIndex(
        after currentIndex: Int,
        paths: [String],
        loop: Bool,
        fileExists: (String) -> Bool
    ) -> Int? {
        var nextIdx = currentIndex + 1
        while nextIdx < paths.count {
            if fileExists(paths[nextIdx]) { return nextIdx }
            nextIdx += 1
        }
        if loop {
            return paths.indices.first { fileExists(paths[$0]) }
        }
        return nil
    }
}
