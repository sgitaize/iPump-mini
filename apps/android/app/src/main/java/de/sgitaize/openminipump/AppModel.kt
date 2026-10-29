// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import de.sgitaize.openminipump.alarms.AlarmEngine
import de.sgitaize.openminipump.api.ApiData
import de.sgitaize.openminipump.api.LocalApiServer
import de.sgitaize.openminipump.api.StatusPage
import de.sgitaize.openminipump.ble.PumpLink
import de.sgitaize.openminipump.nightscout.NightscoutUploader
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Duration
import java.time.Instant

/** Terms of use. Raising `VERSION` asks every user to accept again. */
object Terms {
    const val VERSION = 1
}

/**
 * Composition root: creates the data store, the pump link, the local API server and the
 * Nightscout uploader and wires them together (like AppModel in the iOS app). Every new sensor
 * value fans out to: Nightscout upload, alarm evaluation, Pebble monitor and the status
 * notification of the foreground service.
 */
class AppModel(private val app: Application) {
    val prefs = Prefs(app)
    val log = EventLog(app)
    val config = AppConfig.load(app, prefs)
    val store = DataStore(app)
    val alarms = AlarmEngine(app, log)
    val uploader = NightscoutUploader(prefs, store, log)
    val version: String = app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: "0"

    /** Read once at launch; switching it takes effect on the next start (except [enterDemo]). */
    val demo: Boolean = prefs.demoMode

    private val main = Handler(Looper.getMainLooper())
    private var lastPumpData: Instant? = null

    private val _apiState = MutableStateFlow("stopped")
    val apiState: StateFlow<String> = _apiState

    val link = PumpLink(app, config, prefs, store, log, alarms,
        onData = { lastPumpData = Instant.now(); noDataNotified = false; alarms.cancel(NO_DATA_ID) },
        onHistory = { oldest -> uploader.historyAdded(oldest) })

    val api = LocalApiServer(
        version = version,
        data = { ApiData(store.readings.value, store.snapshot.value, store.treatments.value, store.uploaderBattery()) },
        onState = { _apiState.value = it },
        onLog = { text -> main.post { log.add(text) } },
        onPebbleRequest = { main.post { pebbleRequested() } },
        statusHtml = { StatusPage.html(it, version, prefs.hasTransmitter) },
    )

    init {
        store.onNewReading = {
            uploader.newReading()
            store.latest?.let(alarms::evaluate)
            checkPebble()
            GlucoseWidget.update(app)
        }
        link.migrateHistoryIfNeeded()
        if (demo) {
            alarms.enabled = false
            uploader.disabled = true
            store.loadDemoData()
        }
        restartApi()
    }

    val termsAccepted: Boolean get() = prefs.termsAcceptedVersion >= Terms.VERSION

    fun acceptTerms() {
        prefs.termsAcceptedVersion = Terms.VERSION
        prefs.termsAcceptedAt = System.currentTimeMillis()
    }

    /** Starts Bluetooth once the permissions are granted (called by the service). */
    fun startBluetooth() {
        link.start(bluetooth = !demo)
    }

    /** Starts demo mode right away when no pump is paired; otherwise on the next start. */
    fun enterDemo() {
        prefs.demoMode = true
        if (link.isPaired.value) return
        link.stopForDemo()
        alarms.enabled = false
        uploader.disabled = true
        store.loadDemoData()
    }

    fun restartApi() {
        api.start(allowLan = prefs.apiAllowLan && prefs.apiSecret.isNotEmpty(), secret = prefs.apiSecret)
    }

    // MARK: Watchdog ("no data") and Pebble monitor

    private var noDataNotified = false

    /** Checked every minute: pump data missing for the configured time → one reminder per outage. */
    private val watchdog = object : Runnable {
        override fun run() {
            main.postDelayed(this, 60_000)
            checkPebble()
            val cfg = alarms.config.value
            if (demo || !cfg.noDataEnabled || noDataNotified || !link.isPaired.value) return
            val last = lastPumpData ?: store.lastDataAt.value ?: return
            if (Duration.between(last, Instant.now()).toMinutes() < cfg.noDataMinutes) return
            noDataNotified = true
            alarms.remind(NO_DATA_ID, app.getString(R.string.nodata_title, cfg.noDataMinutes), app.getString(R.string.nodata_body))
        }
    }

    init {
        main.postDelayed(watchdog, 60_000)
    }

    private fun pebbleRequested() {
        prefs.sp.edit().putLong("pebbleLastRequest", System.currentTimeMillis()).apply()
        if (prefs.sp.getBoolean("pebbleNotified", false)) {
            prefs.sp.edit().putBoolean("pebbleNotified", false).apply()
            alarms.cancel(PEBBLE_ID)
        }
    }

    val pebbleLastRequest: Long get() = prefs.sp.getLong("pebbleLastRequest", 0)

    fun setPebbleMonitor(on: Boolean) {
        prefs.pebbleMonitor = on
        // The time limit counts from switching on if no request came yet.
        prefs.sp.edit().putLong("pebbleMonitorSince", System.currentTimeMillis()).putBoolean("pebbleNotified", false).apply()
    }

    private fun checkPebble() {
        if (!prefs.pebbleMonitor || prefs.sp.getBoolean("pebbleNotified", false)) return
        val since = prefs.sp.getLong("pebbleMonitorSince", System.currentTimeMillis())
        val reference = maxOf(pebbleLastRequest, since)
        val silentMinutes = (System.currentTimeMillis() - reference) / 60_000
        if (silentMinutes < prefs.pebbleMinutes) return
        prefs.sp.edit().putBoolean("pebbleNotified", true).apply()
        alarms.remind(PEBBLE_ID, app.getString(R.string.pebble_title), app.getString(R.string.pebble_body, silentMinutes.toInt()))
    }

    companion object {
        private const val NO_DATA_ID = "openminipump.stale"
        private const val PEBBLE_ID = "pebble.stale"

        /** Runtime permissions the app needs for Bluetooth and notifications. */
        fun requiredPermissions(): Array<String> = buildList {
            if (Build.VERSION.SDK_INT >= 31) {
                add(Manifest.permission.BLUETOOTH_CONNECT)
                add(Manifest.permission.BLUETOOTH_ADVERTISE)
            }
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()

        /** Bluetooth permissions granted (notifications are optional). */
        fun hasBluetoothPermissions(context: Context): Boolean = Build.VERSION.SDK_INT < 31 || listOf(
            Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE,
        ).all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
    }
}
