// SPDX-License-Identifier: GPL-3.0-or-later
// IDD History Data records (IDS + Medtronic events), read via the IDD RACP.
// Record layout and event formats from OpenMinimed (PythonPumpConnector history/data.py,
// Documentation/idd-service.md). Records arrive SAKE-encrypted and are decrypted first.
package de.sgitaize.minimedkit

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.math.roundToLong

/** Decoded IDD history event types the app uses (Medtronic types 0xF0xx and IDS types). */
sealed class HistoryEvent {
    /**
     * Pump clock reference (local time, no time zone). Later records count their
     * relative offset (seconds) from the latest reference.
     */
    data class ReferenceTime(val time: LocalDateTime) : HistoryEvent()
    data class BolusDelivered(val id: Int, val fastUnits: Double, val extendedUnits: Double, val durationMinutes: Int) : HistoryEvent()

    /**
     * Second part of a delivered bolus (follows part 1). Activation type (IDS): 0x33 manual,
     * 0x3C recommended (bolus wizard), 0x55 recommendation changed by the user,
     * 0x5A commanded (SmartGuard auto correction).
     */
    data class BolusDeliveredDetails(val activationType: Int?) : HistoryEvent()

    /** SmartGuard auto basal (micro bolus). */
    data class AutoBasal(val units: Double) : HistoryEvent()
    data class Meal(val grams: Double) : HistoryEvent()
    data class BgReading(val mgdl: Double) : HistoryEvent()
    data class Calibration(val mgdl: Double, val accepted: Boolean) : HistoryEvent()
    data class BasalRateChanged(val oldUnitsPerHour: Double, val newUnitsPerHour: Double) : HistoryEvent()
    data class DeliveryStopped(val reason: Int) : HistoryEvent()
    data class DeliveryRestarted(val reason: Int) : HistoryEvent()

    /** Sensor value from the pump history; null for special states (warm-up, out of range…). */
    data class SensorGlucose(val mgdl: Int?) : HistoryEvent()

    /**
     * Pump alert/alarm (Annunciation Consolidated). Status: 0x33 pending, 0x3C snoozed,
     * 0x55 confirmed. Type without the 0xF000 marker.
     */
    data class Annunciation(val id: Int, val type: Int, val status: Int) : HistoryEvent()
    data class Other(val type: Int) : HistoryEvent()
}

/** One IDD history record: event type, sequence number, offset to the reference time and the decoded event. */
data class HistoryRecord(
    val eventType: Int,
    val sequence: Long,
    /** Seconds since the latest reference time event. */
    val relativeOffset: Int,
    val event: HistoryEvent,
) {
    companion object {
        /** Parses a decrypted history record (after the E2E-CRC check). */
        fun parse(data: ByteArray): HistoryRecord {
            val r = ByteReader(data)
            val type = r.u16()
            val seq = r.u32()
            val offset = r.u16()
            return HistoryRecord(type, seq, offset, parseEvent(type, r))
        }

        /** kg/L as used by the pump for BG values → mg/dL. */
        internal fun mgdl(kgPerL: Double): Double = (kgPerL * 100_000).roundToLong().toDouble()

        private fun parseEvent(type: Int, r: ByteReader): HistoryEvent = when (type) {
            0xF00E -> { // NGP reference time: recording reason + date-time
                r.u8()
                val time = readDateTime(r)
                r.expectEnd()
                HistoryEvent.ReferenceTime(time)
            }
            0x0069 -> { // Bolus Delivered P1
                val id = r.u16()
                r.u8() // bolus type
                val fast = r.float32()
                val ext = r.float32()
                val duration = r.u16()
                r.expectEnd()
                HistoryEvent.BolusDelivered(id, fast, ext, duration)
            }
            0x0096 -> { // Bolus Delivered P2: flags, start time offset, [activation], [end reason], [annunciation]
                val flags = r.u8()
                r.u32()
                val activation = if (flags and 0x01 != 0) r.u8() else null
                if (flags and 0x02 != 0) r.u8()
                if (flags and 0x04 != 0) r.u16()
                r.expectEnd()
                HistoryEvent.BolusDeliveredDetails(activation)
            }
            0xF001 -> { // Auto basal delivery
                r.u8()
                val units = r.float32()
                r.expectEnd()
                HistoryEvent.AutoBasal(units)
            }
            0xF005 -> { // Meal
                val grams = r.sfloat()
                r.expectEnd()
                HistoryEvent.Meal(grams)
            }
            0xF007 -> { // BG reading
                r.u16() // time offset
                val bg = r.sfloat()
                r.expectEnd()
                HistoryEvent.BgReading(mgdl(bg))
            }
            0xF008, 0xF009 -> { // Calibration complete / rejected
                r.u16()
                val bg = r.sfloat()
                r.expectEnd()
                HistoryEvent.Calibration(mgdl(bg), type == 0xF008)
            }
            0x0099 -> { // Delivered basal rate changed
                val flags = r.u8()
                val old = r.float32()
                val new = r.float32()
                if (flags and 0x01 != 0) r.u8()
                r.expectEnd()
                HistoryEvent.BasalRateChanged(old, new)
            }
            0xF00A -> HistoryEvent.DeliveryStopped(r.u8()).also { r.expectEnd() }
            0xF00B -> HistoryEvent.DeliveryRestarted(r.u8()).also { r.expectEnd() }
            0xF00C -> { // SG measurement: time offset, SG, ISIG, V counter
                r.u16()
                val sg = r.u16()
                r.u16()
                r.u16()
                r.expectEnd()
                // Values from 0x0300 on encode sensor states, not glucose.
                HistoryEvent.SensorGlucose(if (sg < 0x0300 && sg in 40..400) sg else null)
            }
            0xF010 -> { // Annunciation Consolidated: flags, id, type (0xF…), status, timestamp, aux…
                r.u8()
                val id = r.u16()
                val annType = r.u16()
                val status = r.u8()
                // The auxiliary data that follows depends on the type; it is not needed here.
                HistoryEvent.Annunciation(id, annType and 0x0FFF, status)
            }
            else -> HistoryEvent.Other(type)
        }
    }
}

/** A history event with its absolute time. */
data class TimedHistoryEvent(val sequence: Long, val date: Instant, val event: HistoryEvent)

/** Latest NGP reference time: history sequence number and the pump clock at that point. */
data class HistoryReference(val sequence: Long, val date: Instant)

/** Turns relative history offsets into absolute dates using the NGP reference time events. */
object HistoryTimeline {
    /**
     * Resolves absolute times. [reference] is the latest reference time known before the
     * first record (sequence + pump clock). Records before any reference are dropped.
     */
    fun resolve(
        records: List<HistoryRecord>,
        reference: HistoryReference?,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Pair<List<TimedHistoryEvent>, HistoryReference?> {
        var ref = reference
        val out = mutableListOf<TimedHistoryEvent>()
        for (record in records.sortedBy { it.sequence }) {
            val event = record.event
            if (event is HistoryEvent.ReferenceTime) {
                ref = HistoryReference(record.sequence, event.time.atZone(zone).toInstant())
                continue
            }
            val current = ref ?: continue
            if (record.sequence <= current.sequence) continue
            out.add(TimedHistoryEvent(record.sequence, current.date.plusSeconds(record.relativeOffset.toLong()), event))
        }
        return out to ref
    }
}
