import Foundation

/// The value "shape" of a filter field, driving which operators are valid and which value editor
/// the rule builders show. Unifies built-in `RuleAttribute`s and custom fields under one notion.
enum FilterFieldKind {
    case string
    case number
    case date
    case rating
    case tag
    case quality
}

extension FilterField {
    func kind(customFields: [UUID: CustomMetadataFieldDefinition]) -> FilterFieldKind {
        switch self {
        case .builtin(let attr):
            switch attr {
            case .name, .fileExtension, .path, .parentFolder, .volume, .codec: return .string
            case .tag: return .tag
            case .fileSize, .duration, .height, .width, .playCount: return .number
            case .rating: return .rating
            case .dateImported, .dateCreated: return .date
            case .quality: return .quality
            }
        case .custom(let id):
            switch customFields[id]?.valueType {
            case .number: return .number
            case .date, .dateTime: return .date
            case .string, .text, .none: return .string
            }
        }
    }

    func label(customFields: [UUID: CustomMetadataFieldDefinition]) -> String {
        switch self {
        case .builtin(let attr): return attr.label
        case .custom(let id): return customFields[id]?.name ?? "(deleted field)"
        }
    }

    func supportedComparisons(customFields: [UUID: CustomMetadataFieldDefinition]) -> [RuleComparison] {
        switch self {
        case .builtin(let attr):
            return attr.supportedComparisons
        case .custom:
            switch kind(customFields: customFields) {
            case .string, .tag:
                return [.equals, .notEquals, .contains, .startsWith, .endsWith, .matches]
            case .number, .rating:
                return [.equals, .notEquals, .lessThan, .greaterThan, .lessThanOrEqual, .greaterThanOrEqual, .between]
            case .date:
                return [.equals, .lessThan, .greaterThan, .between]
            case .quality:
                return [.equals, .notEquals]
            }
        }
    }

    func valuePlaceholder(customFields: [UUID: CustomMetadataFieldDefinition]) -> String {
        switch self {
        case .builtin(let attr): return attr.valuePlaceholder
        case .custom(let id):
            switch customFields[id]?.valueType {
            case .number: return "Number"
            case .date, .dateTime: return "YYYY-MM-DD"
            default: return "Value"
            }
        }
    }
}

/// Shared `yyyy-MM-dd` formatter for date rule values — the storage format `FilterMatcher.parseDay`
/// reads (ISO8601 full-date).
enum RuleDateFormat {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}
