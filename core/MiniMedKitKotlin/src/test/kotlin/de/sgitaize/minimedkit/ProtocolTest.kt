// SPDX-License-Identifier: GPL-3.0-or-later
// Parser vectors: OpenMinimed PythonPumpConnector (real 780G payloads, GPL-3.0),
// identical to core/MiniMedKit/Tests/MiniMedKitTests/ProtocolTests.swift.
package de.sgitaize.minimedkit

import org.junit.Test
import java.time.Instant
import java.time.ZoneOffset
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProtocolTest {
    @Test
    fun e2eCrc() {
        assertTrue(Checksums.hasValidE2eCrc(hex("ea07031c0a1f2a80ff0873")))
        assertFalse(Checksums.hasValidE2eCrc(hex("ea07031c0a1f2a80ff0874")))
    }

    @Test
    fun medFloat() {
        assertEquals(-177.7, MedFloat.decode16(0xF90F))
        assertEquals(0.025, MedFloat.decode32(0xF82625A0L))
    }

    @Test
    fun cgmMeasurement() {
        val m = CgmMeasurement.parse(hex("0ec3f900f40b000074e00a00e0f1"))
        assertEquals(249.0, m.glucoseMgdl)
        assertEquals(3060, m.timeOffsetMinutes)
        assertEquals(1.16, m.trendMgdlPerMin)
        assertEquals(10.0, m.quality)

        val m2 = CgmMeasurement.parse(hex("0ec38d00e803000010e00a00d9af"))
        assertEquals(141.0, m2.glucoseMgdl)
        assertEquals(1000, m2.timeOffsetMinutes)

        assertFailsWith<ParseError> { CgmMeasurement.parse(hex("0ec3f900f40b000074e00a00e0f2")) }
    }

    @Test
    fun sessionStartTime() {
        val raw = hex("ea0704040c323680ff")
        val crc = Checksums.e2eCrc(raw)
        val t = CgmSessionStartTime.parse(raw + bytesOf(crc and 0xFF, crc shr 8))
        assertEquals(2026, t.localTime.year)
        assertEquals(12, t.localTime.hour)
        assertNull(t.timeZoneOffsetMinutes)
        assertEquals(1775307054, t.instant(ZoneOffset.UTC).epochSecond)
    }

    @Test
    fun pumpStatus() {
        val s = PumpStatus.parse(hex("5596e80d28fb010300"))
        assertEquals(PumpStatus.RUN, s.therapyControlState)
        assertEquals(PumpStatus.OPERATIONAL_READY, s.operationalState)
        assertEquals(26.25, s.reservoirUnits, 0.0001) // 0xfb280de8 = 2625000e-5
        assertTrue(s.reservoirAttached)
        assertTrue(s.sensorOn)
        assertFalse(s.isSuspended)
    }

    @Test
    fun insulinOnBoard() {
        val iob = InsulinOnBoard.parse(hex("fc0300c05c15fa"))
        assertEquals(1.4, iob.units, 0.0001)
        assertNull(iob.remainingDurationMinutes)
    }

    @Test
    fun timeInRange() {
        val tir = TimeInRange.parse(hex("0204001c024664"))
        assertEquals(28, tir.abovePercent)
        assertEquals(2, tir.belowPercent)
        assertEquals(70, tir.inRangePercent)
        assertEquals(100, tir.smartGuardPercent)
    }

    @Test
    fun therapyAlgorithmStates() {
        val tas = TherapyAlgorithmStates.parse(hex("fe0301000200"))
        assertEquals(TherapyAlgorithmStates.AUTO_BASAL, tas.shieldState)
        assertEquals("SmartGuard", tas.modeDescription)
    }

    @Test
    fun activeBasal() {
        val b = ActiveBasalRate.parse(hex("6a03000200000000"))
        assertEquals(2, b.profileNumber)
        assertEquals(0.0, b.unitsPerHour)
        assertNull(b.tempBasalUnitsPerHour)
    }

    @Test
    fun nightscoutDirections() {
        assertEquals("Flat", Nightscout.direction(0.4).first)
        assertEquals("SingleUp", Nightscout.direction(1.16).first)
        assertEquals("DoubleDown", Nightscout.direction(-2.5).first)
        assertEquals("NONE", Nightscout.direction(null).first)
    }

    @Test
    fun nightscoutEntryShape() {
        val r = GlucoseReading(Instant.ofEpochSecond(1_760_000_000), 123, -1.2, 50)
        val e = Nightscout.entry(r)
        assertEquals(123, e["sgv"])
        assertEquals("sgv", e["type"])
        assertEquals(1_760_000_000_000L, e["date"])
        assertEquals("SingleDown", e["direction"])
        assertEquals("2025-10-09T08:53:20.000Z", e["dateString"])
        assertNull(Nightscout.entry(r, includeId = false)["_id"])
    }

    @Test
    fun jsonWriter() {
        val json = Json.write(mapOf("b" to 1.5, "a" to listOf(true, null, "x\"y"), "c" to JsonNumber("0.050"), "d" to 6.0))
        assertEquals("""{"a":[true,null,"x\"y"],"b":1.5,"c":0.050,"d":6}""", json)
    }
}

class PebbleTest {
    @Test
    fun pebbleShape() {
        val base = Instant.ofEpochSecond(1_760_000_000)
        val readings = listOf(
            GlucoseReading(base, 120, 0.2, 1),
            GlucoseReading(base.plusSeconds(300), 126, 1.3, 6),
        )
        val p = Nightscout.pebble(readings, PumpSnapshot(updatedAt = base), 80, count = 2)
        @Suppress("UNCHECKED_CAST")
        val bgs = p["bgs"] as List<Map<String, Any?>>
        assertEquals(2, bgs.size)
        assertEquals("126", bgs[0]["sgv"])
        assertEquals(6.0, bgs[0]["bgdelta"])
        assertEquals("SingleUp", bgs[0]["direction"])
        assertEquals("80", bgs[0]["battery"])
        assertNull(bgs[1]["bgdelta"])

        val m = Nightscout.pebble(readings, null, null, mmol = true)
        @Suppress("UNCHECKED_CAST")
        val bg = (m["bgs"] as List<Map<String, Any?>>)[0]
        assertEquals("7.0", bg["sgv"])
        assertEquals(0.3, bg["bgdelta"])
    }
}
