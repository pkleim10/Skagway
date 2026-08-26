import Foundation

/// Pure playlist-order helpers for Albums (no DB / UI). Used by drag-reorder and covered by tests.
enum AlbumPlaylistOrder {
    /// Moves `moving` (preserving their relative order as they appear in `order`) onto `target`.
    /// Dragging toward a later item inserts **after** it (so dropping on the next card swaps);
    /// dragging toward an earlier item inserts **before** it. Returns `nil` when the move is a
    /// no-op or invalid (target missing, target itself being moved, nothing to move).
    static func moving(_ moving: [Int64], onto target: Int64, in order: [Int64]) -> [Int64]? {
        guard let targetIndex = order.firstIndex(of: target) else { return nil }
        let movingSet = Set(moving)
        let movingInOrder = order.filter { movingSet.contains($0) }
        guard !movingInOrder.isEmpty else { return nil }
        if movingInOrder.contains(target) { return nil }
        guard let fromIndex = order.firstIndex(where: { movingSet.contains($0) }) else { return nil }

        let movingLookup = Set(movingInOrder)
        var remaining = order.filter { !movingLookup.contains($0) }
        guard let newTargetIndex = remaining.firstIndex(of: target) else { return nil }
        let draggingLater = fromIndex < targetIndex
        let insertAt = draggingLater ? newTargetIndex + 1 : newTargetIndex
        remaining.insert(contentsOf: movingInOrder, at: min(insertAt, remaining.count))
        if remaining == order { return nil }
        return remaining
    }
}
