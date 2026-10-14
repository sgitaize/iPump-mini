// SPDX-License-Identifier: GPL-3.0-or-later
import Charts
import MiniMedKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var link: PumpLink
    @State private var showPairing = false
    @State private var showSettings = false
    /// Selected insulin time block; tapping anywhere else clears it.
    @State private var insulinSelection: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatusBanner(showPairing: $showPairing)
                    MuteBanner()
                    SensorTypeCard()
                    GlucoseHeader()
                    GlucoseChart(insulinSelection: $insulinSelection)
                    ValueGrid()
                    Text("Nur zur Information. Keine Therapieentscheidungen auf Basis dieser App treffen – maßgeblich ist die Anzeige der Pumpe. Kein Medizinprodukt, nicht mit Medtronic verbunden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    NavigationLink("Über & Impressum") { AboutView() }
                        .font(.footnote)
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture { insulinSelection = nil }
            }
            .refreshable { link.refreshNow() }
            .navigationTitle("openMinipump")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Einstellungen")
                }
            }
            .sheet(isPresented: $showPairing) { PairingGuideView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

struct StatusBanner: View {
    @EnvironmentObject private var link: PumpLink
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var uploader: NightscoutUploader
    @Binding var showPairing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(link.phase.label).font(.headline)
                Spacer()
                if let serial = link.pumpSerial { Text(serial).font(.caption).foregroundStyle(.secondary) }
            }
            if let last = store.lastDataAt {
                Text("Letzte Daten \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if uploader.enabled {
                Label(uploader.lastError ?? "Nightscout \(uploader.lastSuccess.map { "ok, \($0.formatted(date: .omitted, time: .shortened))" } ?? "wartet")",
                      systemImage: uploader.lastError == nil ? "icloud.and.arrow.up" : "exclamationmark.icloud")
                    .font(.caption)
                    .foregroundStyle(uploader.lastError == nil ? Color.secondary : Color.red)
            }
            switch link.phase {
            case .blocked(let reason), .failed(let reason):
                Text(reason).font(.subheadline).foregroundStyle(.red)
            default:
                EmptyView()
            }
            if link.phase != .connected {
                if link.isPaired || store.lastDataAt != nil {
                    Text("Gekoppelt. Die Pumpe verbindet sich von selbst, sobald sie in Reichweite ist. Die App muss dafür geöffnet bleiben (im Hintergrund ist ok, nicht wegwischen).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if let since = link.waitingSince, context.date.timeIntervalSince(since) > 3 * 60 {
                            Text("Seit über 3 Minuten keine Verbindung: In den iPhone-Einstellungen Bluetooth kurz aus- und wieder einschalten. Die Pumpe verbindet sich dann neu.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                    Button("Neu koppeln …") { showPairing = true }
                        .font(.footnote)
                } else {
                    Text("Noch keine Pumpe gekoppelt. Die Pumpe muss einmalig mit dieser App gekoppelt werden.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showPairing = true
                    } label: {
                        Label("Pumpe koppeln", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var color: Color {
        switch link.phase {
        case .connected: .green
        case .blocked, .failed, .bluetoothOff: .red
        default: .orange
        }
    }
}

struct GlucoseHeader: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 4) {
                if let r = store.latest {
                    let age = context.date.timeIntervalSince(r.date)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(r.mgdl)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(age > 15 * 60 ? .secondary : .primary)
                            .strikethrough(age > 15 * 60)
                        Text(arrow(r.trendMgdlPerMin)).font(.system(size: 40))
                    }
                    HStack(spacing: 12) {
                        Text("mg/dL")
                        if let d = delta { Text(d > 0 ? "+\(d)" : "\(d)") }
                        Text(ageText(age))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text("–").font(.system(size: 72, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Text("Noch kein Sensorwert").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var delta: Int? {
        let r = store.readings
        guard r.count >= 2, r[r.count - 1].date.timeIntervalSince(r[r.count - 2].date) < 15 * 60 else { return nil }
        return r[r.count - 1].mgdl - r[r.count - 2].mgdl
    }

    private func ageText(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        return minutes < 1 ? "gerade eben" : "vor \(minutes) min"
    }

    /// Medtronic arrows: 1 from 1 mg/dL/min, 2 from 2, 3 from 3.
    private func arrow(_ rate: Double?) -> String {
        guard let rate else { return "" }
        let n = min(3, Int(abs(rate)))
        if n == 0 { return "→" }
        return String(repeating: rate > 0 ? "↑" : "↓", count: n)
    }
}

struct GlucoseChart: View {
    @EnvironmentObject private var store: DataStore
    @AppStorage("chartHours") private var hours = 3
    @Binding var insulinSelection: Date?

    /// Height of the insulin band below the glucose values, in chart units (mg/dL scale).
    private static let band: Double = 36
    private static let bandTop: Double = 40

    private struct InsulinSegment: Identifiable {
        let id: String
        let start: Date
        let end: Date
        let low: Double
        let high: Double
        let color: Color
    }

    private var binSize: TimeInterval { Double((hours <= 3 ? 15 : hours <= 6 ? 30 : 60) * 60) }

    /// Insulin per time block, stacked by kind, scaled into the band at the bottom. Drawn in
    /// the same chart as the glucose values so both share one time axis.
    private func insulinSegments(_ events: [Treatment], from: Date) -> [InsulinSegment] {
        let size = binSize
        let order: [(Treatment.Kind, Color)] = [(.autoBasal, .teal), (.autoCorrection, .purple), (.bolus, .blue)]
        var sums: [Double: [Treatment.Kind: Double]] = [:]
        for t in events where order.contains(where: { $0.0 == t.kind }) {
            let bin = (t.date.timeIntervalSince1970 / size).rounded(.down) * size
            sums[bin, default: [:]][t.kind, default: 0] += t.value ?? 0
        }
        let maxTotal = max(1, sums.values.map { $0.values.reduce(0, +) }.max() ?? 1)
        let scale = (Self.band - 4) / maxTotal
        var out: [InsulinSegment] = []
        for (bin, perKind) in sums where bin + size > from.timeIntervalSince1970 {
            var base = 0.0
            for (kind, color) in order {
                guard let units = perKind[kind], units > 0 else { continue }
                out.append(InsulinSegment(id: "\(bin)-\(kind)",
                                          start: Date(timeIntervalSince1970: max(bin + size * 0.1, from.timeIntervalSince1970)),
                                          end: Date(timeIntervalSince1970: bin + size * 0.9),
                                          low: base * scale, high: (base + units) * scale, color: color))
                base += units
            }
        }
        return out
    }

    private func block(for date: Date) -> (start: Date, end: Date) {
        let start = (date.timeIntervalSince1970 / binSize).rounded(.down) * binSize
        return (Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: start + binSize))
    }

    var body: some View {
        let from = Date().addingTimeInterval(-Double(hours) * 3600)
        let points = store.readings.filter { $0.date >= from }
        let events = store.treatments.filter { $0.date >= from }
        let yMax = max(250, (points.map(\.mgdl).max() ?? 0) + 40)
        let segments = insulinSegments(store.treatments.filter { $0.date >= from.addingTimeInterval(-binSize) }, from: from)
        let selected = insulinSelection.map(block(for:))
        Picker("Zeitraum", selection: $hours) {
            ForEach([3, 6, 12, 24], id: \.self) { Text("\($0) h").tag($0) }
        }
        .pickerStyle(.segmented)
        Chart {
            RectangleMark(yStart: .value("", 70), yEnd: .value("", 180))
                .foregroundStyle(.green.opacity(0.12))
            RuleMark(y: .value("", Self.bandTop))
                .foregroundStyle(.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
            if let selected {
                RectangleMark(xStart: .value("Von", selected.start), xEnd: .value("Bis", selected.end),
                              yStart: .value("", 0), yEnd: .value("", Self.bandTop))
                    .foregroundStyle(.gray.opacity(0.18))
            }
            ForEach(segments) { s in
                RectangleMark(xStart: .value("Von", s.start), xEnd: .value("Bis", s.end),
                              yStart: .value("IE", s.low), yEnd: .value("IE", s.high))
                    .foregroundStyle(s.color)
            }
            ForEach(points, id: \.date) { r in
                PointMark(x: .value("Zeit", r.date), y: .value("mg/dL", r.mgdl))
                    .symbolSize(hours > 6 ? 10 : 24)
                    .foregroundStyle(r.mgdl < 70 ? .red : r.mgdl > 180 ? .orange : .primary)
            }
            ForEach(events.filter { $0.kind == .suspend || $0.kind == .resume }) { t in
                RuleMark(x: .value("Zeit", t.date))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            // Only user boluses and carbs as symbols; SmartGuard insulin is in the band.
            ForEach(events.filter { $0.kind == .carbs }) { t in
                PointMark(x: .value("Zeit", t.date), y: .value("mg/dL", yMax - 15))
                    .symbol(.circle)
                    .symbolSize(70)
                    .foregroundStyle(.orange)
                    .annotation(position: .bottom, spacing: 2) {
                        if hours <= 6 { Text("\(Int(t.value ?? 0)) g").font(.system(size: 9)).foregroundStyle(.orange) }
                    }
            }
            ForEach(events.filter { $0.kind == .bolus }) { t in
                PointMark(x: .value("Zeit", t.date), y: .value("mg/dL", yMax - 45))
                    .symbol(.triangle)
                    .symbolSize(70)
                    .foregroundStyle(.blue)
                    .annotation(position: .bottom, spacing: 2) {
                        if hours <= 6 { Text(String(format: "%.1f", t.value ?? 0)).font(.system(size: 9)).foregroundStyle(.blue) }
                    }
            }
            ForEach(events.filter { $0.kind == .bgCheck || $0.kind == .calibration }) { t in
                PointMark(x: .value("Zeit", t.date), y: .value("mg/dL", t.value ?? 0))
                    .symbol(.diamond)
                    .symbolSize(60)
                    .foregroundStyle(.red)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .trailing, values: Array(stride(from: 50, through: yMax, by: 50)))
        }
        .chartXScale(domain: from...Date())
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: hours <= 6 ? 1 : hours <= 12 ? 2 : 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
            }
        }
        .chartPlotStyle { $0.clipped() }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame else { return }
                        let origin = geo[frame].origin
                        guard let date: Date = proxy.value(atX: location.x - origin.x),
                              let y: Double = proxy.value(atY: location.y - origin.y) else { return }
                        // Taps in the insulin band select a block; anywhere else clears it.
                        if y <= Self.bandTop, segments.contains(where: { block(for: $0.start).start == block(for: date).start }) {
                            if let current = insulinSelection, block(for: current).start == block(for: date).start {
                                insulinSelection = nil
                            } else {
                                insulinSelection = date
                            }
                        } else {
                            insulinSelection = nil
                        }
                    }
            }
        }
        .frame(height: 240)
        .overlay {
            if points.isEmpty { Text("Keine Werte in diesem Zeitraum").font(.caption).foregroundStyle(.secondary) }
        }
        if let selected {
            InsulinBlockDetail(start: selected.start, end: selected.end,
                               items: store.treatments.filter {
                                   [.autoBasal, .autoCorrection, .bolus].contains($0.kind) && $0.date >= selected.start && $0.date < selected.end
                               })
        } else if !segments.isEmpty {
            Text("Insulin-Balken unten antippen für Details").font(.caption2).foregroundStyle(.secondary)
        }
        ChartLegend()
    }
}

/// Details of one insulin time block: sums per kind and the single deliveries.
struct InsulinBlockDetail: View {
    let start: Date
    let end: Date
    let items: [Treatment]

    var body: some View {
        let time = start.formatted(date: .omitted, time: .shortened) + "–" + end.formatted(date: .omitted, time: .shortened)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(time).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f IE", items.reduce(0) { $0 + ($1.value ?? 0) })).font(.subheadline.monospacedDigit())
            }
            if items.isEmpty {
                Text("Keine Abgaben in diesem Zeitraum").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 14) {
                    sum(.bolus, "Bolus", .blue)
                    sum(.autoCorrection, "Autokorrektur", .purple)
                    sum(.autoBasal, "Auto-Basal", .teal)
                }
                .font(.caption)
                ForEach(items.sorted { $0.date < $1.date }) { t in
                    HStack {
                        Circle().fill(color(t.kind)).frame(width: 6, height: 6)
                        Text(t.date.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                        Text(label(t.kind)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.3f IE", t.value ?? 0)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func sum(_ kind: Treatment.Kind, _ title: String, _ c: Color) -> some View {
        let total = items.filter { $0.kind == kind }.reduce(0) { $0 + ($1.value ?? 0) }
        return HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text("\(title) \(String(format: "%.2f", total))")
        }
        .opacity(total > 0 ? 1 : 0.4)
    }

    private func color(_ k: Treatment.Kind) -> Color { k == .bolus ? .blue : k == .autoCorrection ? .purple : .teal }
    private func label(_ k: Treatment.Kind) -> String { k == .bolus ? "Bolus" : k == .autoCorrection ? "Autokorrektur" : "Auto-Basal" }
}

struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            legend("triangle.fill", .blue, "Bolus")
            legend("circle.fill", .orange, "KH")
            legend("diamond.fill", .red, "BZ/Kalibr.")
            legend("square.fill", .purple, "Autokorr.")
            legend("square.fill", .teal, "Auto-Basal")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legend(_ symbol: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) { Image(systemName: symbol).foregroundStyle(color); Text(text) }
    }
}

struct ValueGrid: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var link: PumpLink

    var body: some View {
        let s = store.snapshot
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Tile(title: "Aktives Insulin", value: s.iob.map { String(format: "%.2f IE", $0.units) })
            Tile(title: "Reservoir", value: s.status.map { String(format: "%.0f IE", $0.reservoirUnits) })
            Tile(title: "Modus", value: s.algorithm?.modeDescription,
                 detail: s.status.map { $0.isSuspended ? "Abgabe angehalten" : "Abgabe läuft" })
            Tile(title: "Basalrate", value: basalText(s),
                 detail: s.basal?.tempBasalUnitsPerHour != nil ? "temporär" : s.algorithm?.shieldState == .autoBasal ? "von SmartGuard gesteuert" : nil)
            Tile(title: "Zeit im Zielbereich", value: s.timeInRange.map { "\($0.inRangePercent) %" },
                 detail: s.timeInRange.map { "↑ \($0.abovePercent) %  ↓ \($0.belowPercent) %" })
            Tile(title: "Pumpenbatterie", value: s.pumpBatteryPercent.map { "\($0) %" })
            Tile(title: "Sensor", value: s.status.map { $0.sensorOK ? "Sensor ok" : $0.sensorMessage },
                 detail: s.sensorEnd.map { expiry(Int($0.timeIntervalSinceNow / 60)) },
                 systemImage: s.status.map { $0.sensorOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" },
                 tint: s.status.map { $0.sensorOK ? .green : .orange })
            if SensorType.current.hasTransmitter {
                Tile(title: "Transmitter", value: s.transmitterBatteryPercent.map { "\($0) %" })
            }
        }
        if s.updatedAt > .distantPast {
            Text("Pumpenstatus aktualisiert \(s.updatedAt.formatted(date: .omitted, time: .shortened))\(link.pumpFirmware.map { " · FW \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func basalText(_ s: PumpSnapshot) -> String? {
        guard let basal = s.basal else { return nil }
        if let temp = basal.tempBasalUnitsPerHour { return String(format: "%.3f IE/h", temp) }
        if s.algorithm?.shieldState == .autoBasal { return "Auto" }
        return String(format: "%.3f IE/h", basal.unitsPerHour)
    }

    private func expiry(_ minutes: Int) -> String {
        if minutes <= 0 { return "abgelaufen" }
        let h = minutes / 60
        return h >= 24 ? "noch \(h / 24) T \(h % 24) h" : "noch \(h) h \(minutes % 60) min"
    }
}

struct Tile: View {
    let title: String
    let value: String?
    var detail: String?
    var systemImage: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).foregroundStyle(tint ?? .primary) }
                Text(value ?? "–").font(.title3.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.7)
            }
            if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Sensor generation: Guardian 4 has a separate transmitter (with battery), Simplera Sync
/// is an all-in-one sensor without one.
enum SensorType: String, CaseIterable, Identifiable {
    case unknown = ""
    case simplera
    case guardian

    var id: String { rawValue }
    static let key = "sensorType"
    static var current: SensorType { SensorType(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .unknown }
    var hasTransmitter: Bool { self != .simplera }

    var label: String {
        switch self {
        case .unknown: "Nicht festgelegt"
        case .simplera: "Simplera Sync (ohne Transmitter)"
        case .guardian: "Guardian 4 (mit Transmitter)"
        }
    }
}

/// Asked once after pairing; also changeable in the settings.
struct SensorTypeCard: View {
    @AppStorage(SensorType.key) private var sensorType = ""
    @EnvironmentObject private var link: PumpLink
    @EnvironmentObject private var store: DataStore

    var body: some View {
        if sensorType.isEmpty, link.isPaired || store.lastDataAt != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Welchen Sensor verwendest du?").font(.headline)
                Text("Damit nur passende Werte angezeigt werden. Später änderbar in den Einstellungen.")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach([SensorType.simplera, .guardian]) { type in
                    Button { sensorType = type.rawValue } label: {
                        Text(type.label).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// Shows a global alarm mute with a way to lift it.
struct MuteBanner: View {
    @ObservedObject private var engine = AlarmEngine.shared

    var body: some View {
        if let until = engine.mutedUntil, until > Date() {
            HStack {
                Image(systemName: "bell.slash")
                Text("Alarme stumm bis \(until.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Button("Aufheben") { engine.muteAll(minutes: nil) }
            }
            .font(.subheadline)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
