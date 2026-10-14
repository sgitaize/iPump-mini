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
        }
        let cutoff = Date().addingTimeInterval(-retention)
        readings.removeAll { $0.date < cutoff }
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

    func add(_ text: String, _ level: Level = .info) {
        entries.append(Entry(level: level, text: text))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        print("[omp] \(text)")
    }

    var exportText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "\(f.string(from: $0.date)) [\($0.level)] \($0.text)" }.joined(separator: "\n")
    }
}
