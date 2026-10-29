// SPDX-License-Identifier: GPL-3.0-or-later
// Same cases as core/MiniMedKit/Tests/MiniMedKitTests/SensorClockTests.swift.
package de.sgitaize.minimedkit

import org.junit.Test
import java.time.Duration
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertNull

class SensorClockTest {
    private val now = Instant.ofEpochSecond(1_792_965_874)   // 2026-10-25 23:04:34 CET

    @Test
    fun noShiftWhenOnTime() {
        val start = now.minusSeconds(3 * 86400L + 30)
        assertNull(SensorClock.shift(start, 3 * 1440, now))
        // A value that is a few minutes old is normal latency.
        assertNull(SensorClock.shift(start.minusSeconds(240), 3 * 1440, now))
    }

    @Test
    fun daylightSavingShift() {
        // Live value lands one hour too early (end of DST).
        val start = now.minusSeconds(3 * 86400L + 3600 - 21)
        assertEquals(Duration.ofHours(1), SensorClock.shift(start, 3 * 1440, now))
        // One hour too late (start of DST).
        val late = now.minusSeconds(3 * 86400L - 3600 + 50)
        assertEquals(Duration.ofHours(-1), SensorClock.shift(late, 3 * 1440, now))
    }

    @Test
    fun ignoresDeviationsThatAreNoClockShift() {
        // 22 min off is neither latency nor whole quarter hours.
        val start = now.minusSeconds(3 * 86400L + 22 * 60)
        assertNull(SensorClock.shift(start, 3 * 1440, now))
    }
}
