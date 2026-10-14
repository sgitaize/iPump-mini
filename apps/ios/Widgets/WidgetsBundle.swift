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
            GlucoseWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Glukose")
        .description("Aktueller Sensorwert mit Trend, groß mit Verlauf.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GlucoseEntry

    private var latest: WidgetSnapshot.Point? { entry.snapshot?.latest }
    private var stale: Bool { latest.map { entry.date.timeIntervalSince($0.date) > 15 * 60 } ?? true }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(latest.map { "\($0.mgdl) \(TrendArrow.text(entry.snapshot?.trendRate)) \(formatDelta(entry.snapshot?.delta))" } ?? "–")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text(latest.map { "\($0.mgdl)" } ?? "–").font(.title3.weight(.semibold)).strikethrough(stale)
                Text(TrendArrow.text(entry.snapshot?.trendRate)).font(.caption)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(latest.map { "\($0.mgdl)" } ?? "–").font(.title2.weight(.semibold)).strikethrough(stale)
                    Text(TrendArrow.text(entry.snapshot?.trendRate))
                    Text(formatDelta(entry.snapshot?.delta)).font(.caption)
                }
                if let l = latest { Text(l.date, style: .relative).font(.caption2) }
            }
        case .systemSmall:
            small
        default:
            large
        }
    }

    private var valueColor: Color {
        guard let v = latest?.mgdl, !stale else { return .secondary }
        return v < 70 ? .red : v > 180 ? .orange : .primary
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(latest.map { "\($0.mgdl)" } ?? "–")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
                    .strikethrough(stale)
                    .minimumScaleFactor(0.6)
                Text(TrendArrow.text(entry.snapshot?.trendRate)).font(.title2)
            }
            HStack(spacing: 6) {
                Text(formatDelta(entry.snapshot?.delta))
                if let l = latest { Text(l.date, style: .relative) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var small: some View {
        VStack(alignment: .leading) {
            Text("mg/dL").font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            header
            if let iob = entry.snapshot?.iob {
                Text(String(format: "IOB %.2f IE", iob)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                header
                Spacer()
                if let iob = entry.snapshot?.iob {
                    VStack(alignment: .trailing) {
                        Text("IOB").font(.caption2).foregroundStyle(.secondary)
                        Text(String(format: "%.2f IE", iob)).font(.subheadline.weight(.semibold))
                    }
                }
            }
            if let points = entry.snapshot?.points, !points.isEmpty {
                Chart {
                    RectangleMark(yStart: .value("", 70), yEnd: .value("", 180)).foregroundStyle(.green.opacity(0.12))
                    ForEach(points, id: \.date) { p in
                        PointMark(x: .value("Zeit", p.date), y: .value("mg/dL", p.mgdl))
                            .symbolSize(family == .systemLarge ? 18 : 10)
                            .foregroundStyle(p.mgdl < 70 ? .red : p.mgdl > 180 ? .orange : .primary)
                    }
                }
                .chartYScale(domain: 40...max(250, (points.map(\.mgdl).max() ?? 0) + 20))
                .chartXScale(domain: entry.date.addingTimeInterval(-3 * 3600)...entry.date)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    }
                }
            }
        }
    }
}

// MARK: - Live Activity / Dynamic Island

struct GlucoseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GlucoseActivityAttributes.self) { context in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(context.state.mgdl)").font(.system(size: 40, weight: .bold, design: .rounded))
                Text(TrendArrow.text(context.state.trendRate)).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDelta(context.state.delta)).font(.subheadline.weight(.semibold))
                    Text(context.state.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("mg/dL").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(context.state.mgdl)").font(.title.weight(.bold))
                        Text(TrendArrow.text(context.state.trendRate))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(formatDelta(context.state.delta)).font(.headline)
                        Text("mg/dL").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Text("\(context.state.mgdl)\(TrendArrow.text(context.state.trendRate))").font(.caption.weight(.semibold))
            } compactTrailing: {
                Text(formatDelta(context.state.delta)).font(.caption)
            } minimal: {
                Text("\(context.state.mgdl)").font(.caption2.weight(.semibold))
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
