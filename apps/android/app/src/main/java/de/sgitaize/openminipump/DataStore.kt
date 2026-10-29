// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.content.Context
import android.os.BatteryManager
import de.sgitaize.minimedkit.ActiveBasalRate
import de.sgitaize.minimedkit.GlucoseReading
import de.sgitaize.minimedkit.InsulinOnBoard
import de.sgitaize.minimedkit.PumpSnapshot
import de.sgitaize.minimedkit.PumpStatus
import de.sgitaize.minimedkit.TherapyAlgorithmStates
import de.sgitaize.minimedkit.TimeInRange
import de.sgitaize.minimedkit.Treatment
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Duration
import java.time.Instant
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

data class IobSample(val date: Instant, val units: Double)

/**
 * Holds the data read from the pump and persists it. Mutated on the main thread only; the
 * StateFlows are read by the UI and (as immutable snapshots) by the local API server.
 */
class DataStore(private val context: Context) {
    private val _readings = MutableStateFlow<List<GlucoseReading>>(emptyList())
    val readings: StateFlow<List<GlucoseReading>> = _readings
    private val _snapshot = MutableStateFlow(PumpSnapshot())
    val snapshot: StateFlow<PumpSnapshot> = _snapshot
    private val _lastDataAt = MutableStateFlow<Instant?>(null)
    val lastDataAt: StateFlow<Instant?> = _lastDataAt
    private val _treatments = MutableStateFlow<List<Treatment>>(emptyList())
    val treatments: StateFlow<List<Treatment>> = _treatments
    /** Insulin on board over time (one sample per pump refresh), for the chart details. */
    private val _iobHistory = MutableStateFlow<List<IobSample>>(emptyList())
    val iobHistory: StateFlow<List<IobSample>> = _iobHistory

    /** Called once per genuinely new sensor value (not for updates of a known one). */
    var onNewReading: (() -> Unit)? = null

    /** false in demo mode: nothing is written to disk, so real data stays untouched. */
    var persistenceEnabled = true
        private set

    private val retention: Duration = Duration.ofDays(7)
    private val file = File(context.filesDir, "openminipump-store.json")

    init {
        load()
    }

    val latest: GlucoseReading? get() = _readings.value.lastOrNull()

    /** Phone battery in percent, for Nightscout and the local API. */
    fun uploaderBattery(): Int? {
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return null
        return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).takeIf { it in 0..100 }
    }

    /** IOB sample closest to [date] (within 5 min). */
    fun iobAt(date: Instant): Double? = _iobHistory.value
        .minByOrNull { abs(Duration.between(it.date, date).seconds) }
        ?.takeIf { abs(Duration.between(it.date, date).seconds) <= 300 }?.units

    fun add(reading: GlucoseReading) {
        val list = _readings.value.toMutableList()
        // Same sensor record (offset) or a value within 2 minutes counts as duplicate.
        val i = list.indexOfLast {
            (it.sessionOffsetMinutes != null && it.sessionOffsetMinutes == reading.sessionOffsetMinutes &&
                abs(Duration.between(it.date, reading.date).seconds) < 3600) ||
                abs(Duration.between(it.date, reading.date).seconds) < 120
        }
        if (i >= 0) {
            list[i] = reading
            list.sortBy { it.date }
            _readings.value = list
            touched()
            return
        }
        list.add(reading)
        list.sortBy { it.date }
        val cutoff = Instant.now().minus(retention)
        list.removeAll { it.date < cutoff }
        _readings.value = list
        touched()
        onNewReading?.invoke()
    }

    /**
     * Merges values from the pump history. Does not trigger the "new reading" upload;
     * returns the values that were actually new.
     */
    fun merge(incoming: List<GlucoseReading>): List<GlucoseReading> {
        val list = _readings.value.toMutableList()
        val added = mutableListOf<GlucoseReading>()
        val now = Instant.now()
        val cutoff = now.minus(retention)
        for (r in incoming) {
            if (r.date < cutoff || r.date > now.plusSeconds(300)) continue
            if (list.any { abs(Duration.between(it.date, r.date).seconds) < 120 }) continue
            list.add(r)
            added.add(r)
        }
        if (added.isEmpty()) return emptyList()
        list.sortBy { it.date }
        _readings.value = list
        touched()
        return added
    }

    /** Adds pump history treatments (deduplicated by sequence number); returns the new ones. */
    fun addTreatments(incoming: List<Treatment>): List<Treatment> {
        val known = _treatments.value.map { it.id }.toSet()
        val new = incoming.filter { it.id !in known }
        if (new.isEmpty()) return emptyList()
        val cutoff = Instant.now().minus(retention)
        _treatments.value = (_treatments.value + new).sortedBy { it.date }.filter { it.date >= cutoff }
        touched()
        return new
    }

    fun resetTreatments() {
        _treatments.value = emptyList()
        touched()
    }

    fun update(change: (PumpSnapshot) -> PumpSnapshot) {
        val old = _snapshot.value
        val new = change(old).copy(updatedAt = Instant.now())
        val iob = new.iob
        val lastSample = _iobHistory.value.lastOrNull()
        if (iob != null && (iob != old.iob || lastSample == null || Duration.between(lastSample.date, Instant.now()).seconds > 240)) {
            val cutoff = Instant.now().minus(retention)
            _iobHistory.value = (_iobHistory.value + IobSample(Instant.now(), iob.units)).filter { it.date >= cutoff }
        }
        _snapshot.value = new
        touched()
    }

    private fun touched() {
        _lastDataAt.value = Instant.now()
        save()
    }

    // MARK: Demo mode

    /**
     * Synthetic values for demo mode (trying the app, screenshots). Disables saving and adds
     * a new simulated value every 5 minutes.
     */
    fun loadDemoData() {
        persistenceEnabled = false
        val now = Instant.now()
        _readings.value = (0 until 72).map { i ->
            val t = (71 - i).toDouble()
            GlucoseReading(now.minusSeconds((t * 300).toLong()), (130 + 50 * sin(t / 9)).toInt(), -50.0 / 45.0 * cos(t / 9), 5000 - t.toInt() * 5)
        }
        fun at(min: Long) = now.minusSeconds(min * 60)
        _treatments.value = (listOf(
            Treatment(1, at(150), Treatment.Kind.CARBS, 45.0),
            Treatment(2, at(148), Treatment.Kind.BOLUS, 3.5),
            Treatment(3, at(60), Treatment.Kind.CALIBRATION, 152.0),
            Treatment(4, at(40), Treatment.Kind.AUTO_CORRECTION, 0.45),
            Treatment(5, at(25), Treatment.Kind.AUTO_CORRECTION, 0.6),
        ) + (0 until 36).map { i ->
            Treatment(10L + i, now.minusSeconds(i * 300L), Treatment.Kind.AUTO_BASAL, listOf(0.05, 0.1, 0.0, 0.15, 0.05)[i % 5])
        }.filter { (it.value ?: 0.0) > 0 }).sortedBy { it.date }
        _iobHistory.value = (0 until 72).map { IobSample(now.minusSeconds((71L - it) * 300), maxOf(0.0, 3.2 - it * 0.03)) }
        _snapshot.value = PumpSnapshot(
            updatedAt = now,
            status = PumpStatus(PumpStatus.RUN, PumpStatus.OPERATIONAL_READY, 142.0, true, 1, 0),
            iob = InsulinOnBoard(1.85, 150),
            timeInRange = TimeInRange(false, 14, 2, 84, 98),
            algorithm = TherapyAlgorithmStates(TherapyAlgorithmStates.AUTO_BASAL, 0, null, null),
            basal = ActiveBasalRate(1, 0.85, null, null),
            pumpBatteryPercent = 75,
            transmitterBatteryPercent = 100,
            sensorEnd = now.plusSeconds(3 * 86400 + 5 * 3600),
        )
        _lastDataAt.value = now
        OpenMinipumpApp.main.removeCallbacks(demoTick)
        OpenMinipumpApp.main.postDelayed(demoTick, 300_000)
    }

    /** Adds a new simulated value every 5 minutes. */
    private val demoTick: Runnable = object : Runnable {
        override fun run() {
            val t = Instant.now().epochSecond / 300.0
            add(GlucoseReading(Instant.now(), (130 + 50 * sin(t / 9)).toInt(), 50.0 / 45.0 * cos(t / 9), null))
            OpenMinipumpApp.main.postDelayed(this, 300_000)
        }
    }

    // MARK: Persistence

    private fun save() {
        if (!persistenceEnabled) return
        try {
            val json = JSONObject()
            json.put("readings", JSONArray(_readings.value.map(::readingJson)))
            json.put("snapshot", snapshotJson(_snapshot.value))
            _lastDataAt.value?.let { json.put("lastDataAt", it.toEpochMilli()) }
            json.put("treatments", JSONArray(_treatments.value.map {
                JSONObject().put("id", it.id).put("date", it.date.toEpochMilli()).put("kind", it.kind.name).putOpt("value", it.value)
            }))
            json.put("iobHistory", JSONArray(_iobHistory.value.map { JSONObject().put("date", it.date.toEpochMilli()).put("units", it.units) }))
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(json.toString())
            tmp.renameTo(file)
        } catch (_: Exception) {
        }
    }

    private fun load() {
        if (!file.exists()) return
        try {
            val json = JSONObject(file.readText())
            _readings.value = json.optJSONArray("readings").objects().map {
                GlucoseReading(Instant.ofEpochMilli(it.getLong("date")), it.getInt("mgdl"), it.optDoubleOrNull("trend"), it.optIntOrNull("offset"))
            }
            json.optJSONObject("snapshot")?.let { _snapshot.value = snapshotFrom(it) }
            if (json.has("lastDataAt")) _lastDataAt.value = Instant.ofEpochMilli(json.getLong("lastDataAt"))
            _treatments.value = json.optJSONArray("treatments").objects().mapNotNull {
                val kind = runCatching { Treatment.Kind.valueOf(it.getString("kind")) }.getOrNull() ?: return@mapNotNull null
                Treatment(it.getLong("id"), Instant.ofEpochMilli(it.getLong("date")), kind, it.optDoubleOrNull("value"))
            }
            _iobHistory.value = json.optJSONArray("iobHistory").objects().map {
                IobSample(Instant.ofEpochMilli(it.getLong("date")), it.getDouble("units"))
            }
        } catch (_: Exception) {
        }
    }

    private fun readingJson(r: GlucoseReading) = JSONObject().put("date", r.date.toEpochMilli()).put("mgdl", r.mgdl)
        .putOpt("trend", r.trendMgdlPerMin).putOpt("offset", r.sessionOffsetMinutes)

    private fun snapshotJson(s: PumpSnapshot): JSONObject = JSONObject().apply {
        put("updatedAt", s.updatedAt.toEpochMilli())
        s.status?.let {
            put("status", JSONObject().put("tcs", it.therapyControlState).put("ops", it.operationalState).put("res", it.reservoirUnits)
                .put("att", it.reservoirAttached).put("con", it.sensorConnectivity).put("msg", it.sensorMessageState))
        }
        s.iob?.let { put("iob", JSONObject().put("units", it.units).putOpt("remaining", it.remainingDurationMinutes)) }
        s.timeInRange?.let {
            put("tir", JSONObject().put("ned", it.notEnoughData).put("above", it.abovePercent).put("below", it.belowPercent)
                .put("in", it.inRangePercent).put("sg", it.smartGuardPercent))
        }
        s.algorithm?.let {
            put("algo", JSONObject().putOpt("shield", it.shieldState).putOpt("ready", it.readinessState)
                .putOpt("temp", it.tempTargetMinutes).putOpt("safe", it.safeBasalMinutes))
        }
        s.basal?.let {
            put("basal", JSONObject().put("profile", it.profileNumber).put("rate", it.unitsPerHour)
                .putOpt("temp", it.tempBasalUnitsPerHour).putOpt("tempRemaining", it.tempBasalRemainingMinutes))
        }
        putOpt("pumpBattery", s.pumpBatteryPercent)
        putOpt("transmitterBattery", s.transmitterBatteryPercent)
        s.sensorStart?.let { put("sensorStart", it.toEpochMilli()) }
        s.sensorEnd?.let { put("sensorEnd", it.toEpochMilli()) }
    }

    private fun snapshotFrom(o: JSONObject) = PumpSnapshot(
        updatedAt = Instant.ofEpochMilli(o.optLong("updatedAt", 0)),
        status = o.optJSONObject("status")?.let {
            PumpStatus(it.getInt("tcs"), it.getInt("ops"), it.getDouble("res"), it.getBoolean("att"), it.getInt("con"), it.getInt("msg"))
        },
        iob = o.optJSONObject("iob")?.let { InsulinOnBoard(it.getDouble("units"), it.optIntOrNull("remaining")) },
        timeInRange = o.optJSONObject("tir")?.let {
            TimeInRange(it.getBoolean("ned"), it.getInt("above"), it.getInt("below"), it.getInt("in"), it.getInt("sg"))
        },
        algorithm = o.optJSONObject("algo")?.let {
            TherapyAlgorithmStates(it.optIntOrNull("shield"), it.optIntOrNull("ready"), it.optIntOrNull("temp"), it.optIntOrNull("safe"))
        },
        basal = o.optJSONObject("basal")?.let {
            ActiveBasalRate(it.getInt("profile"), it.getDouble("rate"), it.optDoubleOrNull("temp"), it.optIntOrNull("tempRemaining"))
        },
        pumpBatteryPercent = o.optIntOrNull("pumpBattery"),
        transmitterBatteryPercent = o.optIntOrNull("transmitterBattery"),
        sensorStart = o.optLongOrNull("sensorStart")?.let(Instant::ofEpochMilli),
        sensorEnd = o.optLongOrNull("sensorEnd")?.let(Instant::ofEpochMilli),
    )
}

private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }
private fun JSONObject.optDoubleOrNull(key: String): Double? = if (has(key) && !isNull(key)) getDouble(key) else null
private fun JSONObject.optIntOrNull(key: String): Int? = if (has(key) && !isNull(key)) getInt(key) else null
private fun JSONObject.optLongOrNull(key: String): Long? = if (has(key) && !isNull(key)) getLong(key) else null
