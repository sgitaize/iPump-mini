// SPDX-License-Identifier: GPL-3.0-or-later
// Human-readable start page of the local web server (/status.html, or / from a browser).
import Foundation
import MiniMedKit

enum StatusPage {
    static func html(readings: [GlucoseReading], snapshot: PumpSnapshot, uploaderBattery: Int?, version: String,
                     now: Date = Date()) -> String {
        let sorted = readings.sorted { $0.date > $1.date }
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        func arrows(_ rate: Double?) -> String {
            guard let rate else { return "" }
            let n = min(3, Int(abs(rate)))
            return n == 0 ? "→" : String(repeating: rate > 0 ? "↑" : "↓", count: n)
        }
        func ago(_ d: Date) -> String {
            let m = Int(now.timeIntervalSince(d) / 60)
            return m < 1 ? "gerade eben" : "vor \(m) min"
        }

        var hero = "<div class=\"sg muted\">–</div><div class=\"sub\">Noch kein Sensorwert</div>"
        if let r = sorted.first {
            let stale = now.timeIntervalSince(r.date) > 15 * 60
            var delta = ""
            if sorted.count > 1, r.date.timeIntervalSince(sorted[1].date) < 15 * 60 {
                let d = r.mgdl - sorted[1].mgdl
                delta = d > 0 ? "+\(d)" : "\(d)"
            }
            let cls = r.mgdl < 70 ? "low" : r.mgdl > 180 ? "high" : "ok"
            hero = """
            <div class="sg \(stale ? "muted stale" : cls)">\(r.mgdl)<span class="arrow">\(arrows(r.trendMgdlPerMin))</span></div>
            <div class="sub">mg/dL · \(esc(delta)) · \(ago(r.date)) (\(time.string(from: r.date)))</div>
            """
        }

        var tiles: [(String, String, String?)] = []
        let s = snapshot
        tiles.append(("Aktives Insulin", s.iob.map { String(format: "%.2f IE", $0.units) } ?? "–", nil))
        tiles.append(("Reservoir", s.status.map { String(format: "%.0f IE", $0.reservoirUnits) } ?? "–", nil))
        tiles.append(("Modus", s.algorithm?.modeDescription ?? "–", s.status.map { $0.isSuspended ? "Abgabe angehalten" : "Abgabe läuft" }))
        let basal: String = {
            guard let b = s.basal else { return "–" }
            if let t = b.tempBasalUnitsPerHour { return String(format: "%.3f IE/h (temp.)", t) }
            if s.algorithm?.shieldState == .autoBasal { return "Auto" }
            return String(format: "%.3f IE/h", b.unitsPerHour)
        }()
        tiles.append(("Basalrate", basal, nil))
        tiles.append(("Zeit im Zielbereich", s.timeInRange.map { "\($0.inRangePercent) %" } ?? "–",
                      s.timeInRange.map { "↑ \($0.abovePercent) %  ↓ \($0.belowPercent) %" }))
        tiles.append(("Pumpenbatterie", s.pumpBatteryPercent.map { "\($0) %" } ?? "–", nil))
        let sensorDetail: String? = s.sensorEnd.map { end in
            let m = Int(end.timeIntervalSince(now) / 60)
            if m <= 0 { return "abgelaufen" }
            return m >= 1440 ? "noch \(m / 1440) T \(m % 1440 / 60) h" : "noch \(m / 60) h \(m % 60) min"
        }
        tiles.append(("Sensor", s.status.map { $0.sensorOK ? "✓ Sensor ok" : "⚠︎ \($0.sensorMessage)" } ?? "–", sensorDetail))
        if UserDefaults.standard.string(forKey: "sensorType") != "simplera" {
            tiles.append(("Transmitter", s.transmitterBatteryPercent.map { "\($0) %" } ?? "–", nil))
        }
        tiles.append(("iPhone-Akku", uploaderBattery.map { "\($0) %" } ?? "–", nil))

        let tileHTML = tiles.map { t in
            "<div class=\"tile\"><div class=\"label\">\(esc(t.0))</div><div class=\"value\">\(esc(t.1))</div>"
                + (t.2.map { "<div class=\"detail\">\(esc($0))</div>" } ?? "") + "</div>"
        }.joined()

        let rows = sorted.prefix(12).map { r in
            "<tr><td>\(time.string(from: r.date))</td><td class=\"num\">\(r.mgdl)</td><td>\(arrows(r.trendMgdlPerMin))</td>"
                + "<td class=\"num\">\(r.trendMgdlPerMin.map { String(format: "%+.1f", $0) } ?? "")</td></tr>"
        }.joined()

        let updated = s.updatedAt > .distantPast ? "Pumpenstatus \(ago(s.updatedAt))" : "Noch kein Pumpenstatus"

        return """
        <!doctype html>
        <html lang="de"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="refresh" content="60">
        <title>openMinipump</title>
        <style>
        :root{--bg:#f6f7f9;--card:#fff;--fg:#111;--muted:#6b7280;--ok:#0a7d32;--high:#b45309;--low:#b91c1c;--line:#e5e7eb}
        @media (prefers-color-scheme:dark){:root{--bg:#0f1115;--card:#181b21;--fg:#f3f4f6;--muted:#9ca3af;--ok:#34d399;--high:#fbbf24;--low:#f87171;--line:#2a2f37}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.4 -apple-system,system-ui,sans-serif}
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
        <div class="card">\(hero)</div>
        <div class="grid">\(tileHTML)</div>
        <div class="card" style="margin-top:12px"><table>\(rows.isEmpty ? "<tr><td class=\"muted\">Keine Werte</td></tr>" : rows)</table></div>
        <footer>\(esc(updated)) · Seite lädt jede Minute neu · Version \(esc(version))<br>
        API: <a href="/api/v1/entries.json">entries</a> · <a href="/api/v1/devicestatus.json">devicestatus</a> ·
        <a href="/pebble">pebble</a> · <a href="/api/v1/status.json">status</a><br>
        Nur zur Information, keine Therapieentscheidungen. Maßgeblich ist die Pumpe.</footer>
        </main></body></html>
        """
    }
}
