import XCTest
@testable import Skagway

final class MetadataExportEncodingTests: XCTestCase {
    func testCSVEscape_plain() {
        XCTAssertEqual(CSVWriter.escapeField("hello"), "hello")
    }

    func testCSVEscape_comma() {
        XCTAssertEqual(CSVWriter.escapeField("a,b"), "\"a,b\"")
    }

    func testCSVEscape_quote() {
        XCTAssertEqual(CSVWriter.escapeField("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCSVEscape_newline() {
        XCTAssertEqual(CSVWriter.escapeField("line1\nline2"), "\"line1\nline2\"")
    }

    func testCSVEscape_empty() {
        XCTAssertEqual(CSVWriter.escapeField(""), "")
    }

    func testCSVEscape_unicode() {
        let s = "café 🎥"
        XCTAssertEqual(CSVWriter.escapeField(s), s)
    }

    func testCSVLine_joins() {
        let line = CSVWriter.line(fields: ["a", "b,c", "d\"e"])
        XCTAssertEqual(line, "a,\"b,c\",\"d\"\"e\"\n")
    }

    func testTagsCSVSeparator() {
        let value = MetadataExportValue.stringList(["Vacation", "Family"])
        XCTAssertEqual(MetadataExportRowBuilder.csvCellString(value), "Vacation|Family")
    }

    func testJSONL_nullAndTypes() throws {
        let line = try JSONLWriter.line(
            orderedKeys: ["filePath", "rating", "tags", "duration"],
            values: [
                "filePath": .string("/tmp/a,b.mp4"),
                "rating": .int(5),
                "tags": .stringList(["x", "y"]),
                "duration": .null,
            ]
        )
        XCTAssertTrue(line.hasPrefix("{"))
        XCTAssertTrue(line.hasSuffix("}\n"))
        // Parse as JSON to validate structure
        let data = Data(line.dropLast().utf8) // drop trailing newline
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["filePath"] as? String, "/tmp/a,b.mp4")
        XCTAssertEqual(obj["rating"] as? Int, 5)
        XCTAssertEqual(obj["tags"] as? [String], ["x", "y"])
        XCTAssertTrue(obj["duration"] is NSNull)
    }

    func testJSONL_nonFiniteDoubleEmitsNull() throws {
        let line = try JSONLWriter.line(
            orderedKeys: ["frameRate", "duration"],
            values: [
                "frameRate": .double(.nan),
                "duration": .double(.infinity),
            ]
        )
        let data = Data(line.dropLast().utf8)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertTrue(obj["frameRate"] is NSNull)
        XCTAssertTrue(obj["duration"] is NSNull)
        XCTAssertFalse(line.contains("nan"))
        XCTAssertFalse(line.lowercased().contains("inf"))
    }

    func testCustomFieldId_roundTrip() {
        let uuid = UUID()
        let id = MetadataExportColumn.customFieldId(uuid)
        XCTAssertEqual(MetadataExportColumn.customFieldUUID(fromColumnId: id), uuid)
        XCTAssertNil(MetadataExportColumn.customFieldUUID(fromColumnId: "filePath"))
    }

    func testJSONLKey_customFieldUsesHumanName() {
        let uuid = UUID()
        let columnId = MetadataExportColumn.customFieldId(uuid)
        let columns: [String: MetadataExportColumn] = [
            "filePath": .init(id: "filePath", label: "Path", defaultIncluded: true),
            columnId: .init(id: columnId, label: "Featuring", defaultIncluded: true),
        ]
        XCTAssertEqual(
            MetadataExportColumnRegistry.jsonlKey(forColumnId: columnId, columnsByID: columns),
            "Featuring"
        )
        XCTAssertEqual(
            MetadataExportColumnRegistry.jsonlKey(forColumnId: "filePath", columnsByID: columns),
            "filePath"
        )
    }

    func testJSONLKey_duplicateCustomNamesFallBackToUUID() {
        let a = UUID()
        let b = UUID()
        let idA = MetadataExportColumn.customFieldId(a)
        let idB = MetadataExportColumn.customFieldId(b)
        let columns: [String: MetadataExportColumn] = [
            idA: .init(id: idA, label: "Featuring", defaultIncluded: true),
            idB: .init(id: idB, label: "featuring", defaultIncluded: true),
        ]
        XCTAssertEqual(
            MetadataExportColumnRegistry.jsonlKey(forColumnId: idA, columnsByID: columns),
            idA
        )
        XCTAssertEqual(
            MetadataExportColumnRegistry.jsonlKey(forColumnId: idB, columnsByID: columns),
            idB
        )
    }

    func testJSONLKey_customNameCollidingWithBuiltinFallsBackToUUID() {
        let uuid = UUID()
        let columnId = MetadataExportColumn.customFieldId(uuid)
        let columns: [String: MetadataExportColumn] = [
            "rating": .init(id: "rating", label: "Rating", defaultIncluded: true),
            columnId: .init(id: columnId, label: "rating", defaultIncluded: true),
        ]
        XCTAssertEqual(
            MetadataExportColumnRegistry.jsonlKey(forColumnId: columnId, columnsByID: columns),
            columnId
        )
    }
}
