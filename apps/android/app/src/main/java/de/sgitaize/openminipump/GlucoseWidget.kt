// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.graphics.Paint
import android.widget.RemoteViews
import de.sgitaize.openminipump.alarms.AlarmEngine
import java.time.Duration
import java.time.Instant

/**
 * Home screen widget: latest value, trend arrow and age, like the small iOS widget.
 * Updated by [PumpService] (every minute and on new data) and when a new value arrives.
 */
class GlucoseWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        manager.updateAppWidget(ids, views(context))
    }

    companion object {
        /** Values older than this are shown greyed out and struck through. */
        private const val STALE_MINUTES = 15L

        fun update(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, GlucoseWidget::class.java))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context))
        }

        internal fun views(context: Context): RemoteViews {
            val model = OpenMinipumpApp.model(context)
            val v = RemoteViews(context.packageName, R.layout.widget_glucose)
            v.setOnClickPendingIntent(R.id.widget_root, AlarmEngine.openApp(context))
            val r = model.store.latest
            val age = r?.let { Duration.between(it.date, Instant.now()).toMinutes() }
            if (r == null || age == null || age >= 60) {
                v.setTextViewText(R.id.widget_value, "–")
                v.setTextViewText(R.id.widget_arrow, "")
                v.setTextViewText(R.id.widget_detail, context.getString(R.string.no_data))
                v.setInt(R.id.widget_value, "setPaintFlags", Paint.ANTI_ALIAS_FLAG)
                v.setTextColor(R.id.widget_value, context.getColor(R.color.widget_text))
                return v
            }
            val mmol = model.prefs.unitMmol
            val stale = age >= STALE_MINUTES
            val color = when {
                stale -> context.getColor(R.color.widget_secondary)
                r.mgdl < model.prefs.low -> 0xFFD32F2F.toInt()
                r.mgdl > model.prefs.high -> 0xFFE08A00.toInt()
                else -> context.getColor(R.color.widget_text)
            }
            v.setTextViewText(R.id.widget_value, Units.format(r.mgdl, mmol))
            v.setTextColor(R.id.widget_value, color)
            v.setInt(R.id.widget_value, "setPaintFlags",
                Paint.ANTI_ALIAS_FLAG or (if (stale) Paint.STRIKE_THRU_TEXT_FLAG else 0))
            v.setTextViewText(R.id.widget_arrow, if (stale) "" else Units.arrow(r.trendMgdlPerMin))
            v.setTextColor(R.id.widget_arrow, color)
            val ageText = if (age < 1) context.getString(R.string.just_now) else context.getString(R.string.minutes_ago, age.toInt())
            v.setTextViewText(R.id.widget_detail, "${Units.label(mmol)} · $ageText")
            return v
        }
    }
}
