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

    /// Thread-safe view for the API server (runs on its own queue).
    let shared = SharedData()

    /// Called once per genuinely new sensor value (not for updates of a known one).
    var onNewReading: (() -> Void)?

    private let retention: TimeInterval = 7 * 24 * 3600
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("openminipump-store.json")
    }()

    private struct Persisted: Codable {
        var readings: [GlucoseReading]
        var snapshot: PumpSnapshot
        var lastDataAt: Date?
    }

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        if let data = try? Data(contentsOf: fileURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            readings = p.readings
            snapshot = p.snapshot
            lastDataAt = p.lastDataAt
        }
        publish()
    }

    var latest: GlucoseReading? { readings.last }

    #if DEBUG
    /// Synthetic values for simulator tests (launch argument -demoData). Never in release builds.
    func loadDemoData() {
        let now = Date()
        readings = (0..<72).map { i in
            let t = Double(71 - i)
            let mgdl = Int(130 + 50 * sin(t / 9))
            return GlucoseReading(date: now.addingTimeInterval(-t * 300), mgdl: mgdl,
                                  trendMgdlPerMin: -50.0 / 45.0 * cos(t / 9), sessionOffsetMinutes: UInt16(5000 - Int(t) * 5))
        }
        var s = PumpSnapshot(updatedAt: now)
        s.pumpBatteryPercent = 75
        s.transmitterBatteryPercent = 100
        s.sensorEnd = now.addingTimeInterval(3 * 86400 + 5 * 3600)
        snapshot = s
        touched()
    }
    #endif

    func add(_ reading: GlucoseReading) {
        // Same sensor record (offset) or a value within 2 minutes counts as duplicate.
        if let i = readings.lastIndex(where: {
            ($0.sessionOffsetMinutes != nil && $0.sessionOffsetMinutes == reading.sessionOffsetMinutes
                && abs($0.date.timeIntervalSince(reading.date)) < 3600)
                || abs($0.date.timeIntervalSince(reading.date)) < 120
        }) {
            readings[i] = reading
        } else {
            readings.append(reading)
            readings.sort { $0.date < $1.date }
            let cutoff = Date().addingTimeInterval(-retention)
            readings.removeAll { $0.date < cutoff }
            touched()
            onNewReading?()
            return
        }
        touched()
    }

    func update(_ change: (inout PumpSnapshot) -> Void) {
        change(&snapshot)
        snapshot.updatedAt = Date()
        touched()
    }

    private func touched() {
        lastDataAt = Date()
        publish()
        save()
    }

    private func publish() {
        let level = UIDevice.current.batteryLevel
        shared.set(readings: readings, snapshot: snapshot,
                   uploaderBattery: level >= 0 ? Int((level * 100).rounded()) : nil)
    }

    private func save() {
        let p = Persisted(readings: readings, snapshot: snapshot, lastDataAt: lastDataAt)
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

    func set(readings: [GlucoseReading], snapshot: PumpSnapshot, uploaderBattery: Int?) {
        lock.lock(); defer { lock.unlock() }
        _readings = readings
        _snapshot = snapshot
        _uploaderBattery = uploaderBattery
    }

    func get() -> (readings: [GlucoseReading], snapshot: PumpSnapshot, uploaderBattery: Int?) {
        lock.lock(); defer { lock.unlock() }
        return (_readings, _snapshot, _uploaderBattery)
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
