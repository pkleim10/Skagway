import Foundation

/// Result of Apply Pass 1 (no unmatched row payloads).
struct MetadataApplyPass1Result: Sendable {
    var matchedPaths: [String]
    var matchedCount: Int
    var updatedVideoCount: Int
    var unmatchedCount: Int
    var skippedUnknownColumns: [String]
    var ignoredReadOnlyColumns: [String]
    /// fieldId → (videoDatabaseId → new raw string value)
    var customUpdates: [UUID: [Int64: String]]
    /// videoDatabaseId → new rating
    var ratingUpdates: [Int64: Int]
    /// videoDatabaseId → new library title
    var titleUpdates: [Int64: String]
    /// videoDatabaseId → new subtitle presence
    var subtitleUpdates: [Int64: SubtitlePresence]
    /// videoDatabaseId → tag names to merge (add)
    var tagMerges: [Int64: [String]]
    /// videoDatabaseId → new play count (set, not increment)
    var playCountUpdates: [Int64: Int]
    /// videoDatabaseId → resume position seconds (written to `PlaybackPositionStore` on the matched path)
    var resumeUpdates: [Int64: Double]
    var rowErrors: [String]
}

struct MetadataApplyUnmatchedRow: Identifiable, Sendable, Equatable {
    var id: Int { lineNumber }
    var lineNumber: Int
    var filePath: String?
    var contentFingerprint: String?
    var preview: String
}

enum MetadataApplyError: LocalizedError, Equatable {
    case noMatchKeyColumn
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .noMatchKeyColumn:
            return "The file must include a Path (filePath) and/or Content Fingerprint column."
        case .emptyFile:
            return "The file has no data rows."
        }
    }
}

/// Pure match/diff logic. ViewModel performs repository writes from `Pass1Result`.
enum MetadataApplier {
    struct LibraryIndex: Sendable {
        var byPath: [String: Video]
        var byFingerprint: [String: [Video]]
        var tagsByVideoId: [Int64: [Tag]]
        var customByVideoId: [Int64: [UUID: String]]
        var customFields: [UUID: CustomMetadataFieldDefinition]
        /// Current resume seconds keyed by video database id (from `PlaybackPositionStore`).
        var resumeSecondsByVideoId: [Int64: Double]
    }

    static func buildIndex(
        videos: [Video],
        tagsByVideoId: [Int64: [Tag]],
        customByVideoId: [Int64: [UUID: String]],
        customFieldDefinitions: [CustomMetadataFieldDefinition],
        resumeSecondsByVideoId: [Int64: Double] = [:]
    ) -> LibraryIndex {
        var byPath: [String: Video] = [:]
        var byFingerprint: [String: [Video]] = [:]
        for v in videos {
            byPath[v.filePath] = v
            if let fp = v.contentFingerprint, !fp.isEmpty {
                byFingerprint[fp, default: []].append(v)
            }
        }
        return LibraryIndex(
            byPath: byPath,
            byFingerprint: byFingerprint,
            tagsByVideoId: tagsByVideoId,
            customByVideoId: customByVideoId,
            customFields: Dictionary(uniqueKeysWithValues: customFieldDefinitions.map { ($0.id, $0) }),
            resumeSecondsByVideoId: resumeSecondsByVideoId
        )
    }

    /// Pass 1: match rows and compute differing writable updates. Does not store unmatched payloads.
    static func pass1(
        rows: [MetadataApplyRow],
        resolvedColumnIDs: Set<String>,
        skippedUnknownColumns: [String],
        index: LibraryIndex
    ) throws -> MetadataApplyPass1Result {
        guard !rows.isEmpty else { throw MetadataApplyError.emptyFile }

        let hasPath = resolvedColumnIDs.contains("filePath")
        let hasFP = resolvedColumnIDs.contains("contentFingerprint")
        guard hasPath || hasFP else { throw MetadataApplyError.noMatchKeyColumn }

        let ignoredReadOnly = resolvedColumnIDs
            .filter { !MetadataExportColumnRegistry.isWritableColumnID($0) && !MetadataExportColumnRegistry.isMatchKeyColumnID($0) }
            .sorted()

        var matchedPathsOrdered: [String] = []
        var matchedPathSet = Set<String>()
        var unmatchedCount = 0
        var updatedVideoCount = 0
        var customUpdates: [UUID: [Int64: String]] = [:]
        var ratingUpdates: [Int64: Int] = [:]
        var titleUpdates: [Int64: String] = [:]
        var subtitleUpdates: [Int64: SubtitlePresence] = [:]
        var tagMerges: [Int64: [String]] = [:]
        var playCountUpdates: [Int64: Int] = [:]
        var resumeUpdates: [Int64: Double] = [:]
        var rowErrors: [String] = []

        for row in rows {
            guard let video = matchVideo(row: row, index: index) else {
                unmatchedCount += 1
                continue
            }
            if matchedPathSet.insert(video.filePath).inserted {
                matchedPathsOrdered.append(video.filePath)
            }
            guard let dbId = video.databaseId else {
                unmatchedCount += 1
                continue
            }

            var didUpdate = false

            if let raw = row.values["title"] {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != video.displayTitle {
                    titleUpdates[dbId] = trimmed
                    didUpdate = true
                }
            }

            if let raw = row.values["rating"] {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let rating = Int(trimmed), (0...5).contains(rating) {
                        if video.rating != rating {
                            ratingUpdates[dbId] = rating
                            didUpdate = true
                        }
                    } else {
                        rowErrors.append("Line \(row.lineNumber): invalid rating “\(trimmed)”")
                    }
                }
            }

            if let raw = row.values["hasSubtitles"] {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let presence = SubtitlePresence.parse(trimmed) {
                        if video.subtitlePresence != presence {
                            subtitleUpdates[dbId] = presence
                            didUpdate = true
                        }
                    } else {
                        rowErrors.append("Line \(row.lineNumber): invalid subtitles “\(trimmed)”")
                    }
                }
            }

            if let raw = row.values["tags"] {
                let names = parseTagNames(raw)
                if !names.isEmpty {
                    let existing = Set((index.tagsByVideoId[dbId] ?? []).map(\.name))
                    let toAdd = names.filter { !existing.contains($0) }
                    if !toAdd.isEmpty {
                        tagMerges[dbId, default: []].append(contentsOf: toAdd)
                        didUpdate = true
                    }
                }
            }

            if let raw = row.values["playCount"] {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let count = parseNonNegativeInt(trimmed) {
                        if video.playCount != count {
                            playCountUpdates[dbId] = count
                            didUpdate = true
                        }
                    } else {
                        rowErrors.append("Line \(row.lineNumber): invalid play count “\(trimmed)”")
                    }
                }
            }

            if let raw = row.values["resumePositionSeconds"] {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let seconds = Double(trimmed), seconds.isFinite, seconds >= 0 {
                        let current = index.resumeSecondsByVideoId[dbId]
                        let isSame = current.map { abs($0 - seconds) < 0.0005 } ?? false
                        if !isSame {
                            resumeUpdates[dbId] = seconds
                            didUpdate = true
                        }
                    } else {
                        rowErrors.append("Line \(row.lineNumber): invalid resume position “\(trimmed)”")
                    }
                }
            }

            for (columnId, raw) in row.values {
                guard let fieldUUID = MetadataExportColumn.customFieldUUID(fromColumnId: columnId) else { continue }
                guard index.customFields[fieldUUID] != nil else { continue }
                let trimmed = raw // preserve intentional whitespace only after empty check
                if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let current = index.customByVideoId[dbId]?[fieldUUID] ?? ""
                var storeValue = trimmed
                if let def = index.customFields[fieldUUID] {
                    switch def.valueType {
                    case .number:
                        let t = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
                        if Double(t) == nil {
                            rowErrors.append("Line \(row.lineNumber): invalid number for custom field")
                            continue
                        }
                    case .boolean:
                        guard let normalized = CustomMetadataValueType.normalizeBooleanStorage(trimmed) else {
                            rowErrors.append("Line \(row.lineNumber): invalid boolean for custom field")
                            continue
                        }
                        storeValue = normalized
                    case .string, .text, .date, .dateTime:
                        break
                    }
                }
                if current == storeValue { continue }
                customUpdates[fieldUUID, default: [:]][dbId] = storeValue
                didUpdate = true
            }

            if didUpdate { updatedVideoCount += 1 }
        }

        return MetadataApplyPass1Result(
            matchedPaths: matchedPathsOrdered,
            matchedCount: matchedPathsOrdered.count,
            updatedVideoCount: updatedVideoCount,
            unmatchedCount: unmatchedCount,
            skippedUnknownColumns: skippedUnknownColumns,
            ignoredReadOnlyColumns: ignoredReadOnly,
            customUpdates: customUpdates,
            ratingUpdates: ratingUpdates,
            titleUpdates: titleUpdates,
            subtitleUpdates: subtitleUpdates,
            tagMerges: tagMerges,
            playCountUpdates: playCountUpdates,
            resumeUpdates: resumeUpdates,
            rowErrors: rowErrors
        )
    }

    /// Pass 2: re-scan rows and collect unmatched payloads.
    static func pass2Unmatched(
        rows: [MetadataApplyRow],
        index: LibraryIndex
    ) -> [MetadataApplyUnmatchedRow] {
        var out: [MetadataApplyUnmatchedRow] = []
        for row in rows {
            if matchVideo(row: row, index: index) != nil { continue }
            let path = nonempty(row.values["filePath"])
            let fp = nonempty(row.values["contentFingerprint"])
            let previewParts = [path, fp].compactMap { $0 }
            let preview = previewParts.isEmpty ? "(no match key)" : previewParts.joined(separator: " · ")
            out.append(MetadataApplyUnmatchedRow(
                lineNumber: row.lineNumber,
                filePath: path,
                contentFingerprint: fp,
                preview: preview
            ))
        }
        return out
    }

    static func matchVideo(row: MetadataApplyRow, index: LibraryIndex) -> Video? {
        if let path = nonempty(row.values["filePath"]), let v = index.byPath[path] {
            return v
        }
        if let fp = nonempty(row.values["contentFingerprint"]) {
            let hits = index.byFingerprint[fp] ?? []
            if hits.count == 1 { return hits[0] }
            // 0 or 2+ → unmatched
            return nil
        }
        return nil
    }

    private static func nonempty(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func parseTagNames(_ raw: String) -> [String] {
        raw.split(separator: Character(MetadataExportRowBuilder.tagsCSVSeparator), omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Whole numbers only (`3`, `3.0`); rejects negatives and fractions.
    private static func parseNonNegativeInt(_ raw: String) -> Int? {
        if let n = Int(raw), n >= 0 { return n }
        guard let d = Double(raw), d.isFinite, d >= 0, d.rounded() == d, d <= Double(Int.max) else {
            return nil
        }
        return Int(d)
    }
}
