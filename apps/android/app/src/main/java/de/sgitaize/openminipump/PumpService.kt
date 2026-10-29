// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import de.sgitaize.openminipump.alarms.AlarmEngine
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant

/**
 * Foreground service: keeps the app process (GATT server, SAKE session, local API) alive while
 * the app is in the background, so the pump can reach it at any time. Its ongoing notification
 * shows the latest value, like a Live Activity on iOS.
 */
class PumpService : LifecycleService() {
    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.channel_status), NotificationManager.IMPORTANCE_LOW).apply {
            setShowBadge(false)
        })
        val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        try {
            ServiceCompat.startForeground(this, ID, build(getString(R.string.app_name), getString(R.string.service_starting)), type)
        } catch (e: Exception) {
            // Missing Bluetooth permission or background start not allowed: try again from the app.
            OpenMinipumpApp.model(this).log.warn("Dienst konnte nicht starten: ${e.message}")
            stopSelf()
            return
        }
        val model = OpenMinipumpApp.model(this)
        model.startBluetooth()
        lifecycleScope.launch {
            combine(model.store.readings, model.store.snapshot, model.link.phase) { _, _, _ -> }.collect { update(model) }
        }
        lifecycleScope.launch {
            while (true) {
                delay(60_000)
                update(model)
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        return START_STICKY
    }

    private fun update(model: AppModel) {
        val r = model.store.latest
        val mmol = model.prefs.unitMmol
        val title: String
        val text: String
        if (r != null && Duration.between(r.date, Instant.now()).toMinutes() < 60) {
            val age = Duration.between(r.date, Instant.now()).toMinutes()
            title = "${Units.format(r.mgdl, mmol)} ${Units.arrow(r.trendMgdlPerMin)}  ${Units.label(mmol)}"
            val iob = model.store.snapshot.value.iob?.let { " · IOB " + Units.insulin(it.units, 2) } ?: ""
            text = (if (age < 1) getString(R.string.just_now) else getString(R.string.minutes_ago, age.toInt())) + iob
        } else {
            title = getString(R.string.app_name)
            text = getString(model.link.phase.value.labelRes)
        }
        getSystemService(NotificationManager::class.java).notify(ID, build(title, text))
        GlucoseWidget.update(this)
    }

    private fun build(title: String, text: String) = NotificationCompat.Builder(this, CHANNEL)
        .setSmallIcon(R.drawable.ic_stat_drop)
        .setContentTitle(title)
        .setContentText(text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setShowWhen(false)
        .setCategory(NotificationCompat.CATEGORY_STATUS)
        .setContentIntent(AlarmEngine.openApp(this))
        .build()

    companion object {
        private const val CHANNEL = "status"
        private const val ID = 1

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, PumpService::class.java))
        }
    }
}
