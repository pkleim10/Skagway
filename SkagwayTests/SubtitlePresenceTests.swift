import XCTest
@testable import Skagway

final class SubtitlePresenceTests: XCTestCase {
    func testApplyingSidecarFoundPreservesBurnedIn() {
        XCTAssertEqual(SubtitlePresence.none.applying(sidecarPresent: true), .sidecar)
        XCTAssertEqual(SubtitlePresence.burnedIn.applying(sidecarPresent: true), .burnedInAndSidecar)
        XCTAssertEqual(SubtitlePresence.sidecar.applying(sidecarPresent: true), .sidecar)
        XCTAssertEqual(SubtitlePresence.burnedInAndSidecar.applying(sidecarPresent: true), .burnedInAndSidecar)
    }

    func testApplyingSidecarMissingRevertsBurnedInAndSidecar() {
        XCTAssertEqual(SubtitlePresence.none.applying(sidecarPresent: false), .none)
        XCTAssertEqual(SubtitlePresence.burnedIn.applying(sidecarPresent: false), .burnedIn)
        XCTAssertEqual(SubtitlePresence.sidecar.applying(sidecarPresent: false), .none)
        XCTAssertEqual(SubtitlePresence.burnedInAndSidecar.applying(sidecarPresent: false), .burnedIn)
    }

    func testParseDisplayNamesAndLegacyBools() {
        XCTAssertEqual(SubtitlePresence.parse("None"), .none)
        XCTAssertEqual(SubtitlePresence.parse("Burned-in"), .burnedIn)
        XCTAssertEqual(SubtitlePresence.parse("Sidecar"), .sidecar)
        XCTAssertEqual(SubtitlePresence.parse("Burned-in + Sidecar"), .burnedInAndSidecar)
        XCTAssertEqual(SubtitlePresence.parse("yes"), .sidecar)
        XCTAssertEqual(SubtitlePresence.parse("true"), .sidecar)
        XCTAssertEqual(SubtitlePresence.parse("no"), .none)
        XCTAssertEqual(SubtitlePresence.parse("false"), .none)
        XCTAssertNil(SubtitlePresence.parse("maybe"))
    }
}
