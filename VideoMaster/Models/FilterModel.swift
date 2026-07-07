import Foundation

/// The unified filter domain model (Phase 2 of the layered-filtering design). One model backs both
/// the saved-Collections rule engine and — from Phase 3 — the live advanced filter, so there is a
/// single filter language and a single matcher (`FilterMatcher`).
///
/// A `FilterGroup` is a boolean tree: a match mode (ALL/ANY) over a list of nodes, each of which is
/// either a leaf `FilterCondition` or a nested `FilterGroup`. Collections' existing two-level
/// structure (collection mode → rule-group mode → rules) maps onto this directly; the model itself
/// allows arbitrary nesting, while the editors cap depth at two levels (matching the validated
/// Collections design).

// MARK: - Filter field

/// What a condition tests: one of the built-in `RuleAttribute`s, or a custom metadata field.
///
/// Codable as a single string token so it stores in the existing `collection_rule.attribute` TEXT
/// column with no schema change: built-ins keep their exact `RuleAttribute` rawValue ("fileSize",
/// "rating", …) — so every existing stored rule decodes unchanged — and custom fields encode as
/// `custom:<uuid>`.
enum FilterField: Equatable, Hashable {
    case builtin(RuleAttribute)
    case custom(UUID)

    private static let customPrefix = "custom:"

    var storageToken: String {
        switch self {
        case .builtin(let attr): return attr.rawValue
        case .custom(let id): return Self.customPrefix + id.uuidString
        }
    }

    init?(storageToken: String) {
        if storageToken.hasPrefix(Self.customPrefix) {
            let raw = String(storageToken.dropFirst(Self.customPrefix.count))
            guard let id = UUID(uuidString: raw) else { return nil }
            self = .custom(id)
        } else if let attr = RuleAttribute(rawValue: storageToken) {
            self = .builtin(attr)
        } else {
            return nil
        }
    }
}

extension FilterField: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let token = try container.decode(String.self)
        guard let field = FilterField(storageToken: token) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized filter field token: \(token)")
        }
        self = field
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageToken)
    }
}

// MARK: - Condition

/// A single leaf test: `field` compared to `value` (and, for `.between`, `value2` as the upper
/// bound) using `comparison`. Values are stored as strings and parsed per the field's kind at
/// compile time, exactly as `CollectionRule` already does — the added `value2` is the only new
/// piece, carrying the second bound of a range.
struct FilterCondition: Equatable, Hashable, Codable {
    var field: FilterField
    var comparison: RuleComparison
    var value: String
    var value2: String?

    init(field: FilterField, comparison: RuleComparison, value: String, value2: String? = nil) {
        self.field = field
        self.comparison = comparison
        self.value = value
        self.value2 = value2
    }
}

// MARK: - Tree

indirect enum FilterNode: Equatable, Hashable, Codable {
    case condition(FilterCondition)
    case group(FilterGroup)
}

struct FilterGroup: Equatable, Hashable, Codable {
    var mode: MatchMode
    var nodes: [FilterNode]

    init(mode: MatchMode = .all, nodes: [FilterNode] = []) {
        self.mode = mode
        self.nodes = nodes
    }

    /// True when the group has no leaf conditions anywhere in its tree — a filter that matches
    /// everything (so callers can treat it as "no filter"). An empty group and a group of empty
    /// groups both count as empty.
    var isEmpty: Bool {
        !nodes.contains { node in
            switch node {
            case .condition: return true
            case .group(let g): return !g.isEmpty
            }
        }
    }
}
