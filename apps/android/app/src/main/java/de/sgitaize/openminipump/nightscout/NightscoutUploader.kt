// SPDX-License-Identifier: GPL-3.0-or-later
// Optional upload to the user's own Nightscout (API v1). Android port of
// apps/ios/OpenMinipump/Nightscout/NightscoutUploader.swift.
package de.sgitaize.openminipump.nightscout

import de.sgitaize.minimedkit.Json
import de.sgitaize.minimedkit.Nightscout
import de.sgitaize.openminipump.DataStore
import de.sgitaize.openminipump.EventLog
import de.sgitaize.openminipump.OpenMinipumpApp
import de.sgitaize.openminipump.Prefs
import de.sgitaize.openminipump.R
import de.sgitaize.openminipump.api.LocalApiServer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLEncoder
import java.time.Instant
import java.util.concurrent.Executors

class NightscoutUploader(private val prefs: Prefs, private val store: DataStore, private val log: EventLog) {
    private val _lastSuccess = MutableStateFlow<Instant?>(null)
    val lastSuccess: StateFlow<Instant?> = _lastSuccess
    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError

    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var running = false
    private var lastDeviceStatus: Instant = Instant.EPOCH

    /** Set in demo mode: never upload simulated values. */
    @Volatile var disabled = false

    /**
     * Pump history added values/treatments: older sensor values must be uploaded too
     * (Nightscout deduplicates entries by date and type).
     */
    fun historyAdded(oldestReading: Instant?) {
        if (!prefs.nsEnabled) return
        if (oldestReading != null && oldestReading.toEpochMilli() <= prefs.nsLastEntry) {
            prefs.nsLastEntry = oldestReading.toEpochMilli() - 1000
        }
        syncAsync()
    }

    /** Uploads when a new sensor value arrived; the pump status of the same cycle goes along. */
    fun newReading() {
        if (prefs.nsEnabled) syncAsync()
    }

    fun syncAsync() {
        executor.execute { sync() }
    }

    private fun sync() {
        if (!prefs.nsEnabled || running || disabled) return
        val base = baseUrl() ?: return
        running = true
        try {
            val lastEntry = prefs.nsLastEntry
            val newReadings = store.readings.value.filter { it.date.toEpochMilli() > lastEntry }.takeLast(288)
            if (newReadings.isNotEmpty()) {
                post(base, "api/v1/entries", newReadings.map { Nightscout.entry(it, includeId = false) })
                prefs.nsLastEntry = newReadings.last().date.toEpochMilli()
                log.add("Nightscout: ${newReadings.size} Wert(e) hochgeladen")
            }
            if (prefs.nsTreatments) {
                val lastId = prefs.nsLastTreatment
                val pending = store.treatments.value.filter { it.id > lastId }
                val body = pending.mapNotNull { Nightscout.treatment(it, includeAutoBasal = prefs.nsAutoBasal) }
                if (body.isNotEmpty()) {
                    post(base, "api/v1/treatments", body)
                    log.add("Nightscout: ${body.size} Behandlung(en) hochgeladen")
                }
                pending.maxOfOrNull { it.id }?.let { prefs.nsLastTreatment = it }
            }
            val snap = store.snapshot.value
            if (prefs.nsDeviceStatus && snap.updatedAt > lastDeviceStatus) {
                post(base, "api/v1/devicestatus", Nightscout.deviceStatus(snap, store.uploaderBattery()))
                lastDeviceStatus = snap.updatedAt
            }
            _lastSuccess.value = Instant.now()
            _lastError.value = null
        } catch (e: Exception) {
            _lastError.value = e.message ?: e.javaClass.simpleName
            log.warn("Nightscout-Upload fehlgeschlagen: ${e.message}")
        } finally {
            running = false
        }
    }

    /** Checks URL and secret with GET /api/v1/verifyauth (read-only request). Blocking. */
    fun test(): String {
        val base = baseUrl() ?: return OpenMinipumpApp.string(R.string.ns_invalid_url)
        return try {
            val conn = open(base, "api/v1/verifyauth")
            val code = conn.responseCode
            if (code != 200) return "HTTP $code"
            val json = runCatching { JSONObject(conn.inputStream.bufferedReader().readText()) }.getOrNull()
            val message = json?.opt("message")
            when {
                message is JSONObject && message.optBoolean("canWrite") -> OpenMinipumpApp.string(R.string.ns_ok_write)
                message is JSONObject -> OpenMinipumpApp.string(R.string.ns_no_write)
                message == "OK" -> OpenMinipumpApp.string(R.string.ns_ok_secret)
                else -> OpenMinipumpApp.string(R.string.ns_secret_unconfirmed)
            }
        } catch (e: Exception) {
            e.message ?: e.javaClass.simpleName
        }
    }

    fun resetUploadMarker() {
        val dayAgo = Instant.now().minusSeconds(24 * 3600)
        prefs.nsLastEntry = dayAgo.toEpochMilli()
        lastDeviceStatus = Instant.EPOCH
        prefs.nsLastTreatment = store.treatments.value.lastOrNull { it.date < dayAgo }?.id ?: 0
    }

    private fun baseUrl(): String? {
        var s = prefs.nsUrl.trim()
        if (s.isEmpty()) return null
        if (!s.startsWith("http")) s = "https://$s"
        if (!s.endsWith("/")) s += "/"
        val uri = runCatching { URI(s) }.getOrNull() ?: return null
        return if (uri.scheme == "https" || uri.host == "localhost" || uri.host == "127.0.0.1") s else null
    }

    private fun open(base: String, path: String): HttpURLConnection {
        val secret = prefs.nsSecret
        var url = base + path
        if (secret.startsWith("token=")) {
            // Access token instead of API secret.
            url += "?token=" + URLEncoder.encode(secret.removePrefix("token="), "UTF-8")
        }
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 20_000
        conn.readTimeout = 20_000
        if (secret.isNotEmpty() && !secret.startsWith("token=")) conn.setRequestProperty("api-secret", LocalApiServer.sha1(secret))
        return conn
    }

    private fun post(base: String, path: String, body: Any) {
        val conn = open(base, path)
        try {
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.outputStream.use { it.write(Json.write(body, sortedKeys = false).toByteArray()) }
            val code = conn.responseCode
            if (code !in 200..299) throw Exception(if (code == 401) "API-Secret falsch (401)" else "HTTP $code")
        } finally {
            conn.disconnect()
        }
    }
}
