// SPDX-License-Identifier: GPL-3.0-or-later
// CGM service payloads (Bluetooth CGMS + Medtronic usage, see OpenMinimed cgm-service.md) and
// Insulin Delivery Service payloads as used by the 780G (OpenMinimed idd-service.md).
// IDD values and most CGM values arrive SAKE-encrypted and are decrypted before parsing.
package de.sgitaize.minimedkit

import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

/** CGM Measurement record (GSS 3.43). The 780G always appends an E2E-CRC. */
data class CgmMeasurement(
    val glucoseMgdl: Double,
    /** Minutes since the start of the sensor session. */
    val timeOffsetMinutes: Int,
    val status: Int,
    val calTemp: Int,
    val warning: Int,
    /** Rate of change in mg/dL/min. */
    val trendMgdlPerMin: Double?,
    /** Quality as raw value; meaning on the 780G not yet verified. */
    val quality: Double?,
) {
    companion object {
        /** Parses a measurement record; throws on short data or a wrong E2E-CRC. */
        fun parse(data: ByteArray, hasE2eCrc: Boolean = true): CgmMeasurement {
            if (data.size < (if (hasE2eCrc) 8 else 6)) throw ParseError.TooShort
            if (hasE2eCrc && !Checksums.hasValidE2eCrc(data)) throw ParseError.CrcMismatch
            if (data.u8(0) != data.size) throw ParseError.LengthMismatch
            val r = ByteReader(if (hasE2eCrc) data.copyOf(data.size - 2) else data)
            r.u8() // size
            val flags = r.u8()
            val glucose = r.sfloat()
            val offset = r.u16()
            val status = if (flags and 0x80 != 0) r.u8() else 0
            val calTemp = if (flags and 0x40 != 0) r.u8() else 0
            val warning = if (flags and 0x20 != 0) r.u8() else 0
            val trend = if (flags and 0x01 != 0) r.sfloat() else null
            val quality = if (flags and 0x02 != 0) r.sfloat() else null
            r.expectEnd()
            return CgmMeasurement(glucose, offset, status, calTemp, warning, trend, quality)
        }
    }
}

/** CGM Session Start Time (GSS): date-time (7) + time zone (i8, 15 min) + DST (u8, 15 min) + E2E-CRC. */
data class CgmSessionStartTime(
    val localTime: LocalDateTime,
    val timeZoneOffsetMinutes: Int?,
    val dstOffsetMinutes: Int?,
) {
    /**
     * Absolute start time. If the pump does not send a time zone, its clock is
     * interpreted in [fallbackZone] (the phone's zone; the pump clock is local time).
     */
    fun instant(fallbackZone: ZoneId = ZoneId.systemDefault()): Instant {
        val tz = timeZoneOffsetMinutes
        return if (tz != null) {
            localTime.toInstant(ZoneOffset.ofTotalSeconds((tz + (dstOffsetMinutes ?: 0)) * 60))
        } else {
            localTime.atZone(fallbackZone).toInstant()
        }
    }

    companion object {
        /** Parses the session start time; throws on short data or a wrong E2E-CRC. */
        fun parse(data: ByteArray): CgmSessionStartTime {
            if (data.size != 11) throw ParseError.LengthMismatch
            if (!Checksums.hasValidE2eCrc(data)) throw ParseError.CrcMismatch
            val r = ByteReader(data)
            val time = readDateTime(r)
            val tz = r.i8()
            val dst = r.u8()
            return CgmSessionStartTime(time, if (tz == -128) null else tz * 15, if (dst == 0xFF) null else dst * 15)
        }
    }
}

/** Reads year (u16), month, day, hour, minute, second; invalid dates throw. */
internal fun readDateTime(r: ByteReader): LocalDateTime {
    val year = r.u16()
    val month = r.u8()
    val day = r.u8()
    val hour = r.u8()
    val minute = r.u8()
    val second = r.u8()
    return try {
        LocalDateTime.of(year, month, day, hour, minute, second)
    } catch (e: java.time.DateTimeException) {
        throw ParseError.LengthMismatch
    }
}

/**
 * Read-only Status Reader opcodes we are allowed to send. Everything else is blocked
 * by [ReadOnlyPolicy].
 */
enum class StatusReaderOpcode(val raw: Int, val responseOpcode: Int) {
    GET_ACTIVE_BASAL_RATE_DELIVERY(0x0365, 0x036A),
    GET_INSULIN_ON_BOARD(0x03F3, 0x03FC),
    GET_THERAPY_ALGORITHM_STATES(0x03FD, 0x03FE),
    GET_TIME_IN_RANGE(0x0401, 0x0402);

    val request: ByteArray get() = bytesOf(raw and 0xFF, raw shr 8)

    companion object {
        fun of(raw: Int): StatusReaderOpcode? = entries.firstOrNull { it.raw == raw }
    }
}

/** Opcode of a decrypted Status Reader indication (first two bytes, little-endian). */
fun statusReaderResponseOpcode(data: ByteArray): Int? =
    if (data.size < 2) null else data.u8(0) or (data.u8(1) shl 8)

/** IDD Status characteristic. */
data class PumpStatus(
    /** IDS therapy control state: 0x0F undetermined, 0x33 stop, 0x3C pause, 0x55 run. */
    val therapyControlState: Int,
    /** IDS operational state: 0x0F undetermined, 0x33 off, 0x3C standby, 0x55 preparing, 0x5A priming, 0x66 waiting, 0x96 ready. */
    val operationalState: Int,
    val reservoirUnits: Double,
    val reservoirAttached: Boolean,
    val sensorConnectivity: Int,
    val sensorMessageState: Int,
) {
    val isSuspended: Boolean get() = therapyControlState == PAUSE || therapyControlState == STOP
    val isRunning: Boolean get() = therapyControlState == RUN
    val sensorOn: Boolean get() = sensorConnectivity and 0x01 != 0
    val sensorSignalLost: Boolean get() = sensorConnectivity and 0x04 != 0

    /** No sensor message pending and a signal is there. */
    val sensorOk: Boolean
        get() = (sensorMessageState == 0x00 || sensorMessageState == 0x0C) && sensorOn && !sensorSignalLost

    /** German source text of the sensor message (localised by the app). */
    val sensorMessage: String
        get() = when (sensorMessageState) {
            0x00 -> "Sensor ok"
            0x01 -> "Warten auf Kalibrierung"
            0x02 -> "Sensor wird aktualisiert" // 780G with Simplera: no values for a while
            0x03 -> "Kalibrierung erforderlich"
            0x04 -> "Kalibriert"
            0x05 -> "Sensorsignal wird gesucht"
            0x06 -> "Kein Sensorsignal"
            0x07 -> "Sensor wechseln"
            0x08 -> "Aufwärmphase"
            0x09 -> "SG unter Messbereich"
            0x0A -> "SG über Messbereich"
            0x0B -> "Transmitter-Batterie leer"
            0x0C -> "Sensor verbunden"
            0x0D -> "Warten auf Aufwärmphase"
            0x0E -> "Kein Sensor gekoppelt"
            else -> "Unbekannt (0x%02x)".format(sensorMessageState)
        }

    companion object {
        const val STOP = 0x33
        const val PAUSE = 0x3C
        const val RUN = 0x55
        const val OPERATIONAL_READY = 0x96

        /** Parses the decrypted payload; throws if it is too short or malformed. */
        fun parse(data: ByteArray): PumpStatus {
            if (data.size != 9) throw ParseError.LengthMismatch
            val r = ByteReader(data)
            return PumpStatus(r.u8(), r.u8(), r.float32(), r.u8() and 0x01 != 0, r.u8(), r.u8())
        }
    }
}

/** Active insulin (IOB) as reported by the pump's status reader. */
data class InsulinOnBoard(val units: Double, val remainingDurationMinutes: Int?) {
    companion object {
        fun parse(data: ByteArray): InsulinOnBoard {
            val r = ByteReader(data)
            val opcode = r.u16()
            if (opcode != StatusReaderOpcode.GET_INSULIN_ON_BOARD.responseOpcode) throw ParseError.UnexpectedOpcode(opcode)
            val flags = r.u8()
            val units = r.float32()
            val remaining = if (flags and 0x01 != 0) r.u16() else null
            if (flags and 0x02 != 0) { r.u16(); r.u16() }
            r.expectEnd()
            return InsulinOnBoard(units, remaining)
        }
    }
}

/** Time in range statistics from the pump (percent of today). */
data class TimeInRange(
    val notEnoughData: Boolean,
    val abovePercent: Int,
    val belowPercent: Int,
    val inRangePercent: Int,
    val smartGuardPercent: Int,
) {
    companion object {
        fun parse(data: ByteArray): TimeInRange {
            if (data.size != 7) throw ParseError.LengthMismatch
            val r = ByteReader(data)
            val opcode = r.u16()
            if (opcode != StatusReaderOpcode.GET_TIME_IN_RANGE.responseOpcode) throw ParseError.UnexpectedOpcode(opcode)
            return TimeInRange(r.u8() != 0, r.u8(), r.u8(), r.u8(), r.u8())
        }
    }
}

/** SmartGuard algorithm state (Medtronic status reader opcode). */
data class TherapyAlgorithmStates(
    /** 1 manual mode (open loop), 2 SmartGuard auto basal, 3 safe basal; null if not reported. */
    val shieldState: Int?,
    val readinessState: Int?,
    val tempTargetMinutes: Int?,
    val safeBasalMinutes: Int?,
) {
    val isAutoBasal: Boolean get() = shieldState == AUTO_BASAL

    /** German source text of the mode (localised by the app). */
    val modeDescription: String
        get() = when (shieldState) {
            AUTO_BASAL -> "SmartGuard"
            SAFE_BASAL -> "Sicherheitsbasal"
            OPEN_LOOP -> "Manueller Modus"
            else -> "–"
        }

    companion object {
        const val OPEN_LOOP = 1
        const val AUTO_BASAL = 2
        const val SAFE_BASAL = 3

        fun parse(data: ByteArray): TherapyAlgorithmStates {
            val r = ByteReader(data)
            val opcode = r.u16()
            if (opcode != StatusReaderOpcode.GET_THERAPY_ALGORITHM_STATES.responseOpcode) throw ParseError.UnexpectedOpcode(opcode)
            val flags = r.u16()
            var shield: Int? = null
            var readiness: Int? = null
            if (flags and 0x01 != 0) {
                shield = r.u8().takeIf { it in OPEN_LOOP..SAFE_BASAL }
                readiness = r.u8()
            }
            if (flags and 0x04 != 0) r.u8() // PLGM state
            if (flags and 0x02 != 0) r.u8() // LGS state
            val tempTarget = if (flags and 0x08 != 0) r.u16() else null
            if (flags and 0x10 != 0) r.u16() // wait to calibrate
            val safeBasal = if (flags and 0x20 != 0) r.u16() else null
            r.expectEnd()
            return TherapyAlgorithmStates(shield, readiness, tempTarget, safeBasal)
        }
    }
}

/** Active basal rate and a running temporary basal, if any. */
data class ActiveBasalRate(
    val profileNumber: Int,
    val unitsPerHour: Double,
    val tempBasalUnitsPerHour: Double?,
    val tempBasalRemainingMinutes: Int?,
) {
    companion object {
        fun parse(data: ByteArray): ActiveBasalRate {
            val r = ByteReader(data)
            val opcode = r.u16()
            if (opcode != StatusReaderOpcode.GET_ACTIVE_BASAL_RATE_DELIVERY.responseOpcode) throw ParseError.UnexpectedOpcode(opcode)
            val flags = r.u8()
            val profile = r.u8()
            val rate = r.float32()
            var temp: Double? = null
            var remaining: Int? = null
            if (flags and 0x01 != 0) {
                r.u8() // TBR type
                temp = r.float32()
                r.u16() // programmed duration
                remaining = r.u16()
            }
            if (flags and 0x02 != 0) r.u8()
            if (flags and 0x04 != 0) r.u8()
            r.expectEnd()
            return ActiveBasalRate(profile, rate, temp, remaining)
        }
    }
}

/** IDD Status Changed (decrypted): flags. Bit 3 = annunciation status changed (IDS). */
@JvmInline
value class StatusChangedFlags(val raw: Int) {
    operator fun contains(flag: Int): Boolean = raw and flag != 0

    companion object {
        const val THERAPY_CONTROL_STATE = 1 shl 0
        const val OPERATIONAL_STATE = 1 shl 1
        const val RESERVOIR = 1 shl 2
        const val ANNUNCIATION = 1 shl 3
        const val TOTAL_DAILY_INSULIN = 1 shl 4
        const val ACTIVE_BASAL = 1 shl 5
        const val ACTIVE_BOLUS = 1 shl 6
        const val HISTORY = 1 shl 7

        /** Reads the flags from a decrypted Status Changed payload; null if too short. */
        fun parse(data: ByteArray): StatusChangedFlags? =
            if (data.size < 2) null else StatusChangedFlags(data.u8(0) or (data.u8(1) shl 8))
    }
}
