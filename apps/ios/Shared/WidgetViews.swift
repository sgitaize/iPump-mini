// SPDX-License-Identifier: GPL-3.0-or-later
// Widget and Live Activity views. Shared with the app for the debug preview gallery.
import Charts
import SwiftUI
import WidgetKit

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.colorScheme) private var colorScheme
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Set by the in-app preview gallery; widgets use the environment.
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private let unit = Prefs.unit
    private let low = Prefs.low
    private let high = Prefs.high
    private let style = Prefs.widgetStyle
    private let showIOB = Prefs.widgetShowIOB

    private var latest: WidgetSnapshot.Point? { snapshot?.latest }
    private var stale: Bool { latest.map { date.timeIntervalSince($0.date) > 15 * 60 } ?? true }
    private var valueText: String { latest.map { unit.format($0.mgdl) } ?? "–" }
    private var arrow: String { stale ? "" : TrendArrow.text(snapshot?.trendRate) }
    private var deltaText: String { stale ? "" : unit.formatDelta(snapshot?.delta) }

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(verbatim: latest == nil ? "–" : "\(valueText) \(arrow) \(deltaText)")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        case .systemMedium:
            medium
        default:
            large
        }
    }

    // MARK: Background and colours

    private var rangeColor: Color {
        guard let v = latest?.mgdl, !stale else { return .secondary }
        return RangeColor.color(v, low: low, high: high, neutral: .green)
    }

    private var valueColor: Color {
        guard let v = latest?.mgdl, !stale else { return .secondary }
        if style == .tinted { return .primary }
        return RangeColor.color(v, low: low, high: high, neutral: .primary)
    }

    @ViewBuilder private var background: some View {
        if style == .tinted, !stale, latest != nil {
            LinearGradient(colors: [rangeColor.opacity(colorScheme == .dark ? 0.35 : 0.22), rangeColor.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color(.systemBackground)
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: -2) {
                Text(verbatim: valueText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .strikethrough(stale && latest != nil)
                Text(verbatim: arrow.isEmpty ? unit.label : arrow)
                    .font(.system(size: arrow.isEmpty ? 8 : 12))
            }
            .widgetAccentable()
        }
    }

    /// Value, arrow and change in the first line, then a small curve with IOB.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: valueText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .strikethrough(stale && latest != nil)
                    .widgetAccentable()
                Text(verbatim: arrow).font(.system(size: 15, weight: .semibold))
                Text(verbatim: deltaText).font(.caption)
                Spacer(minLength: 0)
                if let l = latest {
                    Text(l.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 6) {
                Sparkline(points: points(hours: 2), low: low, high: high, lineWidth: 1.5, showRange: false)
                    .frame(maxWidth: .infinity)
                if showIOB, let iob = snapshot?.iob {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("IOB").font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(verbatim: String(format: "%.1f", iob)).font(.caption.weight(.semibold))
                    }
                }
            }
            .frame(height: 24)
        }
    }

    // MARK: Home screen

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: valueText)
                    .font(.system(size: family == .systemSmall ? 46 : 50, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .strikethrough(stale && latest != nil)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(verbatim: arrow).font(.title2.weight(.semibold)).foregroundStyle(valueColor)
            }
            HStack(spacing: 6) {
                if !deltaText.isEmpty { Text(verbatim: deltaText).fontWeight(.semibold) }
                if let l = latest { Text(l.date, style: .relative) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: unit.label).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if showIOB, let iob = snapshot?.iob {
                    Text(verbatim: insulinUnits(iob, 1)).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            header
            Spacer(minLength: 0)
            Sparkline(points: points(hours: 2), low: low, high: high, lineWidth: 2, showRange: true)
                .frame(height: 30)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                statusLines(compact: true)
            }
            .frame(width: 120, alignment: .leading)
            GlucoseChartView(points: points(hours: 3), from: date.addingTimeInterval(-3 * 3600), to: date,
                             low: low, high: high, unit: unit, compact: true)
        }
    }

    private var large: some View {
        let hours = Prefs.widgetHours
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                header
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: unit.label).font(.caption2).foregroundStyle(.secondary)
                    if let mode = snapshot?.mode { modeBadge(mode) }
                }
            }
            GlucoseChartView(points: points(hours: hours), from: date.addingTimeInterval(-Double(hours) * 3600), to: date,
                             low: low, high: high, unit: unit, compact: false)
            Divider()
            statusLines(compact: false)
        }
    }

    private func statusLines(compact: Bool) -> some View {
        let items: [(String, String, String)] = [
            showIOB ? snapshot?.iob.map { ("syringe", L10n.tr("IOB"), insulinUnits($0, 2)) } : nil,
            snapshot?.reservoir.map { ("cylinder", L10n.tr("Reservoir"), insulinUnits($0, 0)) },
            snapshot?.pumpBattery.map { ("battery.75percent", L10n.tr("Akku"), "\($0) %") },
            snapshot?.sensorEnd.map { ("sensor", L10n.tr("Sensor"), sensorLeft($0)) },
        ].compactMap { $0 }
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(items.prefix(2), id: \.1) { item in
                        Label { Text(verbatim: item.2) } icon: { Image(systemName: item.0) }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(items, id: \.1) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Label { Text(verbatim: item.1) } icon: { Image(systemName: item.0) }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(verbatim: item.2).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func modeBadge(_ mode: String) -> some View {
        let text = mode == "smartguard" ? "SmartGuard" : mode == "safe" ? L10n.tr("Sicherheitsbasal") : L10n.tr("Manuell")
        return Text(verbatim: text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill((mode == "smartguard" ? Color.teal : Color.orange).opacity(0.18)))
            .foregroundStyle(mode == "smartguard" ? Color.teal : Color.orange)
    }

    private func sensorLeft(_ end: Date) -> String {
        let h = Int(end.timeIntervalSince(date) / 3600)
        if h <= 0 { return L10n.tr("abgelaufen") }
        return h >= 24 ? L10n.tr("%d T %d h", h / 24, h % 24) : L10n.tr("%d h", h)
    }

    private func points(hours: Int) -> [WidgetSnapshot.Point] {
        let from = date.addingTimeInterval(-Double(hours) * 3600)
        return (snapshot?.points ?? []).filter { $0.date >= from }
    }
}

/// Minimal curve without axes (small widget, lock screen).
struct Sparkline: View {
    let points: [WidgetSnapshot.Point]
    let low: Int
    let high: Int
    let lineWidth: CGFloat
    let showRange: Bool

    var body: some View {
        let values = points.map(\.mgdl)
        let lo = min(values.min() ?? low, low) - 10
        let hi = max(values.max() ?? high, high) + 10
        Chart {
            if showRange {
                RectangleMark(yStart: .value("", low), yEnd: .value("", high))
                    .foregroundStyle(.green.opacity(0.12))
            }
            ForEach(points, id: \.date) { p in
                LineMark(x: .value("", p.date), y: .value("", p.mgdl))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundStyle(.primary.opacity(0.75))
            }
            if let last = points.last {
                PointMark(x: .value("", last.date), y: .value("", last.mgdl))
                    .symbolSize(lineWidth * 14)
                    .foregroundStyle(.primary)
            }
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// Curve with target range and hour axis (medium and large widget).
struct GlucoseChartView: View {
    let points: [WidgetSnapshot.Point]
    let from: Date
    let to: Date
    let low: Int
    let high: Int
    let unit: GlucoseUnit
    let compact: Bool

    var body: some View {
        let yMax = max(250, (points.map(\.mgdl).max() ?? 0) + 20)
        Chart {
            RectangleMark(yStart: .value("", low), yEnd: .value("", high))
                .foregroundStyle(.green.opacity(0.12))
            RuleMark(y: .value("", low)).foregroundStyle(.red.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            RuleMark(y: .value("", high)).foregroundStyle(.orange.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            ForEach(points, id: \.date) { p in
                PointMark(x: .value("", p.date), y: .value("", p.mgdl))
                    .symbolSize(compact ? 9 : 14)
                    .foregroundStyle(RangeColor.color(p.mgdl, low: low, high: high, neutral: .primary))
            }
        }
        .chartYScale(domain: 40...yMax)
        .chartXScale(domain: from...to)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [low, high]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) { Text(verbatim: unit.format(v)).font(.system(size: 8)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: to.timeIntervalSince(from) > 4 * 3600 ? 2 : 1)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                            .font(.system(size: 8))
                            .fixedSize()
                    }
                }
            }
        }
    }
}

/// Lock screen banner of the Live Activity.
struct LiveActivityView: View {
    let state: GlucoseActivityAttributes.ContentState
    /// Always-On display: dimmed lock screen. Draw plain white, no colours or fills.
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        let unit = Prefs.unit
        let color = dimmed ? Color.white : RangeColor.color(state.mgdl, low: Prefs.low, high: Prefs.high, neutral: .primary)
        VStack(spacing: 8) {
            header(unit: unit, color: color)
            if let curve = state.curve, curve.count > 1 {
                LiveCurve(points: curve, low: Prefs.low, high: Prefs.high, dimmed: dimmed)
                    .frame(height: 46)
            }
        }
    }

    private func header(unit: GlucoseUnit, color: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: unit.format(state.mgdl))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text(verbatim: TrendArrow.text(state.trendRate)).font(.title2.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(unit.formatDelta(state.delta)) \(unit.label)").font(.subheadline.weight(.semibold))
                Text(state.date, style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let iob = state.iob {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("IOB").font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: insulinUnits(iob, 2)).font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

/// Glucose curve of the last 3 h for the Live Activity. Awake: target range band and
/// points coloured by range. Always-On (dimmed): a thin white line only.
struct LiveCurve: View {
    let points: [GlucoseActivityAttributes.CurvePoint]
    let low: Int
    let high: Int
    let dimmed: Bool

    var body: some View {
        let values = points.map(\.v)
        let lo = Double(min(values.min() ?? low, low) - 10)
        let hi = Double(max(values.max() ?? high, high) + 10)
        Chart {
            if !dimmed {
                RectangleMark(xStart: .value("", -180), xEnd: .value("", 0),
                              yStart: .value("", low), yEnd: .value("", high))
                    .foregroundStyle(.green.opacity(0.18))
            }
            ForEach(points, id: \.self) { p in
                LineMark(x: .value("", -p.m), y: .value("", p.v))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: dimmed ? 1.5 : 2, lineCap: .round))
                    .foregroundStyle(dimmed ? Color.white.opacity(0.85) : Color.primary.opacity(0.35))
            }
            if !dimmed {
                ForEach(points, id: \.self) { p in
                    PointMark(x: .value("", -p.m), y: .value("", p.v))
                        .symbolSize(10)
                        .foregroundStyle(RangeColor.color(p.v, low: low, high: high, neutral: .primary))
                }
            }
            if let last = points.min(by: { $0.m < $1.m }) {
                PointMark(x: .value("", -last.m), y: .value("", last.v))
                    .symbolSize(dimmed ? 22 : 34)
                    .foregroundStyle(dimmed ? Color.white : RangeColor.color(last.v, low: low, high: high, neutral: .primary))
            }
        }
        .chartXScale(domain: -180...0)
        .chartYScale(domain: lo...hi)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

