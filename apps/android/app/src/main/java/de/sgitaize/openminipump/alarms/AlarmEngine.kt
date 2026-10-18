// SPDX-License-Identifier: GPL-3.0-or-later
// Glucose and pump alarms as notifications, with snooze like common CGM apps (Android port of
// apps/ios/OpenMinipump/Alarms/AlarmEngine.swift). Urgent alarms use a high-importance
// channel; whether they break through Do Not Disturb is up to the user's channel settings.
package de.sgitaize.openminipump.alarms

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import de.sgitaize.minimedkit.GlucoseReading
import de.sgitaize.minimedkit.PumpAlarmCategory
import de.sgitaize.minimedkit.PumpAlarms
import de.sgitaize.minimedkit.PumpStatus
import de.sgitaize.openminipump.EventLog
import de.sgitaize.openminipump.L10n
import de.sgitaize.openminipump.OpenMinipumpApp
import de.sgitaize.openminipump.R
import de.sgitaize.openminipump.ui.MainActivity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONObject
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

enum class GlucoseAlarmKind(val titleRes: Int, val isRate: Boolean = false) {
    URGENT_LOW(R.string.alarm_urgent_low),
    LOW(R.string.alarm_low),
    HIGH(R.string.alarm_high),
    FALLING_FAST(R.string.alarm_falling_fast, true),
    RISING_FAST(R.string.alarm_rising_fast, true),
}

data class AlarmRule(val enabled: Boolean, val threshold: Double, val snoozeMinutes: Int, val repeatMinutes: Int)

data class AlarmConfig(
    val glucose: Map<GlucoseAlarmKind, AlarmRule>,
    val pump: Map<PumpAlarmCategory, Boolean>,
    val noDataEnabled: Boolean,
    val noDataMinutes: Int,
) {
    enum class Preset(val titleRes: Int, val detailRes: Int) {
        STANDARD(R.string.preset_standard, R.string.preset_standard_detail),
        URGENT_ONLY(R.string.preset_urgent, R.string.preset_urgent_detail),
        ALL(R.string.preset_all, R.string.preset_all_detail),
    }

    fun toJson(): String = JSONObject().apply {
        put("glucose", JSONObject().apply {
            for ((k, r) in glucose) put(k.name, JSONObject().put("enabled", r.enabled).put("threshold", r.threshold)
                .put("snooze", r.snoozeMinutes).put("repeat", r.repeatMinutes))
        })
        put("pump", JSONObject().apply { for ((k, v) in pump) put(k.name, v) })
        put("noDataEnabled", noDataEnabled)
        put("noDataMinutes", noDataMinutes)
    }.toString()

    companion object {
        fun preset(p: Preset): AlarmConfig {
            val glucose = mutableMapOf(
                GlucoseAlarmKind.URGENT_LOW to AlarmRule(true, 55.0, 15, 5),
                GlucoseAlarmKind.LOW to AlarmRule(true, 70.0, 30, 15),
                GlucoseAlarmKind.HIGH to AlarmRule(true, 250.0, 60, 60),
                GlucoseAlarmKind.FALLING_FAST to AlarmRule(false, 2.0, 30, 30),
                GlucoseAlarmKind.RISING_FAST to AlarmRule(false, 2.0, 30, 30),
            )
            val pump = PumpAlarmCategory.entries.associateWith { false }.toMutableMap()
            when (p) {
                Preset.STANDARD -> listOf(
                    PumpAlarmCategory.DELIVERY, PumpAlarmCategory.SUPPLIES, PumpAlarmCategory.SENSOR,
                    PumpAlarmCategory.CALIBRATION, PumpAlarmCategory.SMART_GUARD,
                ).forEach { pump[it] = true }
                Preset.URGENT_ONLY -> {
                    glucose[GlucoseAlarmKind.LOW] = glucose.getValue(GlucoseAlarmKind.LOW).copy(enabled = false)
                    glucose[GlucoseAlarmKind.HIGH] = glucose.getValue(GlucoseAlarmKind.HIGH).copy(enabled = false)
                    pump[PumpAlarmCategory.DELIVERY] = true
                }
                Preset.ALL -> {
                    for (k in GlucoseAlarmKind.entries) glucose[k] = glucose.getValue(k).copy(enabled = true)
                    for (c in PumpAlarmCategory.entries) pump[c] = true
                }
            }
            return AlarmConfig(glucose, pump, true, 20)
        }

        fun fromJson(text: String): AlarmConfig? = try {
            val o = JSONObject(text)
            val base = preset(Preset.STANDARD)
            val g = o.getJSONObject("glucose")
            val glucose = GlucoseAlarmKind.entries.associateWith { k ->
                g.optJSONObject(k.name)?.let {
                    AlarmRule(it.getBoolean("enabled"), it.getDouble("threshold"), it.getInt("snooze"), it.getInt("repeat"))
                } ?: base.glucose.getValue(k)
            }
            val p = o.getJSONObject("pump")
            val pump = PumpAlarmCategory.entries.associateWith { p.optBoolean(it.name, base.pump.getValue(it)) }
            AlarmConfig(glucose, pump, o.optBoolean("noDataEnabled", true), o.optInt("noDataMinutes", 20))
        } catch (_: Exception) {
            null
        }
    }
}

class AlarmEngine(private val context: Context, private val log: EventLog) {
    private val sp = context.getSharedPreferences("alarms", Context.MODE_PRIVATE)

    private val _config = MutableStateFlow(AlarmConfig.fromJson(sp.getString("alarmConfig", "") ?: "") ?: AlarmConfig.preset(AlarmConfig.Preset.STANDARD))
    val config: StateFlow<AlarmConfig> = _config

    /** Global mute for all alarms except "urgent low" (epoch millis, 0 = off). */
    private val _mutedUntil = MutableStateFlow(sp.getLong("mutedUntil", 0))
    val mutedUntil: StateFlow<Long> = _mutedUntil

    /** Disabled in demo mode: no alarms for simulated values. */
    var enabled = true

    init {
        createChannels()
    }

    fun setConfig(c: AlarmConfig) {
        _config.value = c
        sp.edit().putString("alarmConfig", c.toJson()).apply()
    }

    fun applyPreset(p: AlarmConfig.Preset) = setConfig(AlarmConfig.preset(p))

    val notificationsAllowed: Boolean get() = NotificationManagerCompat.from(context).areNotificationsEnabled()

    // MARK: Glucose

    fun evaluate(reading: GlucoseReading, now: Instant = Instant.now()) {
        if (!enabled) return
        if (Duration.between(reading.date, now).toMinutes() >= 10) return
        val c = _config.value
        val g = reading.mgdl.toDouble()
        val urgent = c.glucose[GlucoseAlarmKind.URGENT_LOW]
        val rate = reading.trendMgdlPerMin ?: 0.0
        val active = mapOf(
            GlucoseAlarmKind.URGENT_LOW to (g <= (urgent?.threshold ?: 55.0)),
            GlucoseAlarmKind.LOW to (g <= (c.glucose[GlucoseAlarmKind.LOW]?.threshold ?: 70.0) &&
                g > (if (urgent?.enabled == true) urgent.threshold else 0.0)),
            GlucoseAlarmKind.HIGH to (g >= (c.glucose[GlucoseAlarmKind.HIGH]?.threshold ?: 250.0)),
            GlucoseAlarmKind.FALLING_FAST to (rate <= -(c.glucose[GlucoseAlarmKind.FALLING_FAST]?.threshold ?: 2.0)),
            GlucoseAlarmKind.RISING_FAST to (rate >= (c.glucose[GlucoseAlarmKind.RISING_FAST]?.threshold ?: 2.0)),
        )
        for (kind in GlucoseAlarmKind.entries) {
            val rule = c.glucose[kind]
            if (rule == null || !rule.enabled || active[kind] != true) {
                clear(kind.name)
                continue
            }
            val body = if (kind.isRate) {
                context.getString(R.string.alarm_body_rate, reading.mgdl, String.format(Locale.getDefault(), "%+.1f", rate))
            } else {
                context.getString(R.string.alarm_body_value, reading.mgdl, String.format(Locale.getDefault(), "%.1f", g / 18.0182))
            }
            fire(kind.name, context.getString(kind.titleRes), body, urgent = kind == GlucoseAlarmKind.URGENT_LOW || kind == GlucoseAlarmKind.LOW,
                ignoresMute = kind == GlucoseAlarmKind.URGENT_LOW, repeatMinutes = rule.repeatMinutes, now = now)
        }
    }

    // MARK: Pump

    fun pumpAlarm(id: Int, type: Int, status: Int, date: Instant, now: Instant = Instant.now()) {
        log.add("Alarm-Eintrag der Pumpe: id $id, Typ 0x%04X, Status 0x%02X, %s".format(type, status, time(date)))
        val seen = sp.getString("seenPump", "")!!.split(",").filter { it.isNotEmpty() }
        if (status != 0x33 || Duration.between(date, now).toMinutes() >= 30 || id.toString() in seen) return
        sp.edit().putString("seenPump", (seen + id.toString()).takeLast(200).joinToString(",")).apply()
        val info = PumpAlarms.info(type)
        log.add("Pumpenmeldung: ${info.title} (${info.category})")
        if (!enabled || _config.value.pump[info.category] != true) return
        fire("pump.$id", context.getString(R.string.alarm_pump_title, L10n.tr(info.title)),
            context.getString(R.string.alarm_pump_body, time(date)), urgent = info.urgent, ignoresMute = info.urgent, repeatMinutes = 0, now = now)
    }

    // MARK: Sensor

    /**
     * Sensor state from the pump status (read every update). One notification whenever it
     * changes into a problem state; cleared when ok. Uses the pump alert category "Sensor".
     */
    fun sensorStatus(status: PumpStatus, now: Instant = Instant.now()) {
        if (!enabled) return
        val state = status.sensorMessageState or (if (status.sensorSignalLost) 0x100 else 0) or (if (status.sensorOn) 0 else 0x200)
        if (sp.getInt("sensorState", -1) == state) return
        sp.edit().putInt("sensorState", state).apply()
        val text = sensorText(status)
        log.add("Sensorstatus: $text")
        clear("sensor")
        if (status.sensorOk || _config.value.pump[PumpAlarmCategory.SENSOR] != true) return
        val updating = status.sensorMessageState == 0x02
        fire("sensor", context.getString(R.string.sensor_title, L10n.tr(text)),
            context.getString(if (updating) R.string.sensor_updating_body else R.string.sensor_problem_body),
            urgent = false, ignoresMute = false, repeatMinutes = 0, now = now)
    }

    // MARK: Snooze / mute

    fun snooze(key: String, minutes: Int) {
        sp.edit().putLong("snooze.$key", System.currentTimeMillis() + minutes * 60_000L).apply()
        log.add("Alarm $key für $minutes min stummgeschaltet")
        NotificationManagerCompat.from(context).cancel(key.hashCode())
    }

    fun muteAll(minutes: Int?) {
        val until = minutes?.let { System.currentTimeMillis() + it * 60_000L } ?: 0
        _mutedUntil.value = until
        sp.edit().putLong("mutedUntil", until).apply()
    }

    fun sendTest() = post("test", context.getString(R.string.alarm_test_title), context.getString(R.string.alarm_test_body), urgent = true)

    // MARK: Internals

    private fun fire(key: String, title: String, body: String, urgent: Boolean, ignoresMute: Boolean, repeatMinutes: Int, now: Instant) {
        val nowMs = now.toEpochMilli()
        if (sp.getLong("snooze.$key", 0) > nowMs) return
        if (!ignoresMute && _mutedUntil.value > nowMs) return
        val last = sp.getLong("fired.$key", 0)
        if (last > 0) {
            if (repeatMinutes == 0) return
            if (nowMs - last < repeatMinutes * 60_000L - 30_000) return
        }
        sp.edit().putLong("fired.$key", nowMs).apply()
        post(key, title, body, urgent)
        log.warn("Alarm: $title – $body")
    }

    private fun clear(key: String) {
        if (!sp.contains("fired.$key")) return
        sp.edit().remove("fired.$key").apply()
        NotificationManagerCompat.from(context).cancel(key.hashCode())
    }

    private fun post(key: String, title: String, body: String, urgent: Boolean) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val b = NotificationCompat.Builder(context, if (urgent) CHANNEL_URGENT else CHANNEL_ALARMS)
            .setSmallIcon(R.drawable.ic_stat_drop)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(if (urgent) NotificationCompat.PRIORITY_MAX else NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
        for ((minutes, label) in listOf(15 to R.string.snooze_15, 30 to R.string.snooze_30, 60 to R.string.snooze_60)) {
            val intent = Intent(context, AlarmActionReceiver::class.java).putExtra("key", key).putExtra("minutes", minutes)
            val pi = PendingIntent.getBroadcast(context, (key + minutes).hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            b.addAction(0, context.getString(label), pi)
        }
        NotificationManagerCompat.from(context).notify(key.hashCode(), b.build())
    }

    private fun createChannels() {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL_URGENT, context.getString(R.string.channel_urgent), NotificationManager.IMPORTANCE_HIGH).apply {
            enableVibration(true)
            setBypassDnd(true)
        })
        nm.createNotificationChannel(NotificationChannel(CHANNEL_ALARMS, context.getString(R.string.channel_alarms), NotificationManager.IMPORTANCE_HIGH))
        nm.createNotificationChannel(NotificationChannel(CHANNEL_REMINDERS, context.getString(R.string.channel_reminders), NotificationManager.IMPORTANCE_DEFAULT))
    }

    /** Info notifications without snooze (no data, Pebble, app reminders). */
    fun remind(id: String, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val n = NotificationCompat.Builder(context, CHANNEL_REMINDERS)
            .setSmallIcon(R.drawable.ic_stat_drop)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openApp(context))
            .build()
        NotificationManagerCompat.from(context).notify(id.hashCode(), n)
    }

    fun cancel(id: String) = NotificationManagerCompat.from(context).cancel(id.hashCode())

    companion object {
        const val CHANNEL_URGENT = "alarms_urgent"
        const val CHANNEL_ALARMS = "alarms"
        const val CHANNEL_REMINDERS = "reminders"

        /** German source text of the sensor state (localised with L10n.tr). */
        fun sensorText(status: PumpStatus): String = when {
            !status.sensorOn -> "Kein Sensor aktiv"
            status.sensorSignalLost -> "Sensorsignal verloren"
            else -> status.sensorMessage
        }

        fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )

        private fun time(date: Instant): String =
            DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(ZoneId.systemDefault()).format(date)
    }
}

/** Snooze actions of an alarm notification. */
class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val key = intent.getStringExtra("key") ?: return
        val minutes = intent.getIntExtra("minutes", 30)
        OpenMinipumpApp.model(context).alarms.snooze(key, minutes)
    }
}
