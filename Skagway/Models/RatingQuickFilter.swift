import Foundation

/// Quick Filter rating card: exact star, unrated (`0`), or “this rating or higher”.
enum RatingQuickFilter {
    /// `0` means unrated. Or Higher applies only for floors 1–4.
    static func apply(selectedStars: Set<Int>, orHigher: Bool, base: [Video]) -> [Video] {
        guard let floor = selectedStars.min() else { return base }
        if orHigher, floor > 0, floor < 5 {
            return base.filter { $0.rating >= floor }
        }
        return base.filter { selectedStars.contains($0.rating) }
    }
}
