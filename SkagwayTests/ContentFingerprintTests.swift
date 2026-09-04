import XCTest
@testable import Skagway

final class ContentFingerprintTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("skagway-fp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    private func write(_ name: String, data: Data) throws -> URL {
        let url = scratch.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testMissingFileReturnsNil() {
        let url = scratch.appendingPathComponent("absent.bin")
        XCTAssertNil(ContentFingerprint.compute(url: url))
    }

    func testIdenticalFilesMatch() throws {
        let bytes = Data((0..<4096).map { UInt8($0 % 251) })
        let a = try write("a.bin", data: bytes)
        let b = try write("b.bin", data: bytes)
        XCTAssertEqual(ContentFingerprint.compute(url: a), ContentFingerprint.compute(url: b))
    }

    func testSameSizeDifferentHeadDiffers() throws {
        var x = Data(repeating: 1, count: 300_000)
        var y = x
        y[0] = 9
        let a = try write("head-a.bin", data: x)
        let b = try write("head-b.bin", data: y)
        XCTAssertNotEqual(ContentFingerprint.compute(url: a), ContentFingerprint.compute(url: b))
    }

    func testSameSizeDifferentTailDiffers() throws {
        var x = Data(repeating: 2, count: 300_000)
        var y = x
        y[y.count - 1] = 9
        let a = try write("tail-a.bin", data: x)
        let b = try write("tail-b.bin", data: y)
        XCTAssertNotEqual(ContentFingerprint.compute(url: a), ContentFingerprint.compute(url: b))
    }

    func testDifferentSizeDiffers() throws {
        let a = try write("small.bin", data: Data(repeating: 3, count: 1000))
        let b = try write("big.bin", data: Data(repeating: 3, count: 1001))
        XCTAssertNotEqual(ContentFingerprint.compute(url: a), ContentFingerprint.compute(url: b))
    }

    func testStableAcrossCalls() throws {
        let url = try write("stable.bin", data: Data((0..<8000).map { UInt8($0 % 200) }))
        XCTAssertEqual(ContentFingerprint.compute(url: url), ContentFingerprint.compute(url: url))
    }
}
