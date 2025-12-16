import XCTest

@testable import UptimeTray

final class DurationParsingTests: XCTestCase {
    func testParsesMinutesOnly() {
        let desc = "Something\nDuration: 30 minutes\nOther"
        XCTAssertEqual(UptimeCalculator.parseDuration(from: desc), 30 * 60)
    }

    func testParsesHoursAndMinutes() {
        let desc = "Duration: 1 hour and 51 minutes"
        XCTAssertEqual(UptimeCalculator.parseDuration(from: desc), (1 * 3600) + (51 * 60))
    }

    func testParsesHoursOnly() {
        let desc = "Duration: 20 hours"
        XCTAssertEqual(UptimeCalculator.parseDuration(from: desc), 20 * 3600)
    }

    func testReturnsNilWhenNoDurationLine() {
        XCTAssertNil(UptimeCalculator.parseDuration(from: "No duration here"))
    }

    func testReturnsNilWhenZero() {
        XCTAssertNil(UptimeCalculator.parseDuration(from: "Duration: 0 minutes"))
        XCTAssertNil(UptimeCalculator.parseDuration(from: "Duration: 0 hours"))
    }
}


