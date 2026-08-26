import Foundation

/// Pure playlist-order helpers for Albums (no DB / UI). Used by drag-reorder and covered by tests.
enum AlbumPlaylistOrder {
    /// Moves `moving` (preserving their relative order as they appear in `order`) so they sit
    /// immediately before `target`. Returns `nil` when the move is a no-op or invalid
    /// (target missing, target itself being moved, nothing to move).
    static func moving(_ moving: [Int64], before target: Int64, in order: [Int64]) -> [Int64]? {
        guard order.contains(target) else { return nil }
        let movingSet = Set(moving)
        let movingInOrder = order.filter { movingSet.contains($0) }
        guard !movingInOrder.isEmpty else { return nil }
        if movingInOrder.contains(target) { return nil }

        let movingLookup = Set(movingInOrder)
        var remaining = order.filter { !movingLookup.contains($0) }
        guard let insertAt = remaining.firstIndex(of: target) else { return nil }
        remaining.insert(contentsOf: movingInOrder, at: insertAt)
        if remaining == order { return nil }
        return remaining
    }
}
