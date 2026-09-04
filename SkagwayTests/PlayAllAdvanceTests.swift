import XCTest
@testable import Skagway

final class PlayAllAdvanceTests: XCTestCase {
    private let paths = ["/a.mp4", "/missing.mp4", "/c.mp4"]

    private func exists(_ path: String) -> Bool {
        path != "/missing.mp4"
    }

    func testAdvancesToNextExistingFile() {
        XCTAssertEqual(
            PlayAllAdvance.nextIndex(after: 0, paths: paths, loop: false, fileExists: exists),
            2
        )
    }

    func testSkipsConsecutiveMissing() {
        let all = ["/gone1.mp4", "/gone2.mp4", "/ok.mp4"]
        XCTAssertEqual(
            PlayAllAdvance.nextIndex(after: 0, paths: all, loop: false, fileExists: { $0 == "/ok.mp4" }),
            2
        )
    }

    func testEndsSessionWhenPastLastAndNotLooping() {
        XCTAssertNil(PlayAllAdvance.nextIndex(after: 2, paths: paths, loop: false, fileExists: exists))
    }

    func testLoopWrapsToFirstPlayable() {
        XCTAssertEqual(
            PlayAllAdvance.nextIndex(after: 2, paths: paths, loop: true, fileExists: exists),
            0
        )
    }

    func testLoopSkipsMissingAtStart() {
        let leadingMissing = ["/gone.mp4", "/ok.mp4"]
        XCTAssertEqual(
            PlayAllAdvance.nextIndex(after: 1, paths: leadingMissing, loop: true, fileExists: { $0 == "/ok.mp4" }),
            1
        )
    }

    func testLoopWithNothingPlayableEnds() {
        XCTAssertNil(
            PlayAllAdvance.nextIndex(after: 0, paths: ["/x.mp4"], loop: true, fileExists: { _ in false })
        )
    }

    func testCurrentIndexPastEndIsSafe() {
        XCTAssertNil(PlayAllAdvance.nextIndex(after: 99, paths: paths, loop: false, fileExists: exists))
    }
}
