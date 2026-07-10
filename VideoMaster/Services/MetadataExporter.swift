import Foundation

/// RFC 4180 CSV encoding helpers shared by export and tests.
enum CSVWriter {
    /// Encode one field. Quotes when the value contains comma, quote, CR, or LF.
    static func escapeField(_ value: String) -> String {
        let needsQuoting =
            value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Join fields with commas and terminate with `\n`.
    static func line(fields: [String]) -> String {
        fields.map(escapeField).joined(separator: ",") + "\n"
    }

    /// UTF-8 BOM so Excel recognizes UTF-8.
    static var utf8BOM: Data { Data([0xEF, 0xBB, 0xBF]) }
}

enum JSONLWriter {
    /// Encode one object. Keys appear in `orderedKeys` order. Missing/null values are emitted as JSON null.
    static func line(
        orderedKeys: [String],
        values: [String: MetadataExportValue]
    ) throws -> String {
        var parts: [String] = []
        parts.reserveCapacity(orderedKeys.count)
        for key in orderedKeys {
            let keyJSON = encodeJSONString(key)
            let valueJSON = try encodeJSONValue(values[key] ?? .null)
            parts.append("\(keyJSON):\(valueJSON)")
        }
        return "{" + parts.joined(separator: ",") + "}\n"
    }

    /// JSON string literal via array wrap (JSONSerialization rejects bare String top-level).
    static func encodeJSONString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
        let arrayStr = String(data: data, encoding: .utf8)!
        // `["…"]` → drop surrounding `[` and `]` to leave a quoted JSON string.
        return String(arrayStr.dropFirst().dropLast())
    }

    private static func encodeJSONValue(_ value: MetadataExportValue) throws -> String {
        switch value {
        case .null:
            return "null"
        case .string(let s):
            return encodeJSONString(s)
        case .int(let n):
            return String(n)
        case .double(let d):
            // JSON forbids NaN / Infinity; emit null so Apply can round-trip the file.
            guard d.isFinite else { return "null" }
            return MetadataExportRowBuilder.formatDouble(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .stringList(let items):
            let data = try JSONSerialization.data(withJSONObject: items, options: [])
            guard let s = String(data: data, encoding: .utf8) else {
                throw MetadataExportError.encodingFailed
            }
            return s
        }
    }
}

enum MetadataExportError: LocalizedError {
    case encodingFailed
    case emptySelection
    case cancelled
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode export data."
        case .emptySelection: return "Nothing to export."
        case .cancelled: return "Export cancelled."
        case .writeFailed(let message): return message
        }
    }
}

/// Writes metadata for a list of videos to CSV or JSON Lines.
enum MetadataExporter {
    struct Request: Sendable {
        var videos: [Video]
        var orderedColumnIDs: [String]
        var columnsByID: [String: MetadataExportColumn]
        var format: MetadataExportFormat
        var context: MetadataExportContext
        var destinationURL: URL
    }

    /// Write the file. Call from a background task; `progress` is invoked on the cooperative thread.
    static func export(
        _ request: Request,
        progress: ((Int, Int) -> Void)? = nil
    ) throws {
        guard !request.videos.isEmpty else { throw MetadataExportError.emptySelection }
        guard !request.orderedColumnIDs.isEmpty else { throw MetadataExportError.emptySelection }

        switch request.format {
        case .csv:
            try writeCSV(request, progress: progress)
        case .jsonl:
            try writeJSONL(request, progress: progress)
        }
    }

    private static func writeCSV(
        _ request: Request,
        progress: ((Int, Int) -> Void)?
    ) throws {
        let headers = request.orderedColumnIDs.map { id in
            request.columnsByID[id]?.label ?? id
        }
        var data = CSVWriter.utf8BOM
        data.append(contentsOf: CSVWriter.line(fields: headers).utf8)

        let total = request.videos.count
        for (index, video) in request.videos.enumerated() {
            try Task.checkCancellation()
            let cells = request.orderedColumnIDs.map { id in
                let value = MetadataExportRowBuilder.value(columnId: id, video: video, context: request.context)
                return MetadataExportRowBuilder.csvCellString(value)
            }
            data.append(contentsOf: CSVWriter.line(fields: cells).utf8)
            if index % 50 == 0 || index + 1 == total {
                progress?(index + 1, total)
            }
        }
        try data.write(to: request.destinationURL, options: .atomic)
    }

    private static func writeJSONL(
        _ request: Request,
        progress: ((Int, Int) -> Void)?
    ) throws {
        let jsonKeys = MetadataExportColumnRegistry.jsonlKeys(
            forOrderedColumnIDs: request.orderedColumnIDs,
            columnsByID: request.columnsByID
        )
        var data = Data()
        let total = request.videos.count
        for (index, video) in request.videos.enumerated() {
            try Task.checkCancellation()
            var values: [String: MetadataExportValue] = [:]
            values.reserveCapacity(jsonKeys.count)
            for (columnId, jsonKey) in zip(request.orderedColumnIDs, jsonKeys) {
                values[jsonKey] = MetadataExportRowBuilder.value(
                    columnId: columnId,
                    video: video,
                    context: request.context
                )
            }
            let line = try JSONLWriter.line(orderedKeys: jsonKeys, values: values)
            data.append(contentsOf: line.utf8)
            if index % 50 == 0 || index + 1 == total {
                progress?(index + 1, total)
            }
        }
        try data.write(to: request.destinationURL, options: .atomic)
    }
}
