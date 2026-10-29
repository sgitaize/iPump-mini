// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * App settings and small persistent state (SharedPreferences, app-private). Key names follow
 * the iOS app's UserDefaults where there is one.
 */
class Prefs(context: Context) {
    val sp: SharedPreferences = context.getSharedPreferences("openminipump", Context.MODE_PRIVATE)

    /** Bumped on every settings change, so Compose screens re-read values. */
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version

    fun changed() { _version.value++ }

    private fun bool(key: String, default: Boolean) = sp.getBoolean(key, default)
    private fun setBool(key: String, v: Boolean) { sp.edit().putBoolean(key, v).apply(); changed() }
    private fun int(key: String, default: Int) = sp.getInt(key, default)
    private fun setInt(key: String, v: Int) { sp.edit().putInt(key, v).apply(); changed() }
    private fun str(key: String, default: String = "") = sp.getString(key, default) ?: default
    private fun setStr(key: String, v: String) { sp.edit().putString(key, v).apply(); changed() }

    // Onboarding / terms
    var termsAcceptedVersion: Int get() = int("termsAcceptedVersion", 0); set(v) = setInt("termsAcceptedVersion", v)
    var termsAcceptedAt: Long get() = sp.getLong("termsAcceptedAt", 0); set(v) { sp.edit().putLong("termsAcceptedAt", v).apply() }

    // Pump link
    var advertisedName: String get() = str("advertisedName"); set(v) = setStr("advertisedName", v)
    var isPaired: Boolean get() = bool("isPaired", false); set(v) = setBool("isPaired", v)
    var pumpAddress: String get() = str("pumpAddress"); set(v) = setStr("pumpAddress", v)
    var demoMode: Boolean get() = bool("demoMode", false); set(v) = setBool("demoMode", v)

    // History sync (IDD RACP)
    var historyLastSeq: Long? get() = sp.getLong("historyLastSeq", -1).takeIf { it >= 0 }
        set(v) { sp.edit().putLong("historyLastSeq", v ?: -1).apply() }
    var historyRefSeq: Long? get() = sp.getLong("historyRefSeq", -1).takeIf { it >= 0 }
        set(v) { sp.edit().putLong("historyRefSeq", v ?: -1).apply() }
    var historyRefDate: Instant? get() = sp.getLong("historyRefDate", Long.MIN_VALUE).takeIf { it != Long.MIN_VALUE }?.let(Instant::ofEpochMilli)
        set(v) { sp.edit().putLong("historyRefDate", v?.toEpochMilli() ?: Long.MIN_VALUE).apply() }
    /** Session start as reported by the pump and the correction applied to it (clock shift, see SensorClock). */
    var sessionStartReported: Instant? get() = sp.getLong("sessionStartReported", Long.MIN_VALUE).takeIf { it != Long.MIN_VALUE }?.let(Instant::ofEpochMilli)
        set(v) { sp.edit().putLong("sessionStartReported", v?.toEpochMilli() ?: Long.MIN_VALUE).apply() }
    var sessionStartShiftSeconds: Long get() = sp.getLong("sessionStartShift", 0); set(v) { sp.edit().putLong("sessionStartShift", v).apply() }
    var historyVersion: Int get() = int("historyVersion", 0); set(v) = setInt("historyVersion", v)

    // Display
    var theme: String get() = str("appTheme", "system"); set(v) = setStr("appTheme", v)
    var unitMmol: Boolean get() = str("glucoseUnit", "mgdl") == "mmol"; set(v) = setStr("glucoseUnit", if (v) "mmol" else "mgdl")
    var low: Int get() = int("rangeLow", 70); set(v) = setInt("rangeLow", v)
    var high: Int get() = int("rangeHigh", 180); set(v) = setInt("rangeHigh", v)
    var chartHours: Int get() = int("chartHours", 3); set(v) = setInt("chartHours", v)
    /** "", "simplera" or "guardian" (Guardian 4 has a transmitter with battery). */
    var sensorType: String get() = str("sensorType"); set(v) = setStr("sensorType", v)
    val hasTransmitter: Boolean get() = sensorType != "simplera"

    // Nightscout
    var nsEnabled: Boolean get() = bool("nsEnabled", false); set(v) = setBool("nsEnabled", v)
    var nsUrl: String get() = str("nsURL"); set(v) = setStr("nsURL", v)
    var nsSecret: String get() = str("nsSecret"); set(v) = setStr("nsSecret", v)
    var nsDeviceStatus: Boolean get() = bool("nsDeviceStatus", true); set(v) = setBool("nsDeviceStatus", v)
    var nsTreatments: Boolean get() = bool("nsTreatments", true); set(v) = setBool("nsTreatments", v)
    var nsAutoBasal: Boolean get() = bool("nsAutoBasal", false); set(v) = setBool("nsAutoBasal", v)
    var nsLastEntry: Long get() = sp.getLong("nsLastEntry", 0); set(v) { sp.edit().putLong("nsLastEntry", v).apply() }
    var nsLastTreatment: Long get() = sp.getLong("nsLastTreatment", 0); set(v) { sp.edit().putLong("nsLastTreatment", v).apply() }

    // Local API
    var apiAllowLan: Boolean get() = bool("apiAllowLAN", false); set(v) = setBool("apiAllowLAN", v)
    var apiSecret: String get() = str("apiSecret"); set(v) = setStr("apiSecret", v)

    // Pebble monitor
    var pebbleMonitor: Boolean get() = bool("pebbleMonitor", false); set(v) = setBool("pebbleMonitor", v)
    var pebbleMinutes: Int get() = int("pebbleMonitorMinutes", 20); set(v) = setInt("pebbleMonitorMinutes", v)

    /** Imported SAKE key database (public builds ship without it). App-private storage. */
    var importedKeyDatabase: String get() = str("sakeKeyDatabase"); set(v) = setStr("sakeKeyDatabase", v)
}

/** Display unit; Nightscout and the local API always stay in mg/dL. */
object Units {
    const val MMOL_FACTOR = 18.0182

    fun format(mgdl: Int, mmol: Boolean): String =
        if (mmol) String.format(java.util.Locale.getDefault(), "%.1f", mgdl / MMOL_FACTOR) else mgdl.toString()

    fun label(mmol: Boolean) = if (mmol) "mmol/L" else "mg/dL"

    fun formatDelta(d: Int?, mmol: Boolean): String {
        if (d == null) return ""
        if (!mmol) return if (d > 0) "+$d" else if (d == 0) "±0" else "$d"
        val v = d / MMOL_FACTOR
        return if (abs(v) < 0.05) "±0.0" else String.format(java.util.Locale.getDefault(), "%+.1f", v)
    }

    /** Medtronic arrows: 1 from 1 mg/dL/min, 2 from 2, 3 from 3. */
    fun arrow(rate: Double?): String {
        if (rate == null) return ""
        val n = minOf(3, abs(rate).toInt())
        return if (n == 0) "→" else (if (rate > 0) "↑" else "↓").repeat(n)
    }

    fun insulin(units: Double, digits: Int): String =
        String.format(java.util.Locale.getDefault(), "%.${digits}f", units) + " " + OpenMinipumpApp.string(R.string.unit_ie)

    fun mgdlOf(value: Double): Int = value.roundToInt()
}
