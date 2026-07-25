import Foundation

/// How a custom metadata field is edited and stored.
enum CustomMetadataValueType: CaseIterable, Identifiable, Sendable {
    /// Single-line text.
    case string
    /// Multiline text (“text box”).
    case text
    /// Numeric values (integers and floating-point).
    case number
    /// Calendar date (no time-of-day).
    case date
    /// Date and time of day.
    case dateTime
    /// True/false; stored canonically as `"true"` / `"false"`.
    case boolean

    var id: String { rawValue }

    /// Persisted key in the library database (`custom_metadata_field.valueType`).
    var rawValue: String {
        switch self {
        case .string: return "string"
        case .text: return "text"
        case .number: return "number"
        case .date: return "date"
        case .dateTime: return "dateTime"
        case .boolean: return "boolean"
        }
    }

    var displayName: String {
        switch self {
        case .string: return "String"
        case .text: return "Text"
        case .number: return "Number"
        case .date: return "Date"
        case .dateTime: return "Date & Time"
        case .boolean: return "Boolean"
        }
    }

    static var allCases: [CustomMetadataValueType] {
        [.string, .text, .number, .date, .dateTime, .boolean]
    }

    init?(rawValue: String) {
        switch rawValue {
        case "string": self = .string
        case "text": self = .text
        case "number", "integer", "fp": self = .number
        case "date": self = .date
        case "dateTime": self = .dateTime
        case "boolean": self = .boolean
        default: return nil
        }
    }

    /// Normalize a cell/edit string to canonical `"true"` / `"false"`.
    /// Accepts true/false, yes/no, y/n, 1/0 (case-insensitive). Other values → nil.
    static func normalizeBooleanStorage(_ raw: String) -> String? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "y", "1": return "true"
        case "false", "no", "n", "0": return "false"
        default: return nil
        }
    }

    /// Whether `raw` is a recognized boolean token (for import type inference).
    static func isBooleanToken(_ raw: String) -> Bool {
        normalizeBooleanStorage(raw) != nil
    }
}

extension CustomMetadataValueType: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let value = CustomMetadataValueType(rawValue: s) else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unknown CustomMetadataValueType: \(s)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// One row in Settings → Custom Metadata (field name + type). Scoped to the active library database.
struct CustomMetadataFieldDefinition: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var valueType: CustomMetadataValueType

    init(id: UUID = UUID(), name: String, valueType: CustomMetadataValueType) {
        self.id = id
        self.name = name
        self.valueType = valueType
    }
}
