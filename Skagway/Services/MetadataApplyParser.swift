import Foundation

enum MetadataApplyFormat: String, Sendable {
    case csv
    case jsonl
}

enum MetadataApplyDetectError: LocalizedError, Equatable {
    case emptyFile
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "The file is empty."
        case .unrecognizedFormat: return "Could not detect CSV or JSON Lines format."
        }
    }
}

/// One parsed row: internal column id → raw cell string (JSON null / empty → absent or empty string).
struct MetadataApplyRow: Equatable, Sendable {
    /// 1-based line number in the source file (header is line 1 for CSV).
    var lineNumber: Int
    var values: [String: String]
}

enum MetadataApplyParser {
    /// Detect format from extension and/or content sniffing.
    static func detectFormat(url: URL, data: Data) throws -> MetadataApplyFormat {
        let ext = url.pathExtension.lowercased()
        if ext == "csv" { return .csv }
        if ext == "jsonl" || ext == "json" { return .jsonl }

        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        let firstNonEmpty = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let sample = firstNonEmpty else { throw MetadataApplyDetectError.emptyFile }

        if sample.hasPrefix("{") { return .jsonl }
        // Header-like CSV: contains a comma and doesn't look like JSON
        if sample.contains(",") { return .csv }
        throw MetadataApplyDetectError.unrecognizedFormat
    }

    /// Parse the whole file into rows with keys already mapped to internal column ids.
    /// Unknown columns are omitted from row values but returned with sample cells for the import dialog.
    static func parse(
        data: Data,
        format: MetadataApplyFormat,
        customFields: [CustomMetadataFieldDefinition]
    ) throws -> (rows: [MetadataApplyRow], unknownColumns: [UnknownImportColumn], resolvedColumnIDs: Set<String>) {
        switch format {
        case .csv:
            return try parseCSV(data: data, customFields: customFields)
        case .jsonl:
            return try parseJSONL(data: data, customFields: customFields)
        }
    }

    // MARK: - CSV

    private static func parseCSV(
        data: Data,
        customFields: [CustomMetadataFieldDefinition]
    ) throws -> (rows: [MetadataApplyRow], unknownColumns: [UnknownImportColumn], resolvedColumnIDs: Set<String>) {
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        let records = CSVReader.splitRecords(text)
        guard let headerRecord = records.first, !headerRecord.isEmpty else {
            throw MetadataApplyDetectError.emptyFile
        }

        var unknownOrder: [String] = []
        var seenUnknown = Set<String>()
        var unknownIndexKeys: [Int: String] = [:] // column index → header key
        var unknownSamples: [String: [String]] = [:]
        var columnMap: [Int: String] = [:] // index → machine id
        var resolved = Set<String>()
        for (idx, header) in headerRecord.enumerated() {
            if let id = MetadataExportColumnRegistry.resolveIncomingColumnKey(header, customFields: customFields) {
                columnMap[idx] = id
                resolved.insert(id)
            } else {
                let key = header.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    unknownIndexKeys[idx] = key
                    if !seenUnknown.contains(key) {
                        seenUnknown.insert(key)
                        unknownOrder.append(key)
                        unknownSamples[key] = []
                    }
                }
            }
        }

        var rows: [MetadataApplyRow] = []
        for (offset, record) in records.dropFirst().enumerated() {
            let lineNumber = offset + 2 // header = line 1
            if record.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            var values: [String: String] = [:]
            for (idx, cell) in record.enumerated() {
                if let id = columnMap[idx] {
                    values[id] = cell
                } else if let key = unknownIndexKeys[idx] {
                    appendSample(cell, to: &unknownSamples, key: key)
                }
            }
            rows.append(MetadataApplyRow(lineNumber: lineNumber, values: values))
        }
        return (rows, makeUnknownColumns(order: unknownOrder, samples: unknownSamples), resolved)
    }

    // MARK: - JSONL

    private static func parseJSONL(
        data: Data,
        customFields: [CustomMetadataFieldDefinition]
    ) throws -> (rows: [MetadataApplyRow], unknownColumns: [UnknownImportColumn], resolvedColumnIDs: Set<String>) {
        var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var unknownOrder: [String] = []
        var seenUnknown = Set<String>()
        var unknownSamples: [String: [String]] = [:]
        var resolved = Set<String>()
        var rows: [MetadataApplyRow] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, lineSub) in lines.enumerated() {
            let lineNumber = idx + 1
            var line = String(lineSub)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            guard let lineData = trimmed.data(using: .utf8) else {
                throw MetadataApplyParseError.invalidJSONL(line: lineNumber, detail: "Could not decode line as UTF-8.")
            }
            let jsonObject: Any
            do {
                jsonObject = try JSONSerialization.jsonObject(with: lineData, options: [.fragmentsAllowed])
            } catch {
                let snippet = trimmed.count > 120 ? String(trimmed.prefix(117)) + "…" : trimmed
                throw MetadataApplyParseError.invalidJSONL(
                    line: lineNumber,
                    detail: "\(error.localizedDescription) Near: \(snippet)"
                )
            }
            guard let dict = jsonObject as? NSDictionary else {
                throw MetadataApplyParseError.invalidJSONL(
                    line: lineNumber,
                    detail: "Expected a JSON object {…}, got a different JSON value."
                )
            }

            var values: [String: String] = [:]
            for (keyAny, raw) in dict {
                guard let key = keyAny as? String else { continue }
                if raw is NSNull { continue }
                guard let id = MetadataExportColumnRegistry.resolveIncomingColumnKey(key, customFields: customFields) else {
                    if !seenUnknown.contains(key) {
                        seenUnknown.insert(key)
                        unknownOrder.append(key)
                        unknownSamples[key] = []
                    }
                    if let s = Self.jsonValueToApplyString(raw, columnId: "") {
                        appendSample(s, to: &unknownSamples, key: key)
                    }
                    continue
                }
                resolved.insert(id)
                if let s = Self.jsonValueToApplyString(raw, columnId: id) {
                    values[id] = s
                }
            }
            rows.append(MetadataApplyRow(lineNumber: lineNumber, values: values))
        }
        guard !rows.isEmpty else { throw MetadataApplyDetectError.emptyFile }
        return (rows, makeUnknownColumns(order: unknownOrder, samples: unknownSamples), resolved)
    }

    private static func appendSample(_ cell: String, to samples: inout [String: [String]], key: String) {
        let t = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = samples[key] ?? []
        guard list.count < MetadataImportTypeInference.maxSamplesPerColumn else { return }
        list.append(cell)
        samples[key] = list
    }

    private static func makeUnknownColumns(
        order: [String],
        samples: [String: [String]]
    ) -> [UnknownImportColumn] {
        order.map { key in
            let vals = samples[key] ?? []
            return UnknownImportColumn(
                key: key,
                sampleValues: vals,
                suggestedType: MetadataImportTypeInference.suggestType(samples: vals)
            )
        }
    }

    /// Convert a JSON value into the same string representation Apply diffs against.
    private static func jsonValueToApplyString(_ raw: Any, columnId: String) -> String? {
        if columnId == "tags" {
            if let arr = raw as? [Any] {
                let names = arr.compactMap { $0 as? String }
                return names.joined(separator: MetadataExportRowBuilder.tagsCSVSeparator)
            }
            if let s = raw as? String { return s }
            return nil
        }
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber {
            // Distinguish bool from number (NSNumber bridges both).
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            let d = n.doubleValue
            if d.rounded() == d, d >= Double(Int64.min), d <= Double(Int64.max) {
                return String(Int64(d))
            }
            return String(d)
        }
        if let b = raw as? Bool { return b ? "true" : "false" }
        return nil
    }
}

enum MetadataApplyParseError: LocalizedError, Equatable {
    case invalidJSONL(line: Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidJSONL(let line, let detail):
            return "Invalid JSON Lines on line \(line): \(detail)"
        }
    }
}

/// Minimal RFC 4180 CSV splitter (comma, quote doubling, CRLF/LF records).
enum CSVReader {
    static func splitRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(c)
                i += 1
                continue
            }
            switch c {
            case "\"":
                inQuotes = true
                i += 1
            case ",":
                fields.append(field)
                field = ""
                i += 1
            case "\r":
                fields.append(field)
                field = ""
                records.append(fields)
                fields = []
                i += 1
                if i < chars.count, chars[i] == "\n" { i += 1 }
            case "\n":
                fields.append(field)
                field = ""
                records.append(fields)
                fields = []
                i += 1
            default:
                field.append(c)
                i += 1
            }
        }
        // Trailing field / last record (if file doesn't end with newline)
        if inQuotes || !field.isEmpty || !fields.isEmpty {
            fields.append(field)
            records.append(fields)
        }
        return records
    }
}
