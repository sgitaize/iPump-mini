// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Detects a shifted sensor session start. The pump keeps its clock as local wall time;
/// after a daylight-saving change (or a manual clock change) the session start it reports
/// can be off by whole quarter hours, and every live value then lands that far in the past
/// or future (seen on 2026-10-25: exactly one hour too early).
///
/// A sensor value with a session offset newer than the last one seen was just measured, so
/// its real time is "now" (minus a few minutes of latency). If start + offset differs from
/// now by more than `tolerance` and the difference is close to whole quarter hours, the
/// difference is treated as a clock shift.
public enum SensorClock {
    public static let tolerance: TimeInterval = 10 * 60

    /// The shift to add to the session start, or nil if none is evident.
    public static func shift(sessionStart: Date, offsetMinutes: Int, now: Date) -> TimeInterval? {
        let measured = sessionStart.addingTimeInterval(TimeInterval(offsetMinutes) * 60)
        let deviation = now.timeIntervalSince(measured)
        guard abs(deviation) > tolerance else { return nil }
        // The value is up to ~5 min old when it arrives; round to the nearest quarter hour.
        let quarters = (deviation / 900).rounded()
        guard quarters != 0, abs(deviation - quarters * 900) <= 6 * 60 else { return nil }
        return quarters * 900
    }
}
