import Foundation

/// Parses SubRip (`.srt`) files into `[SubtitleCue]`.
///
/// Tolerant of common real-world quirks:
/// - UTF-8 BOM, UTF-16 BOM, or Latin-1 fallback
/// - `\r\n`, `\r`, or `\n` line endings
/// - Missing index line (first line is the timestamp)
/// - Extra blank lines inside or between cues
/// - Timestamps with `,` or `.` fractional separator
/// - Inline HTML-ish tags (`<i>`, `<b>`, `<font ...>`) are stripped
enum SRTParser {
    static func parse(_ raw: String) -> [SubtitleCue] {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split on blank-line boundaries, but tolerate runs of >1 blank line.
        let rawBlocks = text.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        cues.reserveCapacity(rawBlocks.count)
        var nextId = 0

        for raw in rawBlocks {
            let block = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !block.isEmpty else { continue }
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard !lines.isEmpty else { continue }

            // First line may be an index or the timestamp itself.
            var timestampIdx = 0
            if !lines[0].contains("-->") {
                timestampIdx = 1
            }
            guard timestampIdx < lines.count else { continue }
            guard let (start, end) = parseTimestampLine(lines[timestampIdx]) else { continue }

            let textLines = Array(lines[(timestampIdx + 1)...])
                .map(stripInlineFormatting)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Drop leading/trailing fully-blank lines but preserve authored line breaks in between.
            let trimmed = trimLeadingTrailingEmpty(textLines)
            guard !trimmed.isEmpty, trimmed.contains(where: { !$0.isEmpty }) else { continue }

            let cue = SubtitleCue(id: nextId, start: start, end: end, lines: trimmed)
            cues.append(cue)
            nextId += 1
        }

        return cues.sorted { $0.start < $1.start }
    }

    /// Parses `"00:00:20,000 --> 00:00:24,400"` (or with `.`), ignoring any trailing position fields.
    static func parseTimestampLine(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        guard let start = parseTimestamp(parts[0]) else { return nil }
        // WebVTT-style trailing `line:`, `position:` etc. are safely ignored since
        // `parseTimestamp` reads only the leading time token.
        guard let end = parseTimestamp(parts[1]) else { return nil }
        return (start, end)
    }

    /// Parses `"HH:MM:SS,mmm"` / `"HH:MM:SS.mmm"` / `"MM:SS,mmm"` into seconds.
    static func parseTimestamp(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        // Take only the first whitespace-separated token (skips VTT cue settings after the timestamp).
        let firstToken = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? trimmed
        let normalized = firstToken.replacingOccurrences(of: ",", with: ".")
        let comps = normalized.split(separator: ":")
        switch comps.count {
        case 3:
            guard let h = Double(comps[0]), let m = Double(comps[1]), let sec = Double(comps[2]) else { return nil }
            return h * 3600 + m * 60 + sec
        case 2:
            guard let m = Double(comps[0]), let sec = Double(comps[1]) else { return nil }
            return m * 60 + sec
        default:
            return nil
        }
    }

    private static let tagRegex: NSRegularExpression = {
        // `<i>`, `</i>`, `<font color="...">`, `{\an8}` ASS/SSA position tags
        try! NSRegularExpression(pattern: "<[^>]+>|\\{[^}]+\\}", options: [])
    }()

    private static func stripInlineFormatting(_ s: String) -> String {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return tagRegex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
    }

    private static func trimLeadingTrailingEmpty(_ lines: [String]) -> [String] {
        var start = 0
        var end = lines.count
        while start < end, lines[start].isEmpty { start += 1 }
        while end > start, lines[end - 1].isEmpty { end -= 1 }
        return Array(lines[start..<end])
    }
}

extension SRTParser {
    /// Convenience: read a file from disk and parse it, trying UTF-8 first, then Latin-1 as fallback
    /// (common for older SRT files). Returns `nil` if the file cannot be read.
    static func parseFile(at url: URL) -> [SubtitleCue]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let raw = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        guard let raw else { return nil }
        return parse(raw)
    }
}
