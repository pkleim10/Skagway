import Foundation

/// Suggest a custom-metadata type from non-empty import cell samples.
enum MetadataImportTypeInference {
    static let maxSamplesPerColumn = 50

    /// Order matters: boolean before number so `0`/`1` don’t become Number.
    static func suggestType(samples: [String]) -> CustomMetadataValueType {
        let nonEmpty = samples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return .string }

        if nonEmpty.allSatisfy({ CustomMetadataValueType.isBooleanToken($0) }) {
            return .boolean
        }

        if nonEmpty.allSatisfy({ Double($0) != nil }) {
            return .number
        }

        let dateKinds = nonEmpty.map(dateKind)
        if dateKinds.allSatisfy({ $0 == .dateTime }) {
            return .dateTime
        }
        if dateKinds.allSatisfy({ $0 == .date || $0 == .dateTime }) {
            // Prefer date when every value is date-only; if any has time, use dateTime.
            return dateKinds.contains(.dateTime) ? .dateTime : .date
        }

        if nonEmpty.contains(where: { $0.contains("\n") || $0.count > 120 }) {
            return .text
        }

        return .string
    }

    private enum DateKind { case date, dateTime, none }

    private static func dateKind(_ raw: String) -> DateKind {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isoDateOnly.date(from: t) != nil { return .date }
        if isoFrac.date(from: t) != nil || isoPlain.date(from: t) != nil { return .dateTime }
        // Common "yyyy-MM-dd HH:mm:ss" without timezone
        if looseDateTime.date(from: t) != nil { return .dateTime }
        return .none
    }

    private static let isoDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let looseDateTime: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// An import column that did not resolve to a built-in or existing custom field.
struct UnknownImportColumn: Equatable, Identifiable, Sendable {
    var key: String
    var sampleValues: [String]
    var suggestedType: CustomMetadataValueType

    var id: String { key }

    var samplePreview: String {
        sampleValues.first.map {
            let t = $0.replacingOccurrences(of: "\n", with: " ")
            return t.count > 48 ? String(t.prefix(45)) + "…" : t
        } ?? ""
    }
}
