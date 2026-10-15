// SPDX-License-Identifier: GPL-3.0-or-later
import ActivityKit
import Charts
import SwiftUI
import WidgetKit

@main
struct OpenMinipumpWidgets: WidgetBundle {
    var body: some Widget {
        GlucoseWidget()
        GlucoseLiveActivity()
    }
}

// MARK: - Timeline

struct GlucoseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> GlucoseEntry { GlucoseEntry(date: Date(), snapshot: .placeholder) }

    func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        completion(GlucoseEntry(date: Date(), snapshot: context.isPreview ? .placeholder : SharedStore.read()))
    }

    /// The app reloads the timeline on every new value; entries every 5 min keep the
    /// "age"/staleness correct in between.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        Task {
            // App Group file first; without App Groups (free developer team) fall back to the
            // app's local Nightscout-compatible server (answers while the app is not suspended).
            let snapshot: WidgetSnapshot?
            if let shared = SharedStore.read() { snapshot = shared } else { snapshot = await LocalAPI.snapshot() }
            let now = Date()
            let entries = (0..<7).map { GlucoseEntry(date: now.addingTimeInterval(Double($0) * 300), snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(snapshot == nil ? 5 * 60 : 30 * 60))))
        }
    }
}

// MARK: - Home and lock screen widget

struct GlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "glucose", provider: Provider()) { entry in
            GlucoseWidgetView(date: entry.date, snapshot: entry.snapshot)
                .environment(\.locale, L10n.locale)
        }
        .configurationDisplayName("Glukose")
        .description("Aktueller Sensorwert mit Trend, groß mit Verlauf.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Live Activity / Dynamic Island

struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            LiveActivityView(state: context.state)
                .environment(\.locale, L10n.locale)
                .padding(16)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let unit = Prefs.unit
            let s = context.state
            let color = RangeColor.color(s.mgdl, low: Prefs.low, high: Prefs.high, neutral: .primary)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: unit.format(s.mgdl)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(color)
                        Text(verbatim: TrendArrow.text(s.trendRate)).font(.title3.weight(.semibold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: unit.formatDelta(s.delta)).font(.headline)
                        Text(verbatim: unit.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(s.date, style: .relative)
                        Spacer()
                        if let iob = s.iob { Text(verbatim: String(format: "IOB %.2f IE", iob)) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(verbatim: "\(unit.format(s.mgdl))\(TrendArrow.text(s.trendRate))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            } compactTrailing: {
                Text(verbatim: unit.formatDelta(s.delta)).font(.caption)
            } minimal: {
                Text(verbatim: unit.format(s.mgdl)).font(.caption2.weight(.semibold)).foregroundStyle(color)
            }
        }
    }
}

/// Reads the last 3 h from the app's local server (http://127.0.0.1:17580).
enum LocalAPI {
    static func snapshot() async -> WidgetSnapshot? {
        guard let url = URL(string: "http://127.0.0.1:17580/api/v1/entries.json?count=40") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let points = entries.compactMap { e -> WidgetSnapshot.Point? in
            guard let sgv = (e["sgv"] as? NSNumber)?.intValue, let ms = (e["date"] as? NSNumber)?.doubleValue else { return nil }
            return WidgetSnapshot.Point(date: Date(timeIntervalSince1970: ms / 1000), mgdl: sgv)
        }
        .filter { $0.date > Date().addingTimeInterval(-3 * 3600) }
        .sorted { $0.date < $1.date }
        guard !points.isEmpty else { return nil }
        let rate = (entries.first?["trendRate"] as? NSNumber)?.doubleValue
        var iob: Double?
        if let dsURL = URL(string: "http://127.0.0.1:17580/api/v1/devicestatus.json"),
           let (dsData, _) = try? await URLSession.shared.data(from: dsURL),
           let ds = (try? JSONSerialization.jsonObject(with: dsData) as? [[String: Any]])?.first,
           let pump = ds["pump"] as? [String: Any], let i = pump["iob"] as? [String: Any] {
            iob = (i["iob"] as? NSNumber)?.doubleValue
        }
        return WidgetSnapshot(points: points, trendRate: rate, iob: iob, updatedAt: Date())
    }
}
