import XCTest
@testable import ClaudeRadio

final class PlaybackStateTests: XCTestCase {
    func testEquatable() {
        XCTAssertEqual(PlaybackState.playing, PlaybackState.playing)
        XCTAssertEqual(PlaybackState.error("x"), PlaybackState.error("x"))
        XCTAssertNotEqual(PlaybackState.error("x"), PlaybackState.error("y"))
        XCTAssertNotEqual(PlaybackState.playing, PlaybackState.paused)
    }

    func testDescription() {
        XCTAssertEqual(PlaybackState.playing.description, "playing")
        XCTAssertEqual(PlaybackState.error("boom").description, "error(boom)")
    }
}
