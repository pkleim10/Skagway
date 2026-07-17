import XCTest
@testable import Skagway

final class MetadataApplyTests: XCTestCase {
    private let featuringID = UUID(uuidString: "938F1A76-3FD9-4F51-B073-083CA5CF7EE7")!

    private var customFeaturing: CustomMetadataFieldDefinition {
        CustomMetadataFieldDefinition(id: featuringID, name: "Featuring", valueType: .string)
    }

    func testResolve_csvPathLabel() {
        XCTAssertEqual(
            MetadataExportColumnRegistry.resolveIncomingColumnKey("Path", customFields: []),
            "filePath"
        )
    }

    func testResolve_jsonlMachineId() {
        XCTAssertEqual(
            MetadataExportColumnRegistry.resolveIncomingColumnKey("filePath", customFields: []),
            "filePath"
        )
    }

    func testResolve_customHumanName() {
        XCTAssertEqual(
            MetadataExportColumnRegistry.resolveIncomingColumnKey("Featuring", customFields: [customFeaturing]),
            MetadataExportColumn.customFieldId(featuringID)
        )
    }

    func testResolve_unknownSkipped() {
        XCTAssertNil(
            MetadataExportColumnRegistry.resolveIncomingColumnKey("script_helper", customFields: [])
        )
    }

    func testDetect_csvByExtension() throws {
        let data = Data("Path,Rating\n/a,1\n".utf8)
        let url = URL(fileURLWithPath: "/tmp/x.csv")
        XCTAssertEqual(try MetadataApplyParser.detectFormat(url: url, data: data), .csv)
    }

    func testDetect_jsonlByContent() throws {
        let data = Data("{\"filePath\":\"/a\"}\n".utf8)
        let url = URL(fileURLWithPath: "/tmp/x.txt")
        XCTAssertEqual(try MetadataApplyParser.detectFormat(url: url, data: data), .jsonl)
    }

    func testParseCSV_andMatchPath() throws {
        let csv = "Path,Rating,Featuring\n/Movies/a.mp4,5,Alice\n/Movies/missing.mp4,1,Bob\n"
        let data = Data(csv.utf8)
        let (rows, unknown, resolved) = try MetadataApplyParser.parse(
            data: data,
            format: .csv,
            customFields: [customFeaturing]
        )
        XCTAssertTrue(unknown.isEmpty)
        XCTAssertTrue(resolved.contains("filePath"))
        XCTAssertEqual(rows.count, 2)

        let video = Video(
            databaseId: 1,
            filePath: "/Movies/a.mp4",
            fileName: "a.mp4",
            fileSize: 10,
            duration: 1,
            width: 1,
            height: 1,
            codec: nil,
            frameRate: nil,
            creationDate: nil,
            dateAdded: Date(),
            rating: 0,
            thumbnailPath: nil,
            lastPlayed: nil,
            playCount: 0
        )
        let index = MetadataApplier.buildIndex(
            videos: [video],
            tagsByVideoId: [:],
            customByVideoId: [:],
            customFieldDefinitions: [customFeaturing]
        )
        let result = try MetadataApplier.pass1(
            rows: rows,
            resolvedColumnIDs: resolved,
            skippedUnknownColumns: unknown.map(\.key),
            index: index
        )
        XCTAssertEqual(result.matchedCount, 1)
        XCTAssertEqual(result.unmatchedCount, 1)
        XCTAssertEqual(result.ratingUpdates[1], 5)
        XCTAssertEqual(result.customUpdates[featuringID]?[1], "Alice")
    }

    func testMatch_fingerprintFallback_andAmbiguity() throws {
        let v1 = sampleVideo(id: 1, path: "/a.mp4", fp: "abc", rating: 0)
        let v2 = sampleVideo(id: 2, path: "/b.mp4", fp: "abc", rating: 0)
        let index = MetadataApplier.buildIndex(
            videos: [v1, v2],
            tagsByVideoId: [:],
            customByVideoId: [:],
            customFieldDefinitions: []
        )
        let row = MetadataApplyRow(
            lineNumber: 2,
            values: ["contentFingerprint": "abc", "rating": "3"]
        )
        XCTAssertNil(MetadataApplier.matchVideo(row: row, index: index))

        let unique = MetadataApplyRow(
            lineNumber: 3,
            values: ["contentFingerprint": "zzz", "rating": "2"]
        )
        let index2 = MetadataApplier.buildIndex(
            videos: [sampleVideo(id: 3, path: "/c.mp4", fp: "zzz", rating: 1)],
            tagsByVideoId: [:],
            customByVideoId: [:],
            customFieldDefinitions: []
        )
        XCTAssertEqual(MetadataApplier.matchVideo(row: unique, index: index2)?.databaseId, 3)
    }

    func testDiff_emptyLeavesAlone_identicalSkipped() throws {
        let video = sampleVideo(id: 1, path: "/a.mp4", fp: nil, rating: 4)
        let index = MetadataApplier.buildIndex(
            videos: [video],
            tagsByVideoId: [1: [Tag(id: 1, name: "Vacation")]],
            customByVideoId: [1: [featuringID: "Alice"]],
            customFieldDefinitions: [customFeaturing]
        )
        let rows = [
            MetadataApplyRow(lineNumber: 2, values: [
                "filePath": "/a.mp4",
                "rating": "4",
                "tags": "Vacation",
                MetadataExportColumn.customFieldId(featuringID): "Alice",
            ]),
            MetadataApplyRow(lineNumber: 3, values: [
                "filePath": "/a.mp4",
                "rating": "",
                MetadataExportColumn.customFieldId(featuringID): "",
            ]),
        ]
        let result = try MetadataApplier.pass1(
            rows: rows,
            resolvedColumnIDs: ["filePath", "rating", "tags", MetadataExportColumn.customFieldId(featuringID)],
            skippedUnknownColumns: [],
            index: index
        )
        XCTAssertTrue(result.ratingUpdates.isEmpty)
        XCTAssertTrue(result.tagMerges.isEmpty)
        XCTAssertTrue(result.customUpdates.isEmpty)
        XCTAssertEqual(result.updatedVideoCount, 0)
    }

    func testParseJSONL_roundTripFromWriter() throws {
        let line = try JSONLWriter.line(
            orderedKeys: ["filePath", "rating", "Featuring", "tags"],
            values: [
                "filePath": .string("/Movies/a.mp4"),
                "rating": .int(5),
                "Featuring": .string("Alice"),
                "tags": .stringList(["Vacation", "Family"]),
            ]
        )
        let data = Data(line.utf8)
        let (rows, unknown, resolved) = try MetadataApplyParser.parse(
            data: data,
            format: .jsonl,
            customFields: [customFeaturing]
        )
        XCTAssertTrue(unknown.isEmpty)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].values["filePath"], "/Movies/a.mp4")
        XCTAssertEqual(rows[0].values["rating"], "5")
        XCTAssertEqual(rows[0].values[MetadataExportColumn.customFieldId(featuringID)], "Alice")
        XCTAssertEqual(rows[0].values["tags"], "Vacation|Family")
        XCTAssertTrue(resolved.contains("filePath"))
    }

    func testParseJSONL_invalidLineSurfacesLineNumber() {
        let data = Data("{\"filePath\":\"/ok.mp4\"}\n{not-json\n".utf8)
        XCTAssertThrowsError(
            try MetadataApplyParser.parse(data: data, format: .jsonl, customFields: [])
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("line 2"), message)
            XCTAssertFalse(message.contains("isn't in the correct format") && !message.contains("line"))
        }
    }

    func testParseCSV_unknownColumnsCollectSamplesAndSuggestBoolean() throws {
        let csv = "Path,Favorite,Notes\n/a.mp4,yes,hello\n/b.mp4,no,world\n"
        let data = Data(csv.utf8)
        let (rows, unknown, _) = try MetadataApplyParser.parse(
            data: data,
            format: .csv,
            customFields: []
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(unknown.map(\.key), ["Favorite", "Notes"])
        XCTAssertEqual(unknown[0].suggestedType, .boolean)
        XCTAssertEqual(unknown[0].sampleValues.count, 2)
        XCTAssertEqual(unknown[1].suggestedType, .string)
    }

    func testInference_booleanBeforeNumber() {
        XCTAssertEqual(
            MetadataImportTypeInference.suggestType(samples: ["1", "0", "1"]),
            .boolean
        )
        XCTAssertEqual(
            MetadataImportTypeInference.suggestType(samples: ["2", "3.5"]),
            .number
        )
        XCTAssertEqual(
            MetadataImportTypeInference.suggestType(samples: ["yes", "NO"]),
            .boolean
        )
    }

    func testBooleanNormalize() {
        XCTAssertEqual(CustomMetadataValueType.normalizeBooleanStorage("Yes"), "true")
        XCTAssertEqual(CustomMetadataValueType.normalizeBooleanStorage("0"), "false")
        XCTAssertNil(CustomMetadataValueType.normalizeBooleanStorage("maybe"))
    }

    func testPass1_booleanCustomFieldNormalizesAndRejectsGarbage() throws {
        let boolID = UUID()
        let boolField = CustomMetadataFieldDefinition(id: boolID, name: "Favorite", valueType: .boolean)
        let video = sampleVideo(id: 1, path: "/a.mp4", fp: nil, rating: 0)
        let index = MetadataApplier.buildIndex(
            videos: [video],
            tagsByVideoId: [:],
            customByVideoId: [:],
            customFieldDefinitions: [boolField]
        )
        let columnId = MetadataExportColumn.customFieldId(boolID)
        let rows = [
            MetadataApplyRow(lineNumber: 2, values: [
                "filePath": "/a.mp4",
                columnId: "yes",
            ]),
            MetadataApplyRow(lineNumber: 3, values: [
                "filePath": "/a.mp4",
                columnId: "maybe",
            ]),
        ]
        let result = try MetadataApplier.pass1(
            rows: rows,
            resolvedColumnIDs: ["filePath", columnId],
            skippedUnknownColumns: [],
            index: index
        )
        XCTAssertEqual(result.customUpdates[boolID]?[1], "true")
        XCTAssertTrue(result.rowErrors.contains(where: { $0.contains("invalid boolean") }))
    }

    func testParse_reResolveAfterCreatingUnknownField() throws {
        let csv = "Path,Director\n/a.mp4,Nolan\n"
        let data = Data(csv.utf8)
        let (rows1, unknown, _) = try MetadataApplyParser.parse(
            data: data,
            format: .csv,
            customFields: []
        )
        XCTAssertEqual(unknown.map(\.key), ["Director"])
        XCTAssertTrue(rows1[0].values.keys.filter { $0.hasPrefix("custom:") }.isEmpty)

        let directorID = UUID()
        let director = CustomMetadataFieldDefinition(id: directorID, name: "Director", valueType: .string)
        let (rows2, unknown2, resolved) = try MetadataApplyParser.parse(
            data: data,
            format: .csv,
            customFields: [director]
        )
        XCTAssertTrue(unknown2.isEmpty)
        XCTAssertEqual(rows2[0].values[MetadataExportColumn.customFieldId(directorID)], "Nolan")
        XCTAssertTrue(resolved.contains(MetadataExportColumn.customFieldId(directorID)))
    }

    func testPass2_collectsUnmatchedOnly() {
        let video = sampleVideo(id: 1, path: "/a.mp4", fp: nil, rating: 0)
        let index = MetadataApplier.buildIndex(
            videos: [video],
            tagsByVideoId: [:],
            customByVideoId: [:],
            customFieldDefinitions: []
        )
        let rows = [
            MetadataApplyRow(lineNumber: 2, values: ["filePath": "/a.mp4"]),
            MetadataApplyRow(lineNumber: 3, values: ["filePath": "/missing.mp4"]),
        ]
        let unmatched = MetadataApplier.pass2Unmatched(rows: rows, index: index)
        XCTAssertEqual(unmatched.count, 1)
        XCTAssertEqual(unmatched[0].filePath, "/missing.mp4")
    }

    private func sampleVideo(id: Int64, path: String, fp: String?, rating: Int) -> Video {
        Video(
            databaseId: id,
            filePath: path,
            fileName: (path as NSString).lastPathComponent,
            fileSize: 1,
            duration: 1,
            width: 1,
            height: 1,
            codec: nil,
            frameRate: nil,
            creationDate: nil,
            dateAdded: Date(),
            rating: rating,
            thumbnailPath: nil,
            lastPlayed: nil,
            playCount: 0,
            hasSubtitles: false,
            contentFingerprint: fp
        )
    }
}
