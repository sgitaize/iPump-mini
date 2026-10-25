// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import MiniMedKit

final class SensorClockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_965_874)   // 2026-10-25 23:04:34 CET

    func testNoShiftWhenOnTime() {
        let start = now.addingTimeInterval(-3 * 86400 - 30)
        XCTAssertNil(SensorClock.shift(sessionStart: start, offsetMinutes: 3 * 1440, now: now))
        // A value that is a few minutes old is normal latency.
        XCTAssertNil(SensorClock.shift(sessionStart: start.addingTimeInterval(-240), offsetMinutes: 3 * 1440, now: now))
    }

    func testDaylightSavingShift() {
        // Live value lands one hour too early (end of DST).
        let start = now.addingTimeInterval(-3 * 86400 - 3600 + 21)
        XCTAssertEqual(SensorClock.shift(sessionStart: start, offsetMinutes: 3 * 1440, now: now), 3600)
        // One hour too late (start of DST).
        let late = now.addingTimeInterval(-3 * 86400 + 3600 - 50)
        XCTAssertEqual(SensorClock.shift(sessionStart: late, offsetMinutes: 3 * 1440, now: now), -3600)
    }

    func testIgnoresDeviationsThatAreNoClockShift() {
        // 22 min off is neither latency nor whole quarter hours.
        let start = now.addingTimeInterval(-3 * 86400 - 22 * 60)
        XCTAssertNil(SensorClock.shift(sessionStart: start, offsetMinutes: 3 * 1440, now: now))
    }
}
