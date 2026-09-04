import XCTest
@testable import Skagway

final class RatingQuickFilterTests: XCTestCase {
    private let library = [
        TestVideo.make(path: "/a.mp4", rating: 0),
        TestVideo.make(path: "/b.mp4", rating: 1),
        TestVideo.make(path: "/c.mp4", rating: 3),
        TestVideo.make(path: "/d.mp4", rating: 4),
        TestVideo.make(path: "/e.mp4", rating: 5),
    ]

    private func paths(_ selected: Set<Int>, orHigher: Bool) -> [String] {
        RatingQuickFilter.apply(selectedStars: selected, orHigher: orHigher, base: library).map(\.filePath)
    }

    func testEmptySelectionReturnsBase() {
        XCTAssertEqual(paths([], orHigher: false), library.map(\.filePath))
        XCTAssertEqual(paths([], orHigher: true), library.map(\.filePath))
    }

    func testExactStar() {
        XCTAssertEqual(paths([4], orHigher: false), ["/d.mp4"])
        XCTAssertEqual(paths([5], orHigher: false), ["/e.mp4"])
        XCTAssertEqual(paths([1], orHigher: false), ["/b.mp4"])
    }

    func testNoStarsIsUnratedOnly() {
        XCTAssertEqual(paths([0], orHigher: false), ["/a.mp4"])
    }

    func testOrHigherIgnoredForUnrated() {
        XCTAssertEqual(paths([0], orHigher: true), ["/a.mp4"])
    }

    func testOrHigherIgnoredAtFive() {
        XCTAssertEqual(paths([5], orHigher: true), ["/e.mp4"])
    }

    func testOrHigherIncludesFloorAndAbove() {
        XCTAssertEqual(paths([4], orHigher: true), ["/d.mp4", "/e.mp4"])
        XCTAssertEqual(paths([3], orHigher: true), ["/c.mp4", "/d.mp4", "/e.mp4"])
        XCTAssertEqual(paths([1], orHigher: true), ["/b.mp4", "/c.mp4", "/d.mp4", "/e.mp4"])
    }

    func testOrHigherDoesNotIncludeUnrated() {
        XCTAssertFalse(paths([3], orHigher: true).contains("/a.mp4"))
    }
}
