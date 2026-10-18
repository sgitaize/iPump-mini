// SPDX-License-Identifier: GPL-3.0-or-later
// Human-readable start page of the local web server (/status.html, or / from a browser).
// Same page as apps/ios/OpenMinipump/API/StatusPage.swift.
package de.sgitaize.openminipump.api

import de.sgitaize.openminipump.Units
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object StatusPage {
    fun html(d: ApiData, version: String, showTransmitter: Boolean, now: Instant = Instant.now()): String {
        val sorted = d.readings.sortedByDescending { it.date }
        val time = DateTimeFormatter.ofPattern("HH:mm").withZone(ZoneId.systemDefault())
        fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
        fun ago(t: Instant): String {
            val m = Duration.between(t, now).toMinutes()
            return if (m < 1) "gerade eben" else "vor $m min"
        }
        fun f(fmt: String, v: Double) = String.format(Locale.GERMANY, fmt, v)

        var hero = "<div class=\"sg muted\">–</div><div class=\"sub\">Noch kein Sensorwert</div>"
        sorted.firstOrNull()?.let { r ->
            val stale = Duration.between(r.date, now).toMinutes() > 15
            var delta = ""
            if (sorted.size > 1 && Duration.between(sorted[1].date, r.date).toMinutes() < 15) {
                val dd = r.mgdl - sorted[1].mgdl
                delta = if (dd > 0) "+$dd" else "$dd"
            }
            val cls = if (r.mgdl < 70) "low" else if (r.mgdl > 180) "high" else "ok"
            hero = "<div class=\"sg ${if (stale) "muted stale" else cls}\">${r.mgdl}<span class=\"arrow\">${Units.arrow(r.trendMgdlPerMin)}</span></div>" +
                "<div class=\"sub\">mg/dL · ${esc(delta)} · ${ago(r.date)} (${time.format(r.date)})</div>"
        }

        val s = d.snapshot
        val tiles = mutableListOf<Triple<String, String, String?>>()
        tiles.add(Triple("Aktives Insulin", s.iob?.let { f("%.2f IE", it.units) } ?: "–", null))
        tiles.add(Triple("Reservoir", s.status?.let { f("%.0f IE", it.reservoirUnits) } ?: "–", null))
        tiles.add(Triple("Modus", s.algorithm?.modeDescription ?: "–", s.status?.let { if (it.isSuspended) "Abgabe angehalten" else "Abgabe läuft" }))
        val basal = s.basal?.let { b ->
            b.tempBasalUnitsPerHour?.let { f("%.3f IE/h (temp.)", it) } ?: if (s.algorithm?.isAutoBasal == true) "Auto" else f("%.3f IE/h", b.unitsPerHour)
        } ?: "–"
        tiles.add(Triple("Basalrate", basal, null))
        tiles.add(Triple("Zeit im Zielbereich", s.timeInRange?.let { "${it.inRangePercent} %" } ?: "–",
            s.timeInRange?.let { "↑ ${it.abovePercent} %  ↓ ${it.belowPercent} %" }))
        tiles.add(Triple("Pumpenbatterie", s.pumpBatteryPercent?.let { "$it %" } ?: "–", null))
        val sensorDetail = s.sensorEnd?.let { end ->
            val m = Duration.between(now, end).toMinutes()
            when {
                m <= 0 -> "abgelaufen"
                m >= 1440 -> "noch ${m / 1440} T ${m % 1440 / 60} h"
                else -> "noch ${m / 60} h ${m % 60} min"
            }
        }
        tiles.add(Triple("Sensor", s.status?.let { if (it.sensorOk) "✓ Sensor ok" else "⚠︎ ${it.sensorMessage}" } ?: "–", sensorDetail))
        if (showTransmitter) tiles.add(Triple("Transmitter", s.transmitterBatteryPercent?.let { "$it %" } ?: "–", null))
        tiles.add(Triple("Handy-Akku", d.uploaderBattery?.let { "$it %" } ?: "–", null))

        val tileHtml = tiles.joinToString("") { t ->
            "<div class=\"tile\"><div class=\"label\">${esc(t.first)}</div><div class=\"value\">${esc(t.second)}</div>" +
                (t.third?.let { "<div class=\"detail\">${esc(it)}</div>" } ?: "") + "</div>"
        }
        val rows = sorted.take(12).joinToString("") { r ->
            "<tr><td>${time.format(r.date)}</td><td class=\"num\">${r.mgdl}</td><td>${Units.arrow(r.trendMgdlPerMin)}</td>" +
                "<td class=\"num\">${r.trendMgdlPerMin?.let { String.format(Locale.GERMANY, "%+.1f", it) } ?: ""}</td></tr>"
        }
        val updated = if (s.hasData) "Pumpenstatus ${ago(s.updatedAt)}" else "Noch kein Pumpenstatus"

        return """
        <!doctype html>
        <html lang="de"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="60">
        <title>openMinipump</title>
        <style>
        :root{--bg:#f6f7f9;--card:#fff;--fg:#111;--muted:#6b7280;--ok:#0a7d32;--high:#b45309;--low:#b91c1c;--line:#e5e7eb}
        @media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#181b21;--fg:#f3f4f6;--muted:#9ca3af;--ok:#34d399;--high:#fbbf24;--low:#f87171;--line:#2a2f37}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.4 system-ui,sans-serif}
        main{max-width:720px;margin:0 auto;padding:16px}
        h1{font-size:18px;margin:4px 0 12px}.card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px;margin-bottom:12px}
        .sg{font-size:72px;font-weight:700;text-align:center;line-height:1}.arrow{font-size:40px;margin-left:8px}
        .sub{text-align:center;color:var(--muted);margin-top:6px}.ok{color:var(--ok)}.high{color:var(--high)}.low{color:var(--low)}
        .muted{color:var(--muted)}.stale{text-decoration:line-through}
        .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
        .tile{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px}
        .label{font-size:12px;color:var(--muted)}.value{font-size:20px;font-weight:600}.detail{font-size:12px;color:var(--muted)}
        table{width:100%;border-collapse:collapse}td{padding:6px 4px;border-bottom:1px solid var(--line)}.num{text-align:right;font-variant-numeric:tabular-nums}
        footer{color:var(--muted);font-size:12px;margin-top:16px}a{color:inherit}
        </style></head><body><main>
        <h1>openMinipump</h1>
        <div class="card">$hero</div>
        <div class="grid">$tileHtml</div>
        <div class="card" style="margin-top:12px"><table>${if (rows.isEmpty()) "<tr><td class=\"muted\">Keine Werte</td></tr>" else rows}</table></div>
        <footer>${esc(updated)} · Seite lädt jede Minute neu · Version ${esc(version)}<br>
        API: <a href="/api/v1/entries.json">entries</a> · <a href="/api/v1/devicestatus.json">devicestatus</a> ·
        <a href="/pebble">pebble</a> · <a href="/api/v1/status.json">status</a><br>
        Nur zur Information, keine Therapieentscheidungen. Maßgeblich ist die Pumpe.</footer>
        </main></body></html>
        """.trimIndent()
    }
}
