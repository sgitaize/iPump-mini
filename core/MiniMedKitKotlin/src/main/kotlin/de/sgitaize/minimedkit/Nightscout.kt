// SPDX-License-Identifier: GPL-3.0-or-later
// Mapping of pump data to the Nightscout API v1 JSON shapes (entries, devicestatus,
// treatments, status, pebble). Field names follow cgm-remote-monitor.
package de.sgitaize.minimedkit

import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToLong

/** One sensor glucose value as shown and uploaded by the app. */
data class GlucoseReading(
    val date: Instant,
    val mgdl: Int,
    val trendMgdlPerMin: Double?,
    /** Sensor session time offset; identifies the record together with the session start. */
    val sessionOffsetMinutes: Int?,
)

/** Latest pump status as read in the last update cycle; every part is optional because reads can fail individually. */
data class PumpSnapshot(
    val updatedAt: Instant = Instant.EPOCH,
    val status: PumpStatus? = null,
    val iob: InsulinOnBoard? = null,
    val timeInRange: TimeInRange? = null,
    val algorithm: TherapyAlgorithmStates? = null,
    val basal: ActiveBasalRate? = null,
    val pumpBatteryPercent: Int? = null,
    val transmitterBatteryPercent: Int? = null,
    val sensorStart: Instant? = null,
    val sensorEnd: Instant? = null,
) {
    /** True once any status was read (updatedAt is EPOCH before). */
    val hasData: Boolean get() = updatedAt > Instant.EPOCH
}

/** Therapy event from the pump history, as shown in the chart and uploaded to Nightscout. */
data class Treatment(
    /** Pump history sequence number (stable across re-reads). */
    val id: Long,
    val date: Instant,
    val kind: Kind,
    /** Units (bolus, auto basal), grams (carbs), mg/dL (BG, calibration), U/h (basal). */
    val value: Double?,
) {
    /** Kinds of treatments derived from the pump history. */
    enum class Kind {
        /** User-initiated bolus (manual or bolus wizard, usually with carbs). */
        BOLUS,
        /** SmartGuard auto correction bolus. */
        AUTO_CORRECTION,
        AUTO_BASAL, CARBS, BG_CHECK, CALIBRATION, BASAL_CHANGE, SUSPEND, RESUME;

        val isAutomatic: Boolean get() = this == AUTO_BASAL || this == AUTO_CORRECTION
        val isInsulin: Boolean get() = this == BOLUS || this == AUTO_CORRECTION || this == AUTO_BASAL
    }

    companion object {
        /**
         * Builds treatments from a run of history events. A delivered bolus is classified with
         * the activation type of its second part (next record): "commanded" (0x5A) means a
         * SmartGuard auto correction.
         */
        fun from(events: List<TimedHistoryEvent>): List<Treatment> {
            val sorted = events.sortedBy { it.sequence }
            val details = mutableMapOf<Long, Int?>()
            for (e in sorted) {
                val ev = e.event
                if (ev is HistoryEvent.BolusDeliveredDetails) details[e.sequence] = ev.activationType
            }
            return sorted.mapNotNull { e ->
                val t = of(e) ?: return@mapNotNull null
                if (t.kind == Kind.BOLUS && details[e.sequence + 1] == 0x5A) t.copy(kind = Kind.AUTO_CORRECTION) else t
            }
        }

        /** Converts a history event into a treatment, or null for events that are not treatments. */
        fun of(e: TimedHistoryEvent): Treatment? = when (val ev = e.event) {
            is HistoryEvent.BolusDelivered ->
                if (ev.fastUnits + ev.extendedUnits > 0) Treatment(e.sequence, e.date, Kind.BOLUS, ev.fastUnits + ev.extendedUnits) else null
            is HistoryEvent.AutoBasal -> if (ev.units > 0) Treatment(e.sequence, e.date, Kind.AUTO_BASAL, ev.units) else null
            is HistoryEvent.Meal -> if (ev.grams > 0) Treatment(e.sequence, e.date, Kind.CARBS, ev.grams) else null
            is HistoryEvent.BgReading -> Treatment(e.sequence, e.date, Kind.BG_CHECK, ev.mgdl)
            is HistoryEvent.Calibration -> if (ev.accepted) Treatment(e.sequence, e.date, Kind.CALIBRATION, ev.mgdl) else null
            is HistoryEvent.BasalRateChanged -> Treatment(e.sequence, e.date, Kind.BASAL_CHANGE, ev.newUnitsPerHour)
            is HistoryEvent.DeliveryStopped -> Treatment(e.sequence, e.date, Kind.SUSPEND, null)
            is HistoryEvent.DeliveryRestarted -> Treatment(e.sequence, e.date, Kind.RESUME, null)
            else -> null
        }
    }
}

/** Mapping to the Nightscout API v1 JSON shapes (entries, devicestatus, treatments, status, /pebble). */
object Nightscout {
    const val DEVICE = "openMinipump"

    /**
     * Medtronic shows one arrow from 1 mg/dL/min, two from 2, three from 3.
     * Nightscout/Dexcom directions have no "three arrows" step that every client
     * understands, so three arrows map to Double* as well.
     */
    fun direction(rate: Double?): Pair<String, Int> = when {
        rate == null -> "NONE" to 0
        rate >= 2 -> "DoubleUp" to 1
        rate >= 1 -> "SingleUp" to 2
        rate >= -1 -> "Flat" to 4
        rate >= -2 -> "SingleDown" to 6
        else -> "DoubleDown" to 7
    }

    private val iso: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT).withZone(ZoneOffset.UTC)

    fun isoString(date: Instant): String = iso.format(date)

    /** Milliseconds since 1970, as Nightscout uses them in `date` fields. */
    fun millis(date: Instant): Long = date.toEpochMilli()

    /** @param includeId local API only. For uploads Nightscout assigns its own id. */
    fun entry(r: GlucoseReading, includeId: Boolean = true, zone: ZoneId = ZoneId.systemDefault()): Map<String, Any?> {
        val (dir, trend) = direction(r.trendMgdlPerMin)
        val ms = millis(r.date)
        val e = linkedMapOf<String, Any?>(
            "type" to "sgv",
            "sgv" to r.mgdl,
            "direction" to dir,
            "trend" to trend,
            "date" to ms,
            "dateString" to isoString(r.date),
            "sysTime" to isoString(r.date),
            "device" to DEVICE,
            "utcOffset" to zone.rules.getOffset(r.date).totalSeconds / 60,
        )
        if (includeId) e["_id"] = "omp-$ms"
        r.trendMgdlPerMin?.let { e["trendRate"] = it }
        return e
    }

    /** `devicestatus` document: reservoir, IOB, battery, suspend state and Medtronic extras under `pump.extended`. */
    fun deviceStatus(s: PumpSnapshot, uploaderBattery: Int?, now: Instant = Instant.now()): Map<String, Any?> {
        val pump = linkedMapOf<String, Any?>("clock" to isoString(s.updatedAt))
        s.status?.let { status ->
            pump["reservoir"] = status.reservoirUnits
            pump["status"] = mapOf(
                "status" to if (status.isSuspended) "suspended" else "normal",
                "suspended" to status.isSuspended,
                "timestamp" to isoString(s.updatedAt),
            )
        }
        s.iob?.let { pump["iob"] = mapOf("iob" to it.units, "bolusiob" to it.units, "timestamp" to isoString(s.updatedAt)) }
        s.pumpBatteryPercent?.let { pump["battery"] = mapOf("percent" to it) }
        val extended = linkedMapOf<String, Any?>()
        s.algorithm?.let { extended["mode"] = it.modeDescription }
        s.basal?.let { extended["basalRate"] = it.tempBasalUnitsPerHour ?: it.unitsPerHour }
        s.timeInRange?.let { extended["timeInRange"] = it.inRangePercent }
        s.transmitterBatteryPercent?.let { extended["transmitterBattery"] = it }
        s.sensorEnd?.let {
            extended["sensorEnd"] = isoString(it)
            extended["sensorExpiresInMinutes"] = java.time.Duration.between(now, it).toMinutes().toInt()
        }
        if (extended.isNotEmpty()) pump["extended"] = extended

        val ds = linkedMapOf<String, Any?>(
            "device" to DEVICE,
            "created_at" to isoString(s.updatedAt),
            "pump" to pump,
        )
        if (uploaderBattery != null) {
            ds["uploaderBattery"] = uploaderBattery
            ds["uploader"] = mapOf("battery" to uploaderBattery)
        }
        return ds
    }

    /**
     * Classic Nightscout `/pebble` endpoint (cgm-remote-monitor lib/server/pebble.js):
     * `?count=N` (default 1) and `?units=mmol`. Values are strings, the first entry carries
     * `bgdelta`, `battery` and `iob`.
     */
    fun pebble(
        readings: List<GlucoseReading>,
        snapshot: PumpSnapshot?,
        uploaderBattery: Int?,
        count: Int = 1,
        mmol: Boolean = false,
        now: Instant = Instant.now(),
    ): MutableMap<String, Any?> {
        val sorted = readings.sortedByDescending { it.date }
        fun fmt(mgdl: Int) = if (mmol) String.format(Locale.ROOT, "%.1f", mgdl / 18.0) else mgdl.toString()
        val bgs = mutableListOf<Map<String, Any?>>()
        sorted.take(count.coerceIn(1, 100)).forEachIndexed { i, r ->
            val (dir, trend) = direction(r.trendMgdlPerMin)
            val bg = linkedMapOf<String, Any?>(
                "sgv" to fmt(r.mgdl),
                "trend" to trend,
                "direction" to dir,
                "datetime" to millis(r.date),
            )
            if (i == 0) {
                // Delta only between consecutive 5-minute values (gap < 15 min), like Nightscout.
                if (sorted.size > 1 && java.time.Duration.between(sorted[1].date, r.date).seconds < 15 * 60) {
                    val d = r.mgdl - sorted[1].mgdl
                    bg["bgdelta"] = if (mmol) (d / 18.0 * 10).roundToLong() / 10.0 else d.toDouble()
                } else {
                    bg["bgdelta"] = 0
                }
                uploaderBattery?.let { bg["battery"] = it.toString() }
                snapshot?.iob?.let { bg["iob"] = String.format(Locale.ROOT, "%.2f", it.units) }
            }
            bgs.add(bg)
        }
        return linkedMapOf("status" to listOf(mapOf("now" to millis(now))), "bgs" to bgs, "cals" to emptyList<Any>())
    }

    /** `/api/v1/status.json` answer of the local server (read-only, mg/dl). */
    fun status(version: String, now: Instant = Instant.now()): Map<String, Any?> = linkedMapOf(
        "status" to "ok",
        "name" to DEVICE,
        "version" to version,
        "serverTime" to isoString(now),
        "serverTimeEpoch" to millis(now),
        "apiEnabled" to true,
        "careportalEnabled" to false,
        "settings" to mapOf("units" to "mg/dl", "customTitle" to DEVICE),
    )

    /** Exact decimal for JSON (avoids 0.05000000000000003). */
    internal fun dec(v: Double?, digits: Int = 3): JsonNumber =
        JsonNumber(java.math.BigDecimal(String.format(Locale.ROOT, "%.${digits}f", v ?: 0.0)).toPlainString())

    /**
     * Nightscout treatment (API v1). Auto basal micro boluses only if [includeAutoBasal],
     * basal rate changes are not uploaded (the pump status carries the current rate).
     */
    fun treatment(t: Treatment, includeAutoBasal: Boolean = false): Map<String, Any?>? {
        val out = linkedMapOf<String, Any?>(
            "created_at" to isoString(t.date),
            "enteredBy" to DEVICE,
            "pumpId" to t.id,
        )
        when (t.kind) {
            Treatment.Kind.BOLUS -> {
                out["eventType"] = "Correction Bolus"
                out["insulin"] = dec(t.value)
            }
            Treatment.Kind.AUTO_CORRECTION -> {
                out["eventType"] = "Correction Bolus"
                out["insulin"] = dec(t.value)
                out["automatic"] = true
                out["notes"] = "SmartGuard Autokorrektur"
            }
            Treatment.Kind.AUTO_BASAL -> {
                if (!includeAutoBasal) return null
                out["eventType"] = "Correction Bolus"
                out["insulin"] = dec(t.value)
                out["automatic"] = true
                out["type"] = "SMB"
            }
            Treatment.Kind.CARBS -> {
                out["eventType"] = "Carb Correction"
                out["carbs"] = dec(t.value, 0)
            }
            Treatment.Kind.BG_CHECK, Treatment.Kind.CALIBRATION -> {
                out["eventType"] = "BG Check"
                out["glucose"] = dec(t.value, 0)
                out["glucoseType"] = "Finger"
                out["units"] = "mg/dl"
                if (t.kind == Treatment.Kind.CALIBRATION) out["notes"] = "Kalibrierung"
            }
            Treatment.Kind.SUSPEND -> out["eventType"] = "Suspend Pump"
            Treatment.Kind.RESUME -> out["eventType"] = "Resume Pump"
            Treatment.Kind.BASAL_CHANGE -> return null
        }
        return out
    }
}
