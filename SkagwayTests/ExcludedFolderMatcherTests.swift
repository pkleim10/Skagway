import XCTest
@testable import Skagway

final class ExcludedFolderMatcherTests: XCTestCase {
    func testNormalizeStripsTrailingSlash() {
        XCTAssertEqual(ExcludedFolderMatcher.normalize("/Videos/"), "/Videos")
        XCTAssertEqual(ExcludedFolderMatcher.normalize("/"), "/")
    }

    func testContainsExactAndDescendant() {
        let roots = ["/Volumes/Media/Videos"]
        XCTAssertTrue(ExcludedFolderMatcher.contains("/Volumes/Media/Videos", excludedRoots: roots))
        XCTAssertTrue(ExcludedFolderMatcher.contains("/Volumes/Media/Videos/clip.mp4", excludedRoots: roots))
        XCTAssertTrue(ExcludedFolderMatcher.contains("/Volumes/Media/Videos/A/b.mp4", excludedRoots: roots))
    }

    func testDoesNotMatchSiblingPrefix() {
        let roots = ["/Volumes/Media/Videos"]
        XCTAssertFalse(ExcludedFolderMatcher.contains("/Volumes/Media/Videos-backup/clip.mp4", excludedRoots: roots))
        XCTAssertFalse(ExcludedFolderMatcher.contains("/Volumes/Media", excludedRoots: roots))
    }

    func testCaseInsensitive() {
        let roots = ["/Volumes/Media/Videos"]
        XCTAssertTrue(ExcludedFolderMatcher.contains("/volumes/media/videos/Clip.MP4", excludedRoots: roots))
    }

    func testEmptyRootsNeverExclude() {
        XCTAssertFalse(ExcludedFolderMatcher.contains("/any/path", excludedRoots: []))
    }

    func testIsUnderBoundary() {
        XCTAssertTrue(ExcludedFolderMatcher.isUnder(root: "/a/b", path: "/a/b"))
        XCTAssertTrue(ExcludedFolderMatcher.isUnder(root: "/a/b", path: "/a/b/c"))
        XCTAssertFalse(ExcludedFolderMatcher.isUnder(root: "/a/b", path: "/a/bc"))
        XCTAssertFalse(ExcludedFolderMatcher.isUnder(root: "/a/b", path: "/a"))
    }
}
