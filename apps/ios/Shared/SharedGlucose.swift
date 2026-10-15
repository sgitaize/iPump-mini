// SPDX-License-Identifier: GPL-3.0-or-later
// Data shared between the app and its widgets / Live Activity (App Group container).
import ActivityKit
import Foundation

struct WidgetSnapshot: Codable, Equatable {
    struct Point: Codable, Equatable {
        let date: Date
        let mgdl: Int
    }

    var points: [Point]           // last 6 h, oldest first
    var trendRate: Double?
    var iob: Double?
    var updatedAt: Date
    // Pump status for the larger widgets (optional: older files lack them).
    var reservoir: Double?
    var pumpBattery: Int?
    /// "smartguard", "safe" or "manual".
    var mode: String?
    var sensorEnd: Date?

    var latest: Point? { points.last }

    /// Change to the previous value if it is at most 15 min older.
    var delta: Int? {
        guard points.count >= 2 else { return nil }
        let a = points[points.count - 1], b = points[points.count - 2]
        guard a.date.timeIntervalSince(b.date) < 15 * 60 else { return nil }
        return a.mgdl - b.mgdl
    }

    static let placeholder = WidgetSnapshot(
        points: (0..<36).map { Point(date: Date().addingTimeInterval(Double($0 - 35) * 300), mgdl: 120 + Int(30 * sin(Double($0) / 6))) },
        trendRate: 0.4, iob: 1.2, updatedAt: Date(), reservoir: 142, pumpBattery: 80, mode: "smartguard",
        sensorEnd: Date().addingTimeInterval(3 * 86400))
}

enum SharedStore {
    /// "group.<bundle id of the app>", set in both Info.plists.
    static var groupID: String? { Bundle.main.object(forInfoDictionaryKey: "OMPAppGroup") as? String }

    private static var url: URL? {
        guard let id = groupID,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return dir.appendingPathComponent("widget-snapshot.json")
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func read() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// Medtronic arrows: one from 1 mg/dL/min, two from 2, three from 3.
enum TrendArrow {
    static func text(_ rate: Double?) -> String {
        guard let rate else { return "" }
        let n = min(3, Int(abs(rate)))
        if n == 0 { return "→" }
        return String(repeating: rate > 0 ? "↑" : "↓", count: n)
    }
}

func formatDelta(_ d: Int?) -> String {
    guard let d else { return "" }
    return d > 0 ? "+\(d)" : d == 0 ? "±0" : "\(d)"
}

struct GlucoseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mgdl: Int
        var trendRate: Double?
        var delta: Int?
        var date: Date
        var iob: Double?
    }
}
