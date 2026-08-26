import XCTest
@testable import Skagway

final class AlbumPlaylistOrderTests: XCTestCase {
    func testMoveSingleBeforeLaterItem() {
        let result = AlbumPlaylistOrder.moving([1], before: 3, in: [1, 2, 3, 4])
        XCTAssertEqual(result, [2, 1, 3, 4])
    }

    func testMoveSingleBeforeEarlierItem() {
        let result = AlbumPlaylistOrder.moving([3], before: 1, in: [1, 2, 3, 4])
        XCTAssertEqual(result, [3, 1, 2, 4])
    }

    func testMoveBlockPreservesRelativeOrder() {
        let result = AlbumPlaylistOrder.moving([3, 1], before: 4, in: [1, 2, 3, 4])
        XCTAssertEqual(result, [2, 1, 3, 4])
    }

    func testDropOnMovedItemIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([1, 2], before: 2, in: [1, 2, 3]))
    }

    func testMissingTargetIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([1], before: 99, in: [1, 2, 3]))
    }

    func testEmptyMovingIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([], before: 2, in: [1, 2, 3]))
    }

    func testAlreadyInPlaceIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([2], before: 3, in: [1, 2, 3]))
    }
}
