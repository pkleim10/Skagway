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

    func testValidExclusionMustBeStrictDescendant() {
        XCTAssertTrue(ExcludedFolderMatcher.isValidExclusion(path: "/Videos/Raw", ofSource: "/Videos"))
        XCTAssertFalse(ExcludedFolderMatcher.isValidExclusion(path: "/Videos", ofSource: "/Videos"))
        XCTAssertFalse(ExcludedFolderMatcher.isValidExclusion(path: "/Videos/", ofSource: "/Videos"))
        XCTAssertFalse(ExcludedFolderMatcher.isValidExclusion(path: "/Other/Raw", ofSource: "/Videos"))
        XCTAssertFalse(ExcludedFolderMatcher.isValidExclusion(path: "/Vide", ofSource: "/Videos"))
    }

    func testOwningSourceIsDeepestContainer() {
        let media = source(1, "/Media")
        let projects = source(2, "/Media/Projects")
        let sources = [media, projects]

        XCTAssertEqual(
            ExcludedFolderMatcher.owningSource(of: "/Media/Projects/tmp", among: sources)?.id,
            2
        )
        XCTAssertEqual(
            ExcludedFolderMatcher.owningSource(of: "/Media/Incoming", among: sources)?.id,
            1
        )
        XCTAssertNil(ExcludedFolderMatcher.owningSource(of: "/Other/clip.mp4", among: sources))
    }

    func testOrphansAfterParentSourceRemoved() {
        let media = source(1, "/Media")
        let tmp = ExcludedFolder(id: 10, folderPath: "/Media/Projects/tmp", name: "tmp", dateAdded: Date())
        let incoming = ExcludedFolder(id: 11, folderPath: "/Media/Incoming", name: "Incoming", dateAdded: Date())

        XCTAssertTrue(
            ExcludedFolderMatcher.orphanedExcludes(from: [tmp, incoming], sources: []).isEmpty == false
        )
        let orphansWithoutProjects = ExcludedFolderMatcher.orphanedExcludes(
            from: [tmp, incoming],
            sources: [media]
        )
        XCTAssertTrue(orphansWithoutProjects.isEmpty)
        XCTAssertEqual(
            ExcludedFolderMatcher.owningSource(of: tmp.folderPath, among: [media])?.id,
            1
        )
    }

    private func source(_ id: Int64, _ path: String) -> DataSource {
        DataSource(
            id: id,
            folderPath: path,
            name: (path as NSString).lastPathComponent,
            dateAdded: Date()
        )
    }
}
