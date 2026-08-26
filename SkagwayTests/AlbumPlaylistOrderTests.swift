import XCTest
@testable import Skagway

final class AlbumPlaylistOrderTests: XCTestCase {
    func testDropOnNextItemMovesAfter() {
        // Dragging onto the neighbor used to be a no-op with insert-before.
        XCTAssertEqual(AlbumPlaylistOrder.moving([1], onto: 2, in: [1, 2, 3, 4]), [2, 1, 3, 4])
    }

    func testDropOnLaterItemMovesAfter() {
        XCTAssertEqual(AlbumPlaylistOrder.moving([1], onto: 3, in: [1, 2, 3, 4]), [2, 3, 1, 4])
    }

    func testDropOnLastItemMovesToEnd() {
        XCTAssertEqual(AlbumPlaylistOrder.moving([1], onto: 4, in: [1, 2, 3, 4]), [2, 3, 4, 1])
    }

    func testDropOnEarlierItemMovesBefore() {
        XCTAssertEqual(AlbumPlaylistOrder.moving([3], onto: 1, in: [1, 2, 3, 4]), [3, 1, 2, 4])
    }

    func testDropOnPreviousItemSwaps() {
        XCTAssertEqual(AlbumPlaylistOrder.moving([3], onto: 2, in: [1, 2, 3, 4]), [1, 3, 2, 4])
    }

    func testMoveBlockPreservesRelativeOrder() {
        XCTAssertEqual(AlbumPlaylistOrder.moving([1, 3], onto: 4, in: [1, 2, 3, 4]), [2, 4, 1, 3])
    }

    func testDropOnMovedItemIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([1, 2], onto: 2, in: [1, 2, 3]))
    }

    func testMissingTargetIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([1], onto: 99, in: [1, 2, 3]))
    }

    func testEmptyMovingIsNoOp() {
        XCTAssertNil(AlbumPlaylistOrder.moving([], onto: 2, in: [1, 2, 3]))
    }
}
