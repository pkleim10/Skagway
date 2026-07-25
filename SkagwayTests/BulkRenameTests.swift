import XCTest
@testable import Skagway

final class BulkRenameTests: XCTestCase {
    func testRender_literalsAndTokens() {
        let video = sampleVideo(title: "Cooper", fileName: "raw.mp4", duration: 754, height: 1080)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let context = emptyContext()

        let name = BulkRenameTemplate.render(
            pattern: "VIDEO-{Title}-{Quality}.{Extension}",
            video: video,
            context: context,
            tokenIdByKey: map
        )
        XCTAssertEqual(name, "VIDEO-Cooper-1080p.mp4")
    }

    func testRender_durationFriendlyHasNoColons() {
        let video = sampleVideo(title: "A", fileName: "a.mp4", duration: 3723, height: 720)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let name = BulkRenameTemplate.render(
            pattern: "{Title}-{Duration}.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map
        )
        XCTAssertEqual(name, "A-1h02m03s.mp4")
        XCTAssertFalse(name.contains(":"))
    }

    func testRender_durationFormatArgs() {
        let video = sampleVideo(title: "A", fileName: "a.mp4", duration: 3723, height: 720)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let totalMinutes = BulkRenameTemplate.render(
            pattern: "{Duration mmm}.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map
        )
        XCTAssertEqual(totalMinutes, "62.mp4")

        let components = BulkRenameTemplate.render(
            pattern: "{Duration h}h-{Duration m}m-{Duration s}s.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map
        )
        XCTAssertEqual(components, "1h-2m-3s.mp4")
    }

    func testRender_caseTransforms() {
        let video = sampleVideo(title: "copper River", fileName: "raw.mp4", duration: 10, height: 1080)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let context = emptyContext()

        XCTAssertEqual(
            BulkRenameTemplate.render(pattern: "{Title lower}", video: video, context: context, tokenIdByKey: map),
            "copper river"
        )
        XCTAssertEqual(
            BulkRenameTemplate.render(pattern: "{Title UPPER}", video: video, context: context, tokenIdByKey: map),
            "COPPER RIVER"
        )
        XCTAssertEqual(
            BulkRenameTemplate.render(pattern: "{Title N}", video: video, context: context, tokenIdByKey: map),
            "Copper River"
        )
        XCTAssertEqual(
            BulkRenameTemplate.render(pattern: "{Title U}", video: video, context: context, tokenIdByKey: map),
            "COPPER RIVER"
        )
    }

    func testRender_stemAndDateCreatedFormat() {
        let created = date(year: 2026, month: 3, day: 15, hour: 17, minute: 15)
        let video = sampleVideo(
            title: "A",
            fileName: "Vacation Clip.mp4",
            duration: 10,
            height: 1080,
            creationDate: created
        )
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let context = emptyContext()

        XCTAssertEqual(
            BulkRenameTemplate.render(pattern: "{Stem}.{Extension}", video: video, context: context, tokenIdByKey: map),
            "Vacation Clip.mp4"
        )
        XCTAssertEqual(
            BulkRenameTemplate.render(
                pattern: "{DateCreated MMM-yyyy}.{Extension}",
                video: video,
                context: context,
                tokenIdByKey: map
            ),
            "Mar-2026.mp4"
        )
        // DateFormatter: `HH` = 24-hour. (`hh` is 12-hour.) Colon sanitized to `-`.
        XCTAssertEqual(
            BulkRenameTemplate.render(
                pattern: "{Date Created HH:mm}.{Extension}",
                video: video,
                context: context,
                tokenIdByKey: map
            ),
            "17-15.mp4"
        )
    }

    func testRender_uuid8Length() {
        let video = sampleVideo(title: "A", fileName: "a.mp4", duration: 10, height: 1080)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let name = BulkRenameTemplate.render(
            pattern: "{UUID8}.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map
        )
        let stem = (name as NSString).deletingPathExtension
        XCTAssertEqual(stem.count, 8)
        XCTAssertEqual(stem, stem.lowercased())
        XCTAssertTrue(stem.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) })
    }

    func testRender_originalFileNameUnaffectedByCurrentName() {
        var video = sampleVideo(title: "Clip", fileName: "renamed.mp4", duration: 10, height: 1080)
        video.originalFileName = "camera-001.mp4"
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let name = BulkRenameTemplate.render(
            pattern: "{Original File Name}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map
        )
        XCTAssertEqual(name, "camera-001.mp4")
    }

    func testPatternSelection_tokenRangeContaining() {
        let text = "VIDEO-{Title}-{Quality}.{Extension}"
        let title = BulkRenamePatternSelection.tokenRange(containing: 8, in: text) // inside Title
        XCTAssertEqual((text as NSString).substring(with: title!), "{Title}")

        let quality = BulkRenamePatternSelection.tokenRange(containing: 16, in: text)
        XCTAssertEqual((text as NSString).substring(with: quality!), "{Quality}")

        // On literal text — nil
        XCTAssertNil(BulkRenamePatternSelection.tokenRange(containing: 0, in: text))
        XCTAssertNil(BulkRenamePatternSelection.tokenRange(containing: 5, in: text)) // last char of "VIDEO"
        // Index on `{` counts as inside the token
        let onBrace = BulkRenamePatternSelection.tokenRange(containing: 6, in: text)
        XCTAssertEqual((text as NSString).substring(with: onBrace!), "{Title}")
    }

    func testPlan_warnsWhenNoExtension() {
        let video = sampleVideo(title: "Clip", fileName: "clip.mp4", duration: 10, height: 1080)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let rows = BulkRenamePlanner.plan(
            videos: [video],
            pattern: "{Title}",
            context: emptyContext(),
            tokens: tokens
        )
        XCTAssertEqual(rows[0].proposedFileName, "Clip")
        XCTAssertEqual(rows[0].status, .willRename(warning: "No extension"))
        XCTAssertTrue(rows[0].status.isActionable)
        XCTAssertTrue(rows[0].status.hasWarning)
    }

    func testPlan_marksEmptyAndUnchanged() {
        let video = sampleVideo(title: "Same", fileName: "Same.mp4", duration: 10, height: 1080)
        // Force title display to match file name for unchanged path via pattern {File Name}
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let rows = BulkRenamePlanner.plan(
            videos: [video],
            pattern: "{File Name}",
            context: emptyContext(),
            tokens: tokens
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].status, .unchanged)

        let empty = BulkRenamePlanner.plan(
            videos: [video],
            pattern: "",
            context: emptyContext(),
            tokens: tokens
        )
        XCTAssertEqual(empty[0].status, .skipped(reason: "Empty name"))
    }

    func testPlan_detectsInBatchCollision() {
        let a = sampleVideo(title: "Twin", fileName: "a.mp4", duration: 10, height: 1080, path: "/Movies/a.mp4", databaseId: 1)
        let b = sampleVideo(title: "Twin", fileName: "b.mp4", duration: 10, height: 1080, path: "/Movies/b.mp4", databaseId: 2)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let rows = BulkRenamePlanner.plan(
            videos: [a, b],
            pattern: "{Title}.{Extension}",
            context: emptyContext(),
            tokens: tokens
        )
        XCTAssertEqual(rows.filter { $0.status == .skipped(reason: "Collision") }.count, 2)
    }

    func testParse_incPadding() {
        XCTAssertEqual(BulkRenameSpecialParser.parseIncKey("Inc 0")?.string(forOffset: 0), "0")
        XCTAssertEqual(BulkRenameSpecialParser.parseIncKey("Inc 0")?.string(forOffset: 1), "1")
        XCTAssertEqual(BulkRenameSpecialParser.parseIncKey("Inc 015")?.string(forOffset: 0), "015")
        XCTAssertEqual(BulkRenameSpecialParser.parseIncKey("Inc 015")?.string(forOffset: 1), "016")
    }

    func testParse_conflictPrefixAndPadding() {
        let dash = BulkRenameSpecialParser.parseConflictKey("Conflict -1")
        XCTAssertEqual(dash?.string(forConflictIndex: 0), "-1")
        XCTAssertEqual(dash?.string(forConflictIndex: 1), "-2")

        let colon = BulkRenameSpecialParser.parseConflictKey("Conflict :01")
        XCTAssertEqual(colon?.string(forConflictIndex: 0), ":01")
        XCTAssertEqual(colon?.string(forConflictIndex: 1), ":02")
    }

    func testRender_incSequence() {
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let a = sampleVideo(title: "A", fileName: "a.mp4", duration: 10, height: 1080, path: "/Movies/a.mp4", databaseId: 1)
        let b = sampleVideo(title: "B", fileName: "b.mp4", duration: 10, height: 1080, path: "/Movies/b.mp4", databaseId: 2)

        let first = BulkRenameTemplate.render(
            pattern: "clip-{Inc 015}.{Extension}",
            video: a,
            context: emptyContext(),
            tokenIdByKey: map,
            extras: .init(sequenceIndex: 0, conflictIndex: nil)
        )
        let second = BulkRenameTemplate.render(
            pattern: "clip-{Inc 015}.{Extension}",
            video: b,
            context: emptyContext(),
            tokenIdByKey: map,
            extras: .init(sequenceIndex: 1, conflictIndex: nil)
        )
        XCTAssertEqual(first, "clip-015.mp4")
        XCTAssertEqual(second, "clip-016.mp4")
    }

    func testRender_conflictEmptyUnlessIndexed() {
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let map = BulkRenameTokenCatalog.lookupMap(tokens: tokens)
        let video = sampleVideo(title: "Twin", fileName: "a.mp4", duration: 10, height: 1080)

        let plain = BulkRenameTemplate.render(
            pattern: "{Title}{Conflict -1}.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map,
            extras: .init(sequenceIndex: 0, conflictIndex: nil)
        )
        XCTAssertEqual(plain, "Twin.mp4")

        let conflicted = BulkRenameTemplate.render(
            pattern: "{Title}{Conflict -1}.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map,
            extras: .init(sequenceIndex: 0, conflictIndex: 0)
        )
        XCTAssertEqual(conflicted, "Twin-1.mp4")

        // `:` is illegal on macOS APFS names — sanitized to `-`.
        let colon = BulkRenameTemplate.render(
            pattern: "{Title}{Conflict :01}.{Extension}",
            video: video,
            context: emptyContext(),
            tokenIdByKey: map,
            extras: .init(sequenceIndex: 0, conflictIndex: 1)
        )
        XCTAssertEqual(colon, "Twin-02.mp4")
    }

    func testPlan_conflictDisambiguatesBatchCollision() {
        let a = sampleVideo(title: "Twin", fileName: "a.mp4", duration: 10, height: 1080, path: "/Movies/a.mp4", databaseId: 1)
        let b = sampleVideo(title: "Twin", fileName: "b.mp4", duration: 10, height: 1080, path: "/Movies/b.mp4", databaseId: 2)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let rows = BulkRenamePlanner.plan(
            videos: [a, b],
            pattern: "{Title}{Conflict -1}.{Extension}",
            context: emptyContext(),
            tokens: tokens
        )
        XCTAssertEqual(rows[0].proposedFileName, "Twin-1.mp4")
        XCTAssertEqual(rows[1].proposedFileName, "Twin-2.mp4")
        XCTAssertTrue(rows.allSatisfy(\.status.isActionable))
    }

    func testPlan_conflictStaysEmptyWhenUnique() {
        let a = sampleVideo(title: "Alpha", fileName: "a.mp4", duration: 10, height: 1080, path: "/Movies/a.mp4", databaseId: 1)
        let b = sampleVideo(title: "Beta", fileName: "b.mp4", duration: 10, height: 1080, path: "/Movies/b.mp4", databaseId: 2)
        let tokens = BulkRenameTokenCatalog.tokens(customFields: [])
        let rows = BulkRenamePlanner.plan(
            videos: [a, b],
            pattern: "{Title}{Conflict -1}.{Extension}",
            context: emptyContext(),
            tokens: tokens
        )
        XCTAssertEqual(rows[0].proposedFileName, "Alpha.mp4")
        XCTAssertEqual(rows[1].proposedFileName, "Beta.mp4")
    }

    private func emptyContext() -> MetadataExportContext {
        MetadataExportContext(
            tagsByVideoId: [:],
            customValuesByVideoId: [:],
            customFieldDefinitions: [:],
            missingVideoIds: [],
            duplicateVideoIds: [],
            convertedDatesByPath: [:],
            thumbnailsSettled: true
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return Calendar(identifier: .gregorian).date(from: comps) ?? Date()
    }

    private func sampleVideo(
        title: String,
        fileName: String,
        duration: Double,
        height: Int,
        path: String? = nil,
        databaseId: Int64 = 1,
        creationDate: Date? = nil
    ) -> Video {
        let filePath = path ?? "/Movies/\(fileName)"
        return Video(
            databaseId: databaseId,
            filePath: filePath,
            fileName: fileName,
            title: title,
            fileSize: 100,
            duration: duration,
            width: 1920,
            height: height,
            codec: "h264",
            frameRate: 24,
            creationDate: creationDate,
            dateAdded: Date(),
            rating: 0,
            thumbnailPath: nil,
            lastPlayed: nil,
            playCount: 0
        )
    }
}