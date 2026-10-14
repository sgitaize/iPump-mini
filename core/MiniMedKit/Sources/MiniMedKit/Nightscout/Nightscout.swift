// SPDX-License-Identifier: GPL-3.0-or-later
// Mapping of pump data to the Nightscout API v1 JSON shapes (entries, devicestatus,
// status, pebble). Field names follow cgm-remote-monitor.
import Foundation

public struct GlucoseReading: Codable, Equatable, Sendable {
    public let date: Date
    public let mgdl: Int
    public let trendMgdlPerMin: Double?
    /// Sensor session time offset; identifies the record together with the session start.
    public let sessionOffsetMinutes: UInt16?

    public init(date: Date, mgdl: Int, trendMgdlPerMin: Double?, sessionOffsetMinutes: UInt16?) {
        self.date = date
        self.mgdl = mgdl
        self.trendMgdlPerMin = trendMgdlPerMin
        self.sessionOffsetMinutes = sessionOffsetMinutes
    }
}

public struct PumpSnapshot: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var status: PumpStatus?
    public var iob: InsulinOnBoard?
    public var timeInRange: TimeInRange?
    public var algorithm: TherapyAlgorithmStates?
    public var basal: ActiveBasalRate?
    public var pumpBatteryPercent: Int?
    public var transmitterBatteryPercent: Int?
    public var sensorStart: Date?
    public var sensorEnd: Date?
    public var sensorExpiresInMinutes: Int?

    public init(updatedAt: Date = .distantPast) { self.updatedAt = updatedAt }
}

public enum Nightscout {
    public static let device = "openMinipump"

    /// Medtronic shows one arrow from 1 mg/dL/min, two from 2, three from 3.
    /// Nightscout/Dexcom directions have no "three arrows" step that every client
    /// understands, so three arrows map to Double* as well.
    public static func direction(forRate rate: Double?) -> (name: String, trend: Int) {
        guard let rate else { return ("NONE", 0) }
        switch rate {
        case 2...: return ("DoubleUp", 1)
        case 1..<2: return ("SingleUp", 2)
        case -1 ..< 1: return ("Flat", 4)
        case -2 ..< -1: return ("SingleDown", 6)
        default: return ("DoubleDown", 7)
        }
    }

    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // ISO8601DateFormatter is thread-safe for formatting (Foundation docs).
    public static func isoString(_ date: Date) -> String { iso.string(from: date) }
    public static func millis(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    /// - Parameter includeId: local API only. For uploads Nightscout assigns its own id.
    public static func entry(_ r: GlucoseReading, includeId: Bool = true) -> [String: Any] {
        let dir = direction(forRate: r.trendMgdlPerMin)
        let ms = millis(r.date)
        var e: [String: Any] = [
            "type": "sgv",
            "sgv": r.mgdl,
            "direction": dir.name,
            "trend": dir.trend,
            "date": ms,
            "dateString": isoString(r.date),
            "sysTime": isoString(r.date),
            "device": device,
            "utcOffset": TimeZone.current.secondsFromGMT(for: r.date) / 60,
        ]
        if includeId { e["_id"] = "omp-\(ms)" }
        if let rate = r.trendMgdlPerMin { e["trendRate"] = rate }
        return e
    }

    public static func deviceStatus(_ s: PumpSnapshot, uploaderBattery: Int?) -> [String: Any] {
        var pump: [String: Any] = ["clock": isoString(s.updatedAt)]
        if let status = s.status {
            pump["reservoir"] = status.reservoirUnits
            pump["status"] = [
                "status": status.isSuspended ? "suspended" : "normal",
                "suspended": status.isSuspended,
                "timestamp": isoString(s.updatedAt),
            ] as [String: Any]
        }
        if let iob = s.iob {
            pump["iob"] = ["iob": iob.units, "bolusiob": iob.units, "timestamp": isoString(s.updatedAt)] as [String: Any]
        }
        if let b = s.pumpBatteryPercent { pump["battery"] = ["percent": b] }
        var extended: [String: Any] = [:]
        if let a = s.algorithm { extended["mode"] = a.modeDescription }
        if let basal = s.basal { extended["basalRate"] = basal.tempBasalUnitsPerHour ?? basal.unitsPerHour }
        if let tir = s.timeInRange { extended["timeInRange"] = Int(tir.inRangePercent) }
        if let t = s.transmitterBatteryPercent { extended["transmitterBattery"] = t }
        if let end = s.sensorEnd {
            extended["sensorEnd"] = isoString(end)
            extended["sensorExpiresInMinutes"] = Int(end.timeIntervalSinceNow / 60)
        }
        if !extended.isEmpty { pump["extended"] = extended }

        var ds: [String: Any] = [
            "device": device,
            "created_at": isoString(s.updatedAt),
            "pump": pump,
        ]
        if let u = uploaderBattery { ds["uploaderBattery"] = u; ds["uploader"] = ["battery": u] }
        return ds
    }

    /// Classic Nightscout `/pebble` endpoint (cgm-remote-monitor lib/server/pebble.js):
    /// `?count=N` (default 1) and `?units=mmol`. Values are strings, the first entry carries
    /// `bgdelta`, `battery` and `iob`.
    public static func pebble(readings: [GlucoseReading], snapshot: PumpSnapshot?, uploaderBattery: Int?,
                              count: Int = 1, mmol: Bool = false, now: Date = Date()) -> [String: Any] {
        let sorted = readings.sorted { $0.date > $1.date }
        func fmt(_ mgdl: Int) -> String {
            mmol ? String(format: "%.1f", Double(mgdl) / 18.0) : String(mgdl)
        }
        var bgs: [[String: Any]] = []
        for (i, r) in sorted.prefix(max(1, min(count, 100))).enumerated() {
            let dir = direction(forRate: r.trendMgdlPerMin)
            var bg: [String: Any] = [
                "sgv": fmt(r.mgdl),
                "trend": dir.trend,
                "direction": dir.name,
                "datetime": millis(r.date),
            ]
            if i == 0 {
                // Delta only between consecutive 5-minute values (gap < 15 min), like Nightscout.
                if sorted.count > 1, r.date.timeIntervalSince(sorted[1].date) < 15 * 60 {
                    let d = r.mgdl - sorted[1].mgdl
                    bg["bgdelta"] = mmol ? (Double(d) / 18.0 * 10).rounded() / 10 : Double(d)
                } else {
                    bg["bgdelta"] = 0
                }
                if let u = uploaderBattery { bg["battery"] = String(u) }
                if let iob = snapshot?.iob { bg["iob"] = String(format: "%.2f", iob.units) }
            }
            bgs.append(bg)
        }
        return ["status": [["now": millis(now)]], "bgs": bgs, "cals": [] as [Any]]
    }

    public static func status(version: String, now: Date = Date()) -> [String: Any] {
        [
            "status": "ok",
            "name": device,
            "version": version,
            "serverTime": isoString(now),
            "serverTimeEpoch": millis(now),
            "apiEnabled": true,
            "careportalEnabled": false,
            "settings": ["units": "mg/dl", "customTitle": device] as [String: Any],
        ]
    }
}
