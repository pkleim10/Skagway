import Foundation

// MARK: - Tokens

enum BulkRenameTokenSection: String, CaseIterable, Identifiable, Sendable {
    case special
    case identity
    case media
    case library
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .special: return "Special"
        case .identity: return "Identity"
        case .media: return "Media"
        case .library: return "Library"
        case .custom: return "Custom"
        }
    }
}

/// One insertable token in the Bulk Rename field browser.
struct BulkRenameToken: Identifiable, Equatable, Sendable {
    /// Stable id used for value lookup (`title`, `durationFriendly`, `custom:…`).
    let id: String
    /// Human label in the field list.
    let label: String
    /// Text inserted into the pattern, e.g. `{Title}`.
    let insertText: String
    let section: BulkRenameTokenSection
}

enum BulkRenameTokenCatalog {
    /// Default pattern shown when the sheet opens (or when prefs are empty).
    static let defaultPattern = "{Title}.{Extension}"

    static func tokens(customFields: [CustomMetadataFieldDefinition]) -> [BulkRenameToken] {
        var list: [BulkRenameToken] = [
            .init(id: "inc", label: "Increment", insertText: "{Inc 1}", section: .special),
            .init(id: "conflict", label: "Conflict", insertText: "{Conflict -1}", section: .special),
            .init(id: "stem", label: "Stem", insertText: "{Stem}", section: .special),
            .init(id: "nowDate", label: "Date (now)", insertText: "{Date yyyy-MM-dd}", section: .special),
            .init(id: "uuid8", label: "UUID8", insertText: "{UUID8}", section: .special),

            .init(id: "title", label: "Title", insertText: "{Title}", section: .identity),
            .init(id: "fileName", label: "File Name", insertText: "{File Name}", section: .identity),
            .init(id: "originalFileName", label: "Original File Name", insertText: "{Original File Name}", section: .identity),
            .init(id: "fileExtension", label: "Extension", insertText: "{Extension}", section: .identity),
            .init(id: "parentFolder", label: "Parent Folder", insertText: "{Parent Folder}", section: .identity),
            .init(id: "volume", label: "Volume", insertText: "{Volume}", section: .identity),
            .init(id: "filePath", label: "Path", insertText: "{Path}", section: .identity),
            .init(id: "id", label: "Database ID", insertText: "{Database ID}", section: .identity),

            .init(id: "durationFriendly", label: "Duration", insertText: "{Duration}", section: .media),
            .init(id: "width", label: "Width", insertText: "{Width}", section: .media),
            .init(id: "height", label: "Height", insertText: "{Height}", section: .media),
            .init(id: "resolution", label: "Resolution", insertText: "{Resolution}", section: .media),
            .init(id: "quality", label: "Quality", insertText: "{Quality}", section: .media),
            .init(id: "codec", label: "Codec", insertText: "{Codec}", section: .media),
            .init(id: "frameRate", label: "Frame Rate", insertText: "{Frame Rate}", section: .media),
            .init(id: "fileSize", label: "File Size (bytes)", insertText: "{File Size}", section: .media),
            .init(id: "hasSubtitles", label: "Subtitles", insertText: "{Subtitles}", section: .media),

            .init(id: "rating", label: "Rating", insertText: "{Rating}", section: .library),
            .init(id: "tags", label: "Tags", insertText: "{Tags}", section: .library),
            .init(id: "playCount", label: "Plays", insertText: "{Plays}", section: .library),
            .init(id: "dateAdded", label: "Date Imported", insertText: "{Date Imported}", section: .library),
            .init(id: "creationDate", label: "Date Created", insertText: "{Date Created}", section: .library),
            .init(id: "lastPlayed", label: "Last Played", insertText: "{Last Played}", section: .library),
            .init(id: "contentFingerprint", label: "Content Fingerprint", insertText: "{Content Fingerprint}", section: .library),
            .init(id: "resumePositionSeconds", label: "Resume Position", insertText: "{Resume Position}", section: .library),
            .init(id: "isCorrupt", label: "Corrupt", insertText: "{Corrupt}", section: .library),
            .init(id: "isMissing", label: "Missing File", insertText: "{Missing File}", section: .library),
            .init(id: "isDuplicate", label: "Duplicate", insertText: "{Duplicate}", section: .library),
            .init(id: "dateConverted", label: "Date Converted", insertText: "{Date Converted}", section: .library),
        ]

        let sortedCustom = customFields.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        for field in sortedCustom {
            let columnId = MetadataExportColumn.customFieldId(field.id)
            list.append(
                .init(
                    id: columnId,
                    label: field.name,
                    insertText: "{\(field.name)}",
                    section: .custom
                )
            )
        }
        return list
    }

    /// Maps brace field names (e.g. `Title`, `Date Created`, `DateCreated`) → token id.
    static func lookupMap(tokens: [BulkRenameToken]) -> [String: String] {
        var map: [String: String] = [:]
        for token in tokens {
            map[token.id] = token.id
            let inside = String(token.insertText.dropFirst().dropLast())
            // Strip optional format example from insert text (e.g. `{Date yyyy-MM-dd}`).
            let fieldPart: String
            if token.id == "nowDate" {
                fieldPart = "Date"
            } else {
                fieldPart = inside
            }
            map[fieldPart] = token.id
            map[fieldPart.lowercased()] = token.id
            switch token.id {
            case "fileExtension":
                map["ext"] = token.id
                map["extension"] = token.id
            case "durationFriendly":
                map["duration"] = token.id
                map["Duration"] = token.id
            case "fileSize":
                map["File Size (bytes)"] = token.id
            case "playCount":
                map["Play Count"] = token.id
            case "creationDate":
                map["DateCreated"] = token.id
                map["datecreated"] = token.id
            case "dateAdded":
                map["DateImported"] = token.id
                map["dateimported"] = token.id
            case "dateConverted":
                map["DateConverted"] = token.id
                map["dateconverted"] = token.id
            case "lastPlayed":
                map["LastPlayed"] = token.id
                map["lastplayed"] = token.id
            case "fileName":
                map["FileName"] = token.id
                map["filename"] = token.id
            case "originalFileName":
                map["OriginalFileName"] = token.id
                map["originalfilename"] = token.id
            case "parentFolder":
                map["ParentFolder"] = token.id
                map["parentfolder"] = token.id
                map["Parent"] = token.id
                map["parent"] = token.id
            case "stem":
                map["Stem"] = token.id
            case "uuid8":
                map["UUID8"] = token.id
                map["uuid8"] = token.id
            default:
                break
            }
        }
        // Legacy duration component keys (still parse if typed).
        map["Duration.Hours"] = "duration.hours"
        map["duration.hours"] = "duration.hours"
        map["Duration.Minutes"] = "duration.minutes"
        map["duration.minutes"] = "duration.minutes"
        map["Duration.Seconds"] = "duration.seconds"
        map["duration.seconds"] = "duration.seconds"
        // Ensure friendly duration wins for bare Duration.
        map["Duration"] = "durationFriendly"
        map["duration"] = "durationFriendly"
        return map
    }

    /// Field names sorted longest-first for prefix matching with optional args.
    static func matchKeys(from tokenIdByKey: [String: String]) -> [String] {
        Array(Set(tokenIdByKey.keys)).sorted { $0.count > $1.count }
    }
}

// MARK: - Case transform

enum BulkRenameCaseTransform: Equatable, Sendable {
    case lower
    case upper
    /// Title Case — capitalize the first letter of each word (`The Quick Brown Fox`).
    case title
    /// Name case — capitalize only the first letter (`The quick brown fox`).
    case name

    static func parseKeyword(_ word: String) -> BulkRenameCaseTransform? {
        switch word {
        case "L", "l": return .lower
        case "U", "u": return .upper
        case "T", "t": return .title
        case "N", "n": return .name
        default:
            break
        }
        switch word.lowercased() {
        case "lower": return .lower
        case "upper": return .upper
        case "title": return .title
        case "name": return .name
        default: return nil
        }
    }

    func apply(_ string: String) -> String {
        switch self {
        case .lower: return string.lowercased()
        case .upper: return string.uppercased()
        case .title: return string.localizedCapitalized
        case .name:
            let lower = string.lowercased()
            guard let first = lower.first else { return lower }
            return String(first).uppercased() + lower.dropFirst()
        }
    }
}

// MARK: - Numbered specials ({Inc …}, {Conflict …})

/// Zero-padded counter format parsed from `{Inc 015}` or the numeric tail of `{Conflict -01}`.
struct BulkRenameNumberFormat: Equatable, Sendable {
    let start: Int
    /// Minimum width from the digit run in the pattern (`015` → 3).
    let width: Int

    func string(forOffset offset: Int) -> String {
        let value = start + offset
        return String(format: "%0\(max(width, 1))d", value)
    }
}

/// `{Conflict -1}` / `{Conflict :01}` — prefix + numbered format; empty when not needed.
struct BulkRenameConflictFormat: Equatable, Sendable {
    let prefix: String
    let number: BulkRenameNumberFormat

    func string(forConflictIndex index: Int) -> String {
        prefix + number.string(forOffset: index)
    }
}

enum BulkRenameSpecialParser {
    /// `{Inc 0}` / `{Inc 015}` — first Inc token in the pattern wins.
    static func parseInc(from pattern: String) -> BulkRenameNumberFormat? {
        for key in braceContents(in: pattern) {
            if let format = parseIncKey(key) { return format }
        }
        return nil
    }

    /// `{Conflict -1}` / `{Conflict :01}` — first Conflict token wins.
    static func parseConflict(from pattern: String) -> BulkRenameConflictFormat? {
        for key in braceContents(in: pattern) {
            if let format = parseConflictKey(key) { return format }
        }
        return nil
    }

    static func parseIncKey(_ key: String) -> BulkRenameNumberFormat? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rest = stripPrefix(trimmed, "Inc") else { return nil }
        let digits = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
              let start = Int(digits)
        else { return nil }
        return BulkRenameNumberFormat(start: start, width: digits.count)
    }

    static func parseConflictKey(_ key: String) -> BulkRenameConflictFormat? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rest = stripPrefix(trimmed, "Conflict") else { return nil }
        let body = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        guard let digitStart = body.lastIndex(where: { !$0.isNumber }).map({ body.index(after: $0) })
                ?? (body.first?.isNumber == true ? body.startIndex : nil),
              digitStart < body.endIndex
        else { return nil }

        let prefix = String(body[..<digitStart])
        let digits = String(body[digitStart...])
        guard !digits.isEmpty, let start = Int(digits) else { return nil }
        return BulkRenameConflictFormat(
            prefix: prefix,
            number: BulkRenameNumberFormat(start: start, width: digits.count)
        )
    }

    private static func stripPrefix(_ text: String, _ word: String) -> String? {
        guard text.count >= word.count else { return nil }
        let start = text.prefix(word.count)
        guard start.lowercased() == word.lowercased() else { return nil }
        return String(text.dropFirst(word.count))
    }

    private static func braceContents(in pattern: String) -> [String] {
        let ns = pattern as NSString
        let regex = BulkRenameTemplate.tokenRegex
        let full = NSRange(location: 0, length: ns.length)
        var keys: [String] = []
        regex.enumerateMatches(in: pattern, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            keys.append(ns.substring(with: match.range(at: 1)))
        }
        return keys
    }
}

// MARK: - Token parse (field + optional format + case)

enum BulkRenameParsedToken: Equatable, Sendable {
    case inc(BulkRenameNumberFormat)
    case conflict(BulkRenameConflictFormat)
    case uuid8
    case stem(caseTransform: BulkRenameCaseTransform?)
    case nowDate(format: String?, caseTransform: BulkRenameCaseTransform?)
    case field(tokenId: String, format: String?, caseTransform: BulkRenameCaseTransform?)
    case unknown
}

enum BulkRenameTokenParser {
    static func parse(key: String, tokenIdByKey: [String: String]) -> BulkRenameParsedToken {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inc = BulkRenameSpecialParser.parseIncKey(trimmed) {
            return .inc(inc)
        }
        if let conflict = BulkRenameSpecialParser.parseConflictKey(trimmed) {
            return .conflict(conflict)
        }

        let keys = BulkRenameTokenCatalog.matchKeys(from: tokenIdByKey)
        guard let match = matchField(trimmed, keys: keys, tokenIdByKey: tokenIdByKey) else {
            return .unknown
        }

        let (format, caseTransform) = peelArgs(match.rest)
        switch match.tokenId {
        case "uuid8":
            return .uuid8
        case "stem":
            return .stem(caseTransform: caseTransform)
        case "nowDate":
            return .nowDate(format: format, caseTransform: caseTransform)
        default:
            return .field(tokenId: match.tokenId, format: format, caseTransform: caseTransform)
        }
    }

    private struct FieldMatch {
        let tokenId: String
        let rest: String
    }

    private static func matchField(
        _ key: String,
        keys: [String],
        tokenIdByKey: [String: String]
    ) -> FieldMatch? {
        for candidate in keys {
            if key == candidate {
                guard let id = tokenIdByKey[candidate] else { continue }
                return FieldMatch(tokenId: id, rest: "")
            }
            let prefix = candidate + " "
            if key.hasPrefix(prefix) {
                guard let id = tokenIdByKey[candidate] else { continue }
                return FieldMatch(tokenId: id, rest: String(key.dropFirst(prefix.count)))
            }
            // Case-insensitive field name match (preserve rest casing for format strings).
            if key.lowercased() == candidate.lowercased() {
                guard let id = tokenIdByKey[candidate] else { continue }
                return FieldMatch(tokenId: id, rest: "")
            }
            let lowerPrefix = candidate.lowercased() + " "
            let lowerKey = key.lowercased()
            if lowerKey.hasPrefix(lowerPrefix) {
                guard let id = tokenIdByKey[candidate] else { continue }
                let restStart = key.index(key.startIndex, offsetBy: prefix.count)
                return FieldMatch(tokenId: id, rest: String(key[restStart...]))
            }
        }
        return nil
    }

    /// Peel optional trailing case keyword; remainder is the format string.
    static func peelArgs(_ rest: String) -> (format: String?, caseTransform: BulkRenameCaseTransform?) {
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let last = parts.last, let transform = BulkRenameCaseTransform.parseKeyword(last) else {
            return (trimmed, nil)
        }
        let formatParts = parts.dropLast()
        let format = formatParts.isEmpty ? nil : formatParts.joined(separator: " ")
        return (format, transform)
    }
}

// MARK: - Template

enum BulkRenameTemplate {
    fileprivate static let tokenRegex = try! NSRegularExpression(pattern: #"\{([^{}]+)\}"#, options: [])

    private static let dateFormatterCache = NSCache<NSString, DateFormatter>()

    struct RenderExtras: Equatable, Sendable {
        /// 0-based index in the bulk set — drives `{Inc …}`.
        var sequenceIndex: Int = 0
        /// `nil` → `{Conflict …}` expands to empty; `0` → first conflict number.
        var conflictIndex: Int? = nil
    }

    /// Substitutes `{…}` tokens; leaves unknown tokens unchanged.
    static func render(
        pattern: String,
        video: Video,
        context: MetadataExportContext,
        tokenIdByKey: [String: String],
        extras: RenderExtras = RenderExtras()
    ) -> String {
        let ns = pattern as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result = ""
        var cursor = 0

        tokenRegex.enumerateMatches(in: pattern, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2 else { return }
            let outer = match.range(at: 0)
            let inner = match.range(at: 1)
            if outer.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: outer.location - cursor))
            }
            let key = ns.substring(with: inner)
            let parsed = BulkRenameTokenParser.parse(key: key, tokenIdByKey: tokenIdByKey)
            switch parsed {
            case .inc(let format):
                result += format.string(forOffset: extras.sequenceIndex)
            case .conflict(let format):
                if let idx = extras.conflictIndex {
                    result += sanitizeComponent(format.string(forConflictIndex: idx))
                }
            case .uuid8:
                let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                result += String(hex.prefix(8))
            case .stem(let caseTransform):
                var text = (video.fileName as NSString).deletingPathExtension
                if let caseTransform { text = caseTransform.apply(text) }
                result += sanitizeComponent(text)
            case .nowDate(let format, let caseTransform):
                var text = formatDate(Date(), format: format)
                if let caseTransform { text = caseTransform.apply(text) }
                result += sanitizeComponent(text)
            case .field(let tokenId, let format, let caseTransform):
                var text = value(tokenId: tokenId, format: format, video: video, context: context)
                if let caseTransform { text = caseTransform.apply(text) }
                result += sanitizeComponent(text)
            case .unknown:
                result += ns.substring(with: outer)
            }
            cursor = outer.location + outer.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return sanitizeFilename(result)
    }

    static func value(
        tokenId: String,
        format: String? = nil,
        video: Video,
        context: MetadataExportContext
    ) -> String {
        switch tokenId {
        case "durationFriendly":
            guard let d = video.duration else { return "" }
            return formatDuration(d, format: format)
        case "duration.hours":
            guard let d = video.duration else { return "" }
            return String(Int(d) / 3600)
        case "duration.minutes":
            guard let d = video.duration else { return "" }
            return String((Int(d) % 3600) / 60)
        case "duration.seconds":
            guard let d = video.duration else { return "" }
            return String(Int(d) % 60)
        case "stem":
            return (video.fileName as NSString).deletingPathExtension
        case "uuid8", "inc", "conflict", "nowDate":
            return ""
        case "creationDate":
            guard let d = video.creationDate else { return "" }
            return formatDate(d, format: format)
        case "dateAdded":
            return formatDate(video.dateAdded, format: format)
        case "lastPlayed":
            guard let d = video.lastPlayed else { return "" }
            return formatDate(d, format: format)
        case "dateConverted":
            guard let d = context.convertedDatesByPath[video.filePath] else { return "" }
            return formatDate(d, format: format)
        default:
            if let customUUID = MetadataExportColumn.customFieldUUID(fromColumnId: tokenId),
               let def = context.customFieldDefinitions[customUUID],
               def.valueType == .date || def.valueType == .dateTime
            {
                let raw = context.customValues(for: video)[customUUID] ?? ""
                if let date = parseFlexibleDate(raw) {
                    return formatDate(date, format: format)
                }
            }
            let exportValue = MetadataExportRowBuilder.value(
                columnId: tokenId,
                video: video,
                context: context
            )
            return MetadataExportRowBuilder.csvCellString(exportValue)
        }
    }

    /// Duration formatting: bare → `1h02m03s`; `mmm` → total minutes; `sss` → total seconds; `hhh` → total hours.
    static func formatDuration(_ seconds: Double, format: String?) -> String {
        let total = max(0, Int(seconds))
        guard let format, !format.isEmpty else {
            return filenameFriendlyDuration(seconds)
        }
        switch format.lowercased() {
        case "mmm":
            return String(total / 60)
        case "sss":
            return String(total)
        case "hhh":
            return String(total / 3600)
        case "h", "hh":
            return String(total / 3600)
        case "m", "mm":
            return String((total % 3600) / 60)
        case "s", "ss":
            return String(total % 60)
        default:
            // Unknown duration format — treat as friendly fallback.
            return filenameFriendlyDuration(seconds)
        }
    }

    static func formatDate(_ date: Date, format: String?) -> String {
        let pattern = {
            guard let format, !format.isEmpty else { return "yyyy-MM-dd" }
            return format
        }()
        return dateFormatter(for: pattern).string(from: date)
    }

    private static func dateFormatter(for pattern: String) -> DateFormatter {
        let key = pattern as NSString
        if let cached = dateFormatterCache.object(forKey: key) {
            return cached
        }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = pattern
        dateFormatterCache.setObject(f, forKey: key)
        return f
    }

    private static func parseFlexibleDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: trimmed) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0)
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: trimmed)
    }

    /// `1h02m03s` / `12m34s` / `45s` — safe for filenames (no colons).
    static func filenameFriendlyDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh%02dm%02ds", h, m, s)
        }
        if m > 0 {
            return String(format: "%dm%02ds", m, s)
        }
        return String(format: "%ds", s)
    }

    /// Sanitize a single substituted field value (not the whole filename).
    static func sanitizeComponent(_ raw: String) -> String {
        var s = raw
        let replacements: [(String, String)] = [
            ("/", "-"), ("\\", "-"), (":", "-"), ("\0", ""),
            ("×", "x"), ("*", "-"), ("?", ""), ("\"", "'"),
            ("<", ""), (">", ""), ("|", "-"),
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sanitize the full assembled filename.
    static func sanitizeFilename(_ raw: String) -> String {
        var s = sanitizeComponent(raw)
        s = s.replacingOccurrences(of: "/", with: "-")
        while s.hasPrefix(".") { s = String(s.dropFirst()) }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.utf8.count > 255 {
            s = truncateUTF8(s, maxBytes: 255)
        }
        return s
    }

    private static func truncateUTF8(_ string: String, maxBytes: Int) -> String {
        var result = string
        while result.utf8.count > maxBytes, !result.isEmpty {
            result = String(result.dropLast())
        }
        return result
    }
}

// MARK: - Plan

enum BulkRenameRowStatus: Equatable, Sendable {
    /// Ready to rename. Optional warning (e.g. missing extension) still allows apply.
    case willRename(warning: String?)
    case unchanged
    case skipped(reason: String)

    var isActionable: Bool {
        if case .willRename = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .willRename(let warning):
            return warning ?? "OK"
        case .unchanged:
            return "Unchanged"
        case .skipped(let reason):
            return reason
        }
    }

    var hasWarning: Bool {
        if case .willRename(let warning) = self { return warning != nil }
        return false
    }
}

struct BulkRenamePlanRow: Identifiable, Equatable, Sendable {
    let id: String // current file path
    let video: Video
    let currentFileName: String
    let proposedFileName: String
    let status: BulkRenameRowStatus
}

enum BulkRenamePlanner {
    static func plan(
        videos: [Video],
        pattern: String,
        context: MetadataExportContext,
        tokens: [BulkRenameToken]
    ) -> [BulkRenamePlanRow] {
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let conflictFormat = BulkRenameSpecialParser.parseConflict(from: pattern)

        // Pass 1: Inc filled, Conflict empty.
        var draft: [(video: Video, index: Int, proposed: String)] = []
        draft.reserveCapacity(videos.count)
        for (index, video) in videos.enumerated() {
            let proposed = BulkRenameTemplate.render(
                pattern: pattern,
                video: video,
                context: context,
                tokenIdByKey: map,
                extras: .init(sequenceIndex: index, conflictIndex: nil)
            )
            draft.append((video, index, proposed))
        }

        // Pass 2: when `{Conflict …}` is present, disambiguate colliding base names.
        var conflictIndexByPath: [String: Int] = [:]
        if conflictFormat != nil {
            var groups: [String: [String]] = [:]
            for item in draft {
                let key = collisionKey(
                    directory: item.video.url.deletingLastPathComponent().path,
                    fileName: item.proposed
                )
                groups[key, default: []].append(item.video.filePath)
            }

            let batchSourcePaths = Set(videos.map { ($0.filePath as NSString).standardizingPath.lowercased() })
            let draftByPath = Dictionary(uniqueKeysWithValues: draft.map { ($0.video.filePath, $0) })

            for paths in groups.values {
                let needsConflict: Bool
                if paths.count > 1 {
                    needsConflict = true
                } else if let only = paths.first, let item = draftByPath[only] {
                    needsConflict = externallyOccupied(
                        video: item.video,
                        proposed: item.proposed,
                        batchSourcePaths: batchSourcePaths
                    )
                } else {
                    needsConflict = false
                }
                guard needsConflict else { continue }
                for (conflictIdx, path) in paths.enumerated() {
                    conflictIndexByPath[path] = conflictIdx
                }
            }

            draft = draft.map { item in
                let extras = BulkRenameTemplate.RenderExtras(
                    sequenceIndex: item.index,
                    conflictIndex: conflictIndexByPath[item.video.filePath]
                )
                let proposed = BulkRenameTemplate.render(
                    pattern: pattern,
                    video: item.video,
                    context: context,
                    tokenIdByKey: map,
                    extras: extras
                )
                return (item.video, item.index, proposed)
            }
        }

        var counts: [String: Int] = [:]
        for item in draft {
            let key = collisionKey(
                directory: item.video.url.deletingLastPathComponent().path,
                fileName: item.proposed
            )
            counts[key, default: 0] += 1
        }

        let proposedByPath = Dictionary(uniqueKeysWithValues: draft.map { ($0.video.filePath, $0.proposed) })
        let videosByStdPath: [String: Video] = Dictionary(
            uniqueKeysWithValues: videos.map {
                (($0.filePath as NSString).standardizingPath.lowercased(), $0)
            }
        )

        return draft.map { item in
            let current = item.video.fileName
            let status = rowStatus(
                video: item.video,
                current: current,
                proposed: item.proposed,
                batchCounts: counts,
                proposedByPath: proposedByPath,
                videosByStdPath: videosByStdPath
            )
            return BulkRenamePlanRow(
                id: item.video.filePath,
                video: item.video,
                currentFileName: current,
                proposedFileName: item.proposed,
                status: status
            )
        }
    }

    private static func collisionKey(directory: String, fileName: String) -> String {
        ((directory as NSString).standardizingPath + "/" + fileName).lowercased()
    }

    /// True when the destination exists on disk and is not a batch member that will move away.
    private static func externallyOccupied(
        video: Video,
        proposed: String,
        batchSourcePaths: Set<String>
    ) -> Bool {
        let dir = video.url.deletingLastPathComponent().path
        let destPath = (dir as NSString).appendingPathComponent(proposed)
        let destStd = (destPath as NSString).standardizingPath
        let sourceStd = (video.filePath as NSString).standardizingPath
        if destStd.compare(sourceStd, options: [.caseInsensitive]) == .orderedSame {
            return false
        }
        guard FileManager.default.fileExists(atPath: destPath) else { return false }
        return !batchSourcePaths.contains(destStd.lowercased())
    }

    private static func rowStatus(
        video: Video,
        current: String,
        proposed: String,
        batchCounts: [String: Int],
        proposedByPath: [String: String],
        videosByStdPath: [String: Video]
    ) -> BulkRenameRowStatus {
        if proposed.isEmpty {
            return .skipped(reason: "Empty name")
        }
        if proposed.utf8.count > 255 {
            return .skipped(reason: "Name too long")
        }
        if proposed.contains("/") || proposed.contains("\0") {
            return .skipped(reason: "Illegal characters")
        }
        if current == proposed {
            return .unchanged
        }

        let dir = video.url.deletingLastPathComponent().path
        let key = collisionKey(directory: dir, fileName: proposed)
        if (batchCounts[key] ?? 0) > 1 {
            return .skipped(reason: "Collision")
        }

        let destPath = (dir as NSString).appendingPathComponent(proposed)
        let destStd = (destPath as NSString).standardizingPath
        let sourceStd = (video.filePath as NSString).standardizingPath
        if destStd.compare(sourceStd, options: [.caseInsensitive]) == .orderedSame {
            return okRenameStatus(proposed: proposed)
        }

        if FileManager.default.fileExists(atPath: destPath) {
            if let occupant = videosByStdPath[destStd.lowercased()],
               let occupantProposed = proposedByPath[occupant.filePath]
            {
                if occupant.fileName.compare(occupantProposed, options: [.caseInsensitive]) == .orderedSame {
                    return .skipped(reason: "Collision")
                }
                return okRenameStatus(proposed: proposed)
            }
            return .skipped(reason: "Collision")
        }

        return okRenameStatus(proposed: proposed)
    }

    /// Actionable rename; warn when the proposed name has no path extension.
    private static func okRenameStatus(proposed: String) -> BulkRenameRowStatus {
        let ext = (proposed as NSString).pathExtension
        if ext.isEmpty {
            return .willRename(warning: "No extension")
        }
        return .willRename(warning: nil)
    }
}
