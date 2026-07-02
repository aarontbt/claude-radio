import XCTest
@testable import ClaudeRadio

final class ReconnectManagerTests: XCTestCase {
    func testDoublesUpToMax() {
        var backoff = Backoff(initial: 2, max: 60)
        XCTAssertEqual(backoff.next(), 2)
        XCTAssertEqual(backoff.next(), 4)
        XCTAssertEqual(backoff.next(), 8)
        XCTAssertEqual(backoff.next(), 16)
        XCTAssertEqual(backoff.next(), 32)
        XCTAssertEqual(backoff.next(), 60, "should cap at max instead of reaching 64")
        XCTAssertEqual(backoff.next(), 60, "should stay capped at max")
    }

    func testResetReturnsToInitial() {
        var backoff = Backoff(initial: 2, max: 60)
        _ = backoff.next()
        _ = backoff.next()
        backoff.reset()
        XCTAssertEqual(backoff.next(), 2)
    }
}
