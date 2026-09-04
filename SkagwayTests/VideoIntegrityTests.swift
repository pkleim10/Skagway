import XCTest
@testable import Skagway

final class VideoIntegrityTests: XCTestCase {
    func testHealthyVideoIsNotCorrupt() {
        XCTAssertFalse(VideoIntegrity.isCorrupt(TestVideo.make(), thumbnailsSettled: true))
        XCTAssertFalse(VideoIntegrity.isCorrupt(TestVideo.make(), thumbnailsSettled: false))
    }

    func testMissingAllDecodeMetadataIsCorrupt() {
        let video = TestVideo.make(duration: nil, width: nil, height: nil)
        XCTAssertTrue(VideoIntegrity.isCorrupt(video, thumbnailsSettled: false))
        XCTAssertTrue(VideoIntegrity.isCorrupt(video, thumbnailsSettled: true))
    }

    func testPartialMetadataIsNotCorruptBeforeThumbnailsSettle() {
        let video = TestVideo.make(duration: 10, width: nil, height: nil, thumbnailPath: nil)
        XCTAssertFalse(VideoIntegrity.isCorrupt(video, thumbnailsSettled: false))
    }

    func testMissingThumbnailAfterSettleIsCorrupt() {
        let video = TestVideo.make(thumbnailPath: nil)
        XCTAssertTrue(VideoIntegrity.isCorrupt(video, thumbnailsSettled: true))
        XCTAssertFalse(VideoIntegrity.isCorrupt(video, thumbnailsSettled: false))
    }

    func testMissingFileIsNotCorruptHeuristic() {
        // Missing is a filesystem check (id set), not this metadata heuristic.
        let video = TestVideo.make(path: "/does/not/exist.mp4")
        XCTAssertFalse(VideoIntegrity.isCorrupt(video, thumbnailsSettled: false))
    }
}
