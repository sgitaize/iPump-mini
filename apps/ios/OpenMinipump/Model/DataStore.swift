// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import MiniMedKit
import UIKit

/// Holds the data read from the pump, persists it and publishes a thread-safe copy
/// for the local API server.
@MainActor
final class DataStore: ObservableObject {
    @Published private(set) var readings: [GlucoseReading] = []
    @Published private(set) var snapshot = PumpSnapshot()
    @Published private(set) var lastDataAt: Date?
    @Published private(set) var treatments: [Treatment] = []
    /// Insulin on board over time (one sample per pump refresh), for the chart details.
    @Published private(set) var iobHistory: [IOBSample] = []
    /// Reservoir and pump battery over time (about every 15 min, 30 days) for the supply forecast.
    @Published private(set) var supplyHistory: [SupplySample] = []

    /// Thread-safe view for the API server (runs on its own queue).
    let shared = SharedData()

    /// Called once per genuinely new sensor value (not for updates of a known one).
    var onNewReading: (() -> Void)?
    /// Called when the newest value changed without a new live value: filled in from the pump
    /// history or replaced by a later copy. Widgets, Live Activity and API must follow it.
    var onLatestChanged: (() -> Void)?

    private let retention: TimeInterval = 14 * 24 * 3600
    private let fileURL: URL
    private static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("openminipump-store.json")
    }

    private struct Persisted: Codable {
        var readings: [GlucoseReading]
        var snapshot: PumpSnapshot
        var lastDataAt: Date?
        var treatments: [Treatment]?
        var iobHistory: [IOBSample]?
        var supplyHistory: [SupplySample]?
    }

    /// `fileURL` is only overridden by tests (own file instead of the real store).
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let data = try? Data(contentsOf: self.fileURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            readings = p.readings
            snapshot = p.snapshot
            lastDataAt = p.lastDataAt
            treatments = p.treatments ?? []
            iobHistory = p.iobHistory ?? []
            supplyHistory = p.supplyHistory ?? []
        }
        publish()
    }

    var latest: GlucoseReading? { readings.last }

    /// IOB sample closest to `date` (within 5 min).
    func iob(at date: Date) -> Double? {
        iobHistory.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            .flatMap { abs($0.date.timeIntervalSince(date)) <= 300 ? $0.units : nil }
    }

    /// false in demo mode: nothing is written to disk, so real data stays untouched.
    private(set) var persistenceEnabled = true
    private var demoTimer: Timer?

    /// Synthetic values for demo mode (App Review, screenshots). Disables saving and adds a
    /// new simulated value every 5 minutes so widgets and the Live Activity keep moving.
    func loadDemoData() {
        persistenceEnabled = false
        let now = Date()
        // 14 days of values (patterns need them); the last 6 hours are the plain wave, older ones
        // add a breakfast peak on most days and a few night lows on top of it.
        let cal = Calendar.current
        func demoValue(_ t: Double) -> Double {
            let base = 130 + 50 * sin(t / 9)
            guard t >= 72 else { return base }
            let date = now.addingTimeInterval(-t * 300)
            let hour = Double(cal.component(.hour, from: date)) + Double(cal.component(.minute, from: date)) / 60
            let day = Int((cal.startOfDay(for: date).timeIntervalSince1970 / 86400).rounded())
            func bump(_ from: Double, _ to: Double) -> Double {
                hour > from && hour < to ? pow(sin((hour - from) / (to - from) * .pi), 2) : 0
            }
            var v = base
            if day % 7 < 4 { v += 95 * bump(8.2, 11.2) }                      // after breakfast on 4 of 7 days
            if day % 5 == 0 { v -= bump(1.5, 4.5) * (base - 58) }             // night low on some days
            return v
        }
        readings = (0..<(14 * 288)).map { i in
            let t = Double(14 * 288 - 1 - i)
            return GlucoseReading(date: now.addingTimeInterval(-t * 300), mgdl: Int(demoValue(t)),
                                  trendMgdlPerMin: (demoValue(t - 1) - demoValue(t)) / 5,
                                  sessionOffsetMinutes: UInt16(60000 - Int(t) * 5))
        }
        var s = PumpSnapshot(updatedAt: now)
        s.pumpBatteryPercent = 75
        s.transmitterBatteryPercent = 100
        s.sensorEnd = now.addingTimeInterval(3 * 86400 + 5 * 3600)
        snapshot = s
        // Split into typed steps: one long expression ran into the type-checker time limit
        // in Release builds on CI.
        var demoTreatments: [Treatment] = [
            Treatment(id: 1, date: now.addingTimeInterval(-150 * 60), kind: .carbs, value: 45),
            Treatment(id: 2, date: now.addingTimeInterval(-148 * 60), kind: .bolus, value: 3.5),
            Treatment(id: 3, date: now.addingTimeInterval(-60 * 60), kind: .calibration, value: 152),
            Treatment(id: 4, date: now.addingTimeInterval(-40 * 60), kind: .autoCorrection, value: 0.45),
            Treatment(id: 5, date: now.addingTimeInterval(-25 * 60), kind: .autoCorrection, value: 0.6),
        ]
        let basalSteps: [Double] = [0.05, 0.1, 0.0, 0.15, 0.05]
        for i in 0..<36 where basalSteps[i % 5] > 0 {
            let date: Date = now.addingTimeInterval(-Double(i) * 300)
            demoTreatments.append(Treatment(id: UInt32(10 + i), date: date, kind: .autoBasal, value: basalSteps[i % 5]))
        }
        treatments = demoTreatments
        // Breakfast on the last 14 days (for the pattern card), id range separate from the above.
        treatments += (1...14).compactMap { d -> [Treatment]? in
            guard let day = cal.date(byAdding: .day, value: -d, to: cal.startOfDay(for: now)) else { return nil }
            let at = day.addingTimeInterval(7.5 * 3600)
            return [Treatment(id: UInt32(1000 + d * 2), date: at, kind: .carbs, value: 40),
                    Treatment(id: UInt32(1001 + d * 2), date: at.addingTimeInterval(120), kind: .bolus, value: 3.5)]
        }.flatMap { $0 }
        treatments.sort { $0.date < $1.date }   // like addTreatments
        supplyHistory = Self.demoSupplyHistory(now: now)
        // Ends at the current IOB of the status below (1.85 U) and decays towards it.
        iobHistory = (0..<72).map { i in IOBSample(date: now.addingTimeInterval(-Double(71 - i) * 300), units: 1.85 + Double(71 - i) * 0.03) }
        // Pump status from JSON (the types are Codable and otherwise only parsed from bytes).
        func decode<T: Decodable>(_ json: String) -> T? { try? JSONDecoder().decode(T.self, from: Data(json.utf8)) }
        var demo = snapshot
        demo.status = decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":142,"reservoirAttached":true,"sensorConnectivity":1,"sensorMessageState":0}"#)
        demo.iob = decode(#"{"units":1.85,"remainingDurationMinutes":150}"#)
        demo.timeInRange = decode(#"{"notEnoughData":false,"abovePercent":14,"belowPercent":2,"inRangePercent":84,"smartGuardPercent":98}"#)
        demo.algorithm = decode(#"{"shieldState":2,"readinessState":0}"#)
        demo.basal = decode(#"{"profileNumber":1,"unitsPerHour":0.85}"#)
        snapshot = demo
        lastDataAt = now
        touched()
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.addDemoReading() }
        }
    }

    /// Ten days of supply samples that end at the demo status (142 U, 75 %): reservoir changed
    /// about 4 days ago, battery drops about 4 % a day, consumption with meal peaks.
    static func demoSupplyHistory(now: Date) -> [SupplySample] {
        let cal = Calendar.current
        var reservoir = 142.0, battery = 75.0
        var out: [SupplySample] = []
        for i in 0..<(10 * 96) {
            let date = now.addingTimeInterval(-Double(i) * 900)
            out.append(SupplySample(date: date, reservoir: reservoir.rounded(), battery: battery.rounded()))
            let hour = cal.component(.hour, from: date)
            let wd = cal.component(.weekday, from: date)
            let day = Int((cal.startOfDay(for: date).timeIntervalSince1970 / 86400).rounded())
            var rate = 0.9 + ([7, 12, 18].contains(hour) ? 3.2 : 0)           // U per hour
            if wd == 1 || wd == 7 { rate *= 0.85 }
            rate *= 1 + 0.08 * sin(Double(day) * 1.7)
            reservoir += rate / 4
            if reservoir > 300 { reservoir = 12 }                             // earlier reservoir
            battery += 4.0 / 96
            if battery > 100 { battery = 8 }                                  // earlier battery
        }
        return out.reversed()
    }

    private func addDemoReading() {
        let now = Date()
        let t = now.timeIntervalSince1970 / 300
        let mgdl = Int(130 + 50 * sin(t / 9))
        add(GlucoseReading(date: now, mgdl: mgdl, trendMgdlPerMin: 50.0 / 45.0 * cos(t / 9), sessionOffsetMinutes: nil))
    }

    /// Maximum clock skew accepted for a value from the future (pump and iPhone clocks).
    static let futureTolerance: TimeInterval = 300
    /// The sensor reports 40–400 mg/dL; anything else is a decoding or transfer error.
    static let plausibleRange = 40...400

    /// One rule for every way a value comes in (live, pump history, Nightscout): inside the
    /// retention window, at most 5 min in the future, within the sensor range.
    func isPlausible(_ r: GlucoseReading, now: Date = Date()) -> Bool {
        r.date >= now.addingTimeInterval(-retention)
            && r.date <= now.addingTimeInterval(Self.futureTolerance)
            && Self.plausibleRange.contains(r.mgdl)
    }

    /// Adds a live value. Returns false if it was rejected as implausible.
    @discardableResult
    func add(_ reading: GlucoseReading) -> Bool {
        guard isPlausible(reading) else { return false }
        // Same sensor record (offset) or a value within 2 minutes counts as duplicate.
        if let i = readings.lastIndex(where: {
            ($0.sessionOffsetMinutes != nil && $0.sessionOffsetMinutes == reading.sessionOffsetMinutes
                && abs($0.date.timeIntervalSince(reading.date)) < 3600)
                || abs($0.date.timeIntervalSince(reading.date)) < 120
        }) {
            let wasLatest = i == readings.count - 1
            readings[i] = reading
            readings.sort { $0.date < $1.date }
            touched()
            if wasLatest || latest?.date == reading.date { onLatestChanged?() }
            return true
        }
        readings.append(reading)
        readings.sort { $0.date < $1.date }
        let cutoff = Date().addingTimeInterval(-retention)
        readings.removeAll { $0.date < cutoff }
        touched()
        onNewReading?()
        return true
    }

    /// Merges values from the pump history or from Nightscout. Does not trigger the
    /// "new reading" upload; returns the values that were actually new.
    @discardableResult
    func merge(_ incoming: [GlucoseReading]) -> [GlucoseReading] {
        var added: [GlucoseReading] = []
        let latestBefore = latest?.date
        let now = Date()
        for r in incoming where isPlausible(r, now: now) {
            if readings.contains(where: { abs($0.date.timeIntervalSince(r.date)) < 120 }) { continue }
            readings.append(r)
            added.append(r)
        }
        guard !added.isEmpty else { return [] }
        readings.sort { $0.date < $1.date }
        touched()
        if latest?.date != latestBefore { onLatestChanged?() }
        return added
    }

    /// Adds pump history treatments (deduplicated by sequence number); returns the new ones.
    @discardableResult
    func addTreatments(_ incoming: [Treatment]) -> [Treatment] {
        let known = Set(treatments.map(\.id))
        let new = incoming.filter { !known.contains($0.id) }
        guard !new.isEmpty else { return [] }
        treatments.append(contentsOf: new)
        treatments.sort { $0.date < $1.date }
        let cutoff = Date().addingTimeInterval(-retention)
        treatments.removeAll { $0.date < cutoff }
        touched()
        return new
    }

    func resetTreatments() {
        treatments = []
        touched()
    }

    func update(_ change: (inout PumpSnapshot) -> Void) {
        let oldIOB = snapshot.iob
        change(&snapshot)
        if let iob = snapshot.iob, iob != oldIOB || iobHistory.last.map({ Date().timeIntervalSince($0.date) > 240 }) ?? true {
            iobHistory.append(IOBSample(date: Date(), units: iob.units))
            let cutoff = Date().addingTimeInterval(-retention)
            iobHistory.removeAll { $0.date < cutoff }
        }
        snapshot.updatedAt = Date()
        recordSupply()
        touched()
    }

    /// Stores reservoir and battery as a supply sample (at most every 15 min).
    private func recordSupply() {
        guard persistenceEnabled else { return }
        let reservoir = snapshot.status.flatMap { $0.reservoirAttached ? $0.reservoirUnits : nil }
        let sample = SupplySample(date: Date(), reservoir: reservoir, battery: snapshot.pumpBatteryPercent.map(Double.init))
        SupplyHistory.record(sample, into: &supplyHistory)
    }

    private func touched() {
        lastDataAt = Date()
        publish()
        save()
    }

    private func publish() {
        let level = UIDevice.current.batteryLevel
        shared.set(readings: readings, snapshot: snapshot, treatments: treatments,
                   uploaderBattery: level >= 0 ? Int((level * 100).rounded()) : nil)
    }

    private func save() {
        guard persistenceEnabled else { return }
        let p = Persisted(readings: readings, snapshot: snapshot, lastDataAt: lastDataAt, treatments: treatments,
                          iobHistory: iobHistory, supplyHistory: supplyHistory)
        if let data = try? JSONEncoder().encode(p) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}

final class SharedData: @unchecked Sendable {
    private let lock = NSLock()
    private var _readings: [GlucoseReading] = []
    private var _snapshot = PumpSnapshot()
    private var _uploaderBattery: Int?
    private var _treatments: [Treatment] = []

    func set(readings: [GlucoseReading], snapshot: PumpSnapshot, treatments: [Treatment], uploaderBattery: Int?) {
        lock.lock(); defer { lock.unlock() }
        _readings = readings
        _snapshot = snapshot
        _treatments = treatments
        _uploaderBattery = uploaderBattery
    }

    var treatments: [Treatment] {
        lock.lock(); defer { lock.unlock() }
        return _treatments
    }

    func get() -> (readings: [GlucoseReading], snapshot: PumpSnapshot, uploaderBattery: Int?) {
        lock.lock(); defer { lock.unlock() }
        return (_readings, _snapshot, _uploaderBattery)
    }

    // MARK: Wake schedule for clients of the local API
    // In the background the app (and its server) only runs for a short window after
    // each pump update. Clients such as watch faces use this schedule to poll then.

    private var _wakes: [Date] = []

    func recordWake(_ date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        if let last = _wakes.last, date.timeIntervalSince(last) < 60 { return }
        _wakes.append(date)
        if _wakes.count > 7 { _wakes.removeFirst(_wakes.count - 7) }
    }

    /// Last wake, the typical interval (median of recent gaps, 5 min by default) and the
    /// next expected wake (always in the future).
    func wakeSchedule(now: Date = Date()) -> (last: Date, interval: TimeInterval, next: Date)? {
        lock.lock(); defer { lock.unlock() }
        guard let last = _wakes.last else { return nil }
        let gaps = zip(_wakes.dropFirst(), _wakes).map { $0.timeIntervalSince($1) }.filter { $0 >= 120 && $0 <= 900 }.sorted()
        let interval = gaps.isEmpty ? 300 : gaps[gaps.count / 2]
        var next = last.addingTimeInterval(interval)
        while next < now { next.addTimeInterval(interval) }
        return (last, interval, next)
    }
}

/// In-memory log shown in the app (diagnostics for the first device tests).
@MainActor
final class EventLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let level: Level
        let text: String
    }

    enum Level { case info, warning, error, blocked }

    @Published private(set) var entries: [Entry] = []

    /// Also written to Application Support/openminipump.log (rotated at 2 MB), so background
    /// behaviour can be analysed later (pull via Xcode/devicectl or share in the app).
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("openminipump.log")
    }()
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    private lazy var handle: FileHandle? = {
        let url = Self.fileURL
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 2_000_000 {
            let old = url.deletingPathExtension().appendingPathExtension("1.log")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil,
                                           attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()

    func add(_ text: String, _ level: Level = .info) {
        let entry = Entry(level: level, text: text)
        entries.append(entry)
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        print("[omp] \(text)")
        let line = "\(formatter.string(from: entry.date)) [\(level)] \(text)\n"
        try? handle?.write(contentsOf: Data(line.utf8))
    }

    var exportText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "\(f.string(from: $0.date)) [\($0.level)] \($0.text)" }.joined(separator: "\n")
    }
}

struct IOBSample: Codable, Equatable {
    let date: Date
    let units: Double
}
