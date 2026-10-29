// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.minimedkit

import java.time.Duration
import java.time.Instant
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Detects a shifted sensor session start. The pump keeps its clock as local wall time;
 * after a daylight-saving change (or a manual clock change) the session start it reports
 * can be off by whole quarter hours, and every live value then lands that far in the past
 * or future (seen on 2026-10-25: exactly one hour too early).
 *
 * A sensor value with a session offset newer than the last one seen was just measured, so
 * its real time is "now" (minus a few minutes of latency). If start + offset differs from
 * now by more than [TOLERANCE_SECONDS] and the difference is close to whole quarter hours,
 * the difference is treated as a clock shift. Same logic as SensorClock.swift.
 */
object SensorClock {
    const val TOLERANCE_SECONDS = 10 * 60L

    /** The shift to add to the session start, or null if none is evident. */
    fun shift(sessionStart: Instant, offsetMinutes: Int, now: Instant): Duration? {
        val measured = sessionStart.plusSeconds(offsetMinutes * 60L)
        val deviation = Duration.between(measured, now).toMillis() / 1000.0
        if (abs(deviation) <= TOLERANCE_SECONDS) return null
        // The value is up to ~5 min old when it arrives; round to the nearest quarter hour.
        val quarters = (deviation / 900).roundToLong()
        if (quarters == 0L || abs(deviation - quarters * 900) > 6 * 60) return null
        return Duration.ofSeconds(quarters * 900)
    }
}
