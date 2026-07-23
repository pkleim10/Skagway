import Foundation

/// Export file format chosen in the Export Metadata sheet.
enum MetadataExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case jsonl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .csv: return "CSV"
        case .jsonl: return "JSON Lines"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .jsonl: return "jsonl"
        }
    }

    var utTypeIdentifier: String {
        switch self {
        case .csv: return "public.comma-separated-values-text"
        case .jsonl: return "public.json"
        }
    }
}

/// How the export set was chosen — fixed by the entry point, not a sheet control.
enum MetadataExportScope: String, Sendable {
    case selection
    case filtered

    var summaryNoun: String {
        switch self {
        case .selection: return "selected"
        case .filtered: return "filtered"
        }
    }
}

/// Typed cell value produced by the row builder for both CSV and JSONL writers.
enum MetadataExportValue: Equatable, Sendable {
    case null
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    /// Tag names (and any future multi-value string lists).
    case stringList([String])
}

/// One exportable column: stable machine id + human label.
struct MetadataExportColumn: Identifiable, Equatable, Sendable {
    /// Stable id used for prefs and internal resolution (e.g. `filePath`, `custom:<uuid>`).
    /// JSONL object keys for custom fields prefer the human `label` when unique — see
    /// `MetadataExportColumnRegistry.jsonlKey(forColumnId:columnsByID:)`.
    let id: String
    let label: String
    /// Included in the default column set for new installs / reset.
    let defaultIncluded: Bool

    static func customFieldId(_ uuid: UUID) -> String { "custom:\(uuid.uuidString)" }

    static func customFieldUUID(fromColumnId id: String) -> UUID? {
        guard id.hasPrefix("custom:") else { return nil }
        return UUID(uuidString: String(id.dropFirst("custom:".count)))
    }
}

/// How an export column relates to Import Metadata (round-trip).
enum MetadataExportColumnKind: Int, CaseIterable, Comparable, Sendable {
    /// Path / Content Fingerprint — used to find videos; not written.
    case matchKey = 0
    /// Rating, Tags, custom fields — written by Import Metadata.
    case importable = 1
    /// Size, duration, codec, … — informational; Import Metadata ignores.
    case exportOnly = 2

    var title: String {
        switch self {
        case .matchKey: return "Match keys"
        case .importable: return "Importable"
        case .exportOnly: return "Export only"
        }
    }

    var caption: String {
        switch self {
        case .matchKey: return "Used to find videos when applying this file."
        case .importable: return "Written back by Import Metadata."
        case .exportOnly: return "Informational; Import Metadata ignores these columns."
        }
    }

    static func < (lhs: MetadataExportColumnKind, rhs: MetadataExportColumnKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum MetadataExportColumnRegistry {
    /// Built-in columns in catalog order (not necessarily export order).
    static let builtins: [MetadataExportColumn] = [
        .init(id: "filePath", label: "Path", defaultIncluded: true),
        .init(id: "fileName", label: "Name", defaultIncluded: true),
        .init(id: "id", label: "Database ID", defaultIncluded: false),
        .init(id: "fileExtension", label: "Extension", defaultIncluded: false),
        .init(id: "parentFolder", label: "Parent Folder", defaultIncluded: false),
        .init(id: "volume", label: "Volume", defaultIncluded: false),
        .init(id: "fileSize", label: "File Size (bytes)", defaultIncluded: true),
        .init(id: "duration", label: "Duration (seconds)", defaultIncluded: true),
        .init(id: "width", label: "Width", defaultIncluded: true),
        .init(id: "height", label: "Height", defaultIncluded: true),
        .init(id: "resolution", label: "Resolution", defaultIncluded: false),
        .init(id: "quality", label: "Quality", defaultIncluded: true),
        .init(id: "codec", label: "Codec", defaultIncluded: false),
        .init(id: "frameRate", label: "Frame Rate", defaultIncluded: false),
        .init(id: "creationDate", label: "Date Created", defaultIncluded: false),
        .init(id: "dateAdded", label: "Date Imported", defaultIncluded: true),
        .init(id: "rating", label: "Rating", defaultIncluded: true),
        .init(id: "tags", label: "Tags", defaultIncluded: true),
        .init(id: "playCount", label: "Plays", defaultIncluded: true),
        .init(id: "lastPlayed", label: "Last Played", defaultIncluded: false),
        .init(id: "hasSubtitles", label: "Subtitles", defaultIncluded: false),
        .init(id: "contentFingerprint", label: "Content Fingerprint", defaultIncluded: false),
        .init(id: "resumePositionSeconds", label: "Resume Position (seconds)", defaultIncluded: false),
        .init(id: "isCorrupt", label: "Corrupt", defaultIncluded: false),
        .init(id: "isMissing", label: "Missing File", defaultIncluded: false),
        .init(id: "isDuplicate", label: "Duplicate", defaultIncluded: false),
        .init(id: "dateConverted", label: "Date Converted", defaultIncluded: false),
        .init(id: "thumbnailPath", label: "Thumbnail Cache Path", defaultIncluded: false),
    ]

    static var builtinIDs: Set<String> { Set(builtins.map(\.id)) }

    /// Columns Apply can write in v1.
    static let writableColumnIDs: Set<String> = ["rating", "tags"]

    static func isWritableColumnID(_ id: String) -> Bool {
        if writableColumnIDs.contains(id) { return true }
        return MetadataExportColumn.customFieldUUID(fromColumnId: id) != nil
    }

    static func isMatchKeyColumnID(_ id: String) -> Bool {
        id == "filePath" || id == "contentFingerprint"
    }

    static func kind(forColumnID id: String) -> MetadataExportColumnKind {
        if isMatchKeyColumnID(id) { return .matchKey }
        if isWritableColumnID(id) { return .importable }
        return .exportOnly
    }

    /// Reorder `ids` into Match keys → Importable → Export only, preserving relative order within each.
    static func rebucketByKind(_ ids: [String]) -> [String] {
        var buckets: [MetadataExportColumnKind: [String]] = [
            .matchKey: [], .importable: [], .exportOnly: []
        ]
        for id in ids {
            buckets[kind(forColumnID: id), default: []].append(id)
        }
        return MetadataExportColumnKind.allCases.flatMap { buckets[$0] ?? [] }
    }

    /// Within each kind section, put included ids first (relative order preserved).
    static func pinCheckedWithinSections(order: [String], includedIDs: Set<String>) -> [String] {
        MetadataExportColumnKind.allCases.flatMap { sectionKind in
            let section = order.filter { kind(forColumnID: $0) == sectionKind }
            let checked = section.filter { includedIDs.contains($0) }
            let unchecked = section.filter { !includedIDs.contains($0) }
            return checked + unchecked
        }
    }

    static func defaultOrderedColumnIDs(customFields: [CustomMetadataFieldDefinition]) -> [String] {
        let builtinDefaults = builtins.filter(\.defaultIncluded).map(\.id)
        let custom = customFields
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { MetadataExportColumn.customFieldId($0.id) }
        return rebucketByKind(builtinDefaults + custom)
    }

    /// Full list order for the picker: sectioned by kind; within each section, default-included first.
    static func defaultFullListOrder(customFields: [CustomMetadataFieldDefinition]) -> [String] {
        let all = allColumns(customFields: customFields).map(\.id)
        let includedDefaults = Set(allColumns(customFields: customFields).filter(\.defaultIncluded).map(\.id))
        let sectioned = rebucketByKind(all)
        return pinCheckedWithinSections(order: sectioned, includedIDs: includedDefaults)
    }

    static func defaultIncludedIDs(customFields: [CustomMetadataFieldDefinition]) -> Set<String> {
        Set(allColumns(customFields: customFields).filter(\.defaultIncluded).map(\.id))
    }

    /// All columns available for the picker: builtins + current custom field definitions.
    static func allColumns(customFields: [CustomMetadataFieldDefinition]) -> [MetadataExportColumn] {
        let customCols = customFields
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                MetadataExportColumn(
                    id: MetadataExportColumn.customFieldId($0.id),
                    label: $0.name,
                    defaultIncluded: true
                )
            }
        return builtins + customCols
    }

    /// Sanitize a persisted ordered id list against the current catalog; append any new columns;
    /// re-bucket into Match keys → Importable → Export only.
    static func sanitizeFullListOrder(_ ids: [String], customFields: [CustomMetadataFieldDefinition]) -> [String] {
        let known = allColumns(customFields: customFields).map(\.id)
        let knownSet = Set(known)
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where knownSet.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        for id in known where !seen.contains(id) {
            result.append(id)
        }
        return rebucketByKind(result)
    }

    static func sanitizeIncludedIDs(_ ids: [String], customFields: [CustomMetadataFieldDefinition]) -> Set<String> {
        let known = Set(allColumns(customFields: customFields).map(\.id))
        return Set(ids).intersection(known)
    }

    /// Sanitize a persisted ordered id list against the current catalog (included-only lists).
    static func sanitizeOrderedIDs(_ ids: [String], customFields: [CustomMetadataFieldDefinition]) -> [String] {
        let known = Set(allColumns(customFields: customFields).map(\.id))
        var seen = Set<String>()
        var result: [String] = []
        for id in ids where known.contains(id) && !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return rebucketByKind(result)
    }

    /// JSONL object key for a column.
    /// - Built-ins: stable machine id (`filePath`, `rating`, …).
    /// - Custom fields: human display name when it is unique (case-insensitive) among custom
    ///   fields **and** does not collide with a built-in id; otherwise `custom:<uuid>`.
    static func jsonlKey(
        forColumnId columnId: String,
        columnsByID: [String: MetadataExportColumn]
    ) -> String {
        guard let column = columnsByID[columnId] else { return columnId }
        guard MetadataExportColumn.customFieldUUID(fromColumnId: columnId) != nil else {
            return columnId
        }
        let name = column.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return columnId }

        let nameKey = name.lowercased()
        if builtinIDs.contains(name) || builtinIDs.contains(where: { $0.lowercased() == nameKey }) {
            return columnId
        }

        let customColumns = columnsByID.values.filter {
            MetadataExportColumn.customFieldUUID(fromColumnId: $0.id) != nil
        }
        let sameNameCount = customColumns.filter {
            $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == nameKey
        }.count
        guard sameNameCount == 1 else { return columnId }
        return name
    }

    /// Map ordered internal column ids → JSONL keys (same length / order).
    static func jsonlKeys(
        forOrderedColumnIDs ids: [String],
        columnsByID: [String: MetadataExportColumn]
    ) -> [String] {
        ids.map { jsonlKey(forColumnId: $0, columnsByID: columnsByID) }
    }

    /// Resolve a CSV header or JSONL object key to an internal column id.
    /// - Built-in machine ids and human labels map to builtins.
    /// - Custom: `custom:<uuid>`, or unique case-insensitive field name.
    /// - Unknown → nil (Apply skips).
    static func resolveIncomingColumnKey(
        _ key: String,
        customFields: [CustomMetadataFieldDefinition]
    ) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if builtinIDs.contains(trimmed) { return trimmed }

        let lower = trimmed.lowercased()
        for col in builtins {
            if col.label.lowercased() == lower { return col.id }
        }

        if let uuid = MetadataExportColumn.customFieldUUID(fromColumnId: trimmed),
           customFields.contains(where: { $0.id == uuid })
        {
            return MetadataExportColumn.customFieldId(uuid)
        }

        let nameMatches = customFields.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower
        }
        if nameMatches.count == 1 {
            return MetadataExportColumn.customFieldId(nameMatches[0].id)
        }
        return nil
    }
}

/// Snapshot of library state needed to resolve one video’s export row.
struct MetadataExportContext: Sendable {
    var tagsByVideoId: [Int64: [Tag]]
    var customValuesByVideoId: [Int64: [UUID: String]]
    var customFieldDefinitions: [UUID: CustomMetadataFieldDefinition]
    var missingVideoIds: Set<String>
    var duplicateVideoIds: Set<String>
    /// `filePath` → completed conversion date (most recent if multiple).
    var convertedDatesByPath: [String: Date]
    var thumbnailsSettled: Bool

    func tags(for video: Video) -> [Tag] {
        guard let id = video.databaseId else { return [] }
        return tagsByVideoId[id] ?? []
    }

    func customValues(for video: Video) -> [UUID: String] {
        guard let id = video.databaseId else { return [:] }
        return customValuesByVideoId[id] ?? [:]
    }
}

enum MetadataExportRowBuilder {
    static let tagsCSVSeparator = "|"

    private static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func value(
        columnId: String,
        video: Video,
        context: MetadataExportContext
    ) -> MetadataExportValue {
        if let customUUID = MetadataExportColumn.customFieldUUID(fromColumnId: columnId) {
            return customValue(fieldId: customUUID, video: video, context: context)
        }
        switch columnId {
        case "filePath": return .string(video.filePath)
        case "fileName": return .string(video.fileName)
        case "id":
            if let id = video.databaseId { return .int(id) }
            return .null
        case "fileExtension":
            return .string((video.filePath as NSString).pathExtension)
        case "parentFolder":
            let parent = ((video.filePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return .string(parent)
        case "volume":
            let comps = (video.filePath as NSString).pathComponents
            let vol = comps.count >= 3 && comps[0] == "/" && comps[1] == "Volumes" ? comps[2] : "/"
            return .string(vol)
        case "fileSize": return .int(video.fileSize)
        case "duration":
            if let d = video.duration { return .double(d) }
            return .null
        case "width":
            if let w = video.width { return .int(Int64(w)) }
            return .null
        case "height":
            if let h = video.height { return .int(Int64(h)) }
            return .null
        case "resolution":
            if let r = video.resolution { return .string(r) }
            return .null
        case "quality":
            if let q = video.resolutionLabel { return .string(q) }
            return .null
        case "codec":
            if let c = video.codec { return .string(c) }
            return .null
        case "frameRate":
            if let f = video.frameRate { return .double(f) }
            return .null
        case "creationDate":
            if let d = video.creationDate { return .string(isoDateTime.string(from: d)) }
            return .null
        case "dateAdded":
            return .string(isoDateTime.string(from: video.dateAdded))
        case "rating": return .int(Int64(video.rating))
        case "tags":
            let names = context.tags(for: video).map(\.name)
                .map { $0.replacingOccurrences(of: tagsCSVSeparator, with: "") }
            return .stringList(names)
        case "playCount": return .int(Int64(video.playCount))
        case "lastPlayed":
            if let d = video.lastPlayed { return .string(isoDateTime.string(from: d)) }
            return .null
        case "hasSubtitles": return .bool(video.hasSubtitles)
        case "contentFingerprint":
            if let fp = video.contentFingerprint { return .string(fp) }
            return .null
        case "resumePositionSeconds":
            if let s = PlaybackPositionStore.loadSeconds(filePath: video.filePath) {
                return .double(s)
            }
            return .null
        case "isCorrupt":
            return .bool(isCorrupt(video, thumbnailsSettled: context.thumbnailsSettled))
        case "isMissing":
            return .bool(context.missingVideoIds.contains(video.id))
        case "isDuplicate":
            return .bool(context.duplicateVideoIds.contains(video.id))
        case "dateConverted":
            if let d = context.convertedDatesByPath[video.filePath] {
                return .string(isoDateTime.string(from: d))
            }
            return .null
        case "thumbnailPath":
            if let p = video.thumbnailPath {
                // Strip cache-busting `#timestamp` suffix for a cleaner export.
                let bare = p.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? p
                return .string(bare)
            }
            return .null
        default:
            return .null
        }
    }

    private static func customValue(
        fieldId: UUID,
        video: Video,
        context: MetadataExportContext
    ) -> MetadataExportValue {
        let raw = context.customValues(for: video)[fieldId] ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .null }
        guard let def = context.customFieldDefinitions[fieldId] else {
            return .string(raw)
        }
        switch def.valueType {
        case .string, .text:
            return .string(raw)
        case .number:
            if let d = Double(trimmed) { return .double(d) }
            return .string(raw)
        case .boolean:
            if let canon = CustomMetadataValueType.normalizeBooleanStorage(trimmed) {
                return .bool(canon == "true")
            }
            return .string(raw)
        case .date, .dateTime:
            // Preserve stored canonical strings (yyyy-MM-dd / ISO8601).
            return .string(trimmed)
        }
    }

    private static func isCorrupt(_ video: Video, thumbnailsSettled: Bool) -> Bool {
        video.duration == nil && video.width == nil && video.height == nil
            || (thumbnailsSettled && video.thumbnailPath == nil)
    }

    /// CSV cell string for a value (null → empty).
    static func csvCellString(_ value: MetadataExportValue) -> String {
        switch value {
        case .null: return ""
        case .string(let s): return s
        case .int(let n): return String(n)
        case .double(let d): return Self.formatDouble(d)
        case .bool(let b): return b ? "true" : "false"
        case .stringList(let items):
            return items.joined(separator: tagsCSVSeparator)
        }
    }

    static func formatDouble(_ d: Double) -> String {
        guard d.isFinite else { return "" }
        if d.rounded() == d, d >= Double(Int64.min), d <= Double(Int64.max) {
            return String(Int64(d))
        }
        return String(d)
    }
}
