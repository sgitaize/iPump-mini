// SPDX-License-Identifier: GPL-3.0-or-later
// Optional: writes glucose, insulin and carbs to Apple Health (write only, off by default).
//
// Reads nothing from Health. Every sample carries a stable sync identifier, so HealthKit
// deduplicates by itself when a value is written again. Demo mode never writes.
// Basal: SmartGuard micro boluses (`autoBasal`) are not written. The history gives only a
// delivered amount per record, no reliable interval, and Health would show wrong basal rates.
import Foundation
import HealthKit
import MiniMedKit

/// Pure mapping from app data to HealthKit samples (no store needed, easy to test).
enum HealthMapping {
    static let glucoseUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    static let insulinUnit = HKUnit.internationalUnit()
    static let carbUnit = HKUnit.gram()

    static func glucoseSyncID(_ r: GlucoseReading) -> String { "omp-sgv-\(Int(r.date.timeIntervalSince1970))" }
    static func treatmentSyncID(_ t: Treatment) -> String { "omp-tr-\(t.id)" }

    private static func metadata(_ id: String, extra: [String: Any] = [:]) -> [String: Any] {
        var m = extra
        m[HKMetadataKeySyncIdentifier] = id
        m[HKMetadataKeySyncVersion] = 1
        return m
    }

    static func sample(_ r: GlucoseReading) -> HKQuantitySample? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose), r.mgdl > 0 else { return nil }
        return HKQuantitySample(type: type, quantity: HKQuantity(unit: glucoseUnit, doubleValue: Double(r.mgdl)),
                                start: r.date, end: r.date, metadata: metadata(glucoseSyncID(r)))
    }

    /// Bolus and SmartGuard auto corrections become insulin delivery (reason bolus), carbs
    /// dietary carbohydrates. Everything else (auto basal, BG checks, …) is skipped.
    static func sample(_ t: Treatment) -> HKQuantitySample? {
        guard let value = t.value, value > 0 else { return nil }
        switch t.kind {
        case .bolus, .autoCorrection:
            guard let type = HKQuantityType.quantityType(forIdentifier: .insulinDelivery) else { return nil }
            let meta = metadata(treatmentSyncID(t), extra: [
                HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.bolus.rawValue,
            ])
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: insulinUnit, doubleValue: value),
                                    start: t.date, end: t.date, metadata: meta)
        case .carbs:
            guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: carbUnit, doubleValue: value),
                                    start: t.date, end: t.date, metadata: metadata(treatmentSyncID(t)))
        default:
            return nil
        }
    }

    /// Everything newer than the written-up-to marks, as samples (oldest first).
    static func pending(readings: [GlucoseReading], treatments: [Treatment],
                        glucoseSince: Date, treatmentsSince: Date) -> [HKQuantitySample] {
        let g = readings.filter { $0.date > glucoseSince }.compactMap(sample)
        let t = treatments.filter { $0.date > treatmentsSince }.compactMap(sample)
        return (g + t).sorted { $0.startDate < $1.startDate }
    }

    /// Throttle: at most one write every `minInterval` seconds.
    static func isDue(last: Date?, now: Date, minInterval: TimeInterval = 300) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }
}

/// What `HealthSync` needs from HealthKit. Tests replace it.
protocol HealthWriting {
    func requestAuthorization() async throws
    func save(_ samples: [HKSample]) async throws
}

struct HealthStoreWriter: HealthWriting {
    private let store = HKHealthStore()
    private static var shareTypes: Set<HKSampleType> {
        Set([HKQuantityTypeIdentifier.bloodGlucose, .insulinDelivery, .dietaryCarbohydrates]
            .compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSync.Failure.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: [])
        // Status for writing is readable (unlike reading): .sharingDenied = user said no.
        let denied = Self.shareTypes.allSatisfy { store.authorizationStatus(for: $0) == .sharingDenied }
        if denied { throw HealthSync.Failure.denied }
    }

    func save(_ samples: [HKSample]) async throws {
        try await store.save(samples)
    }
}

@MainActor
final class HealthSync: ObservableObject {
    enum Failure: Error { case unavailable, denied }

    static let backfill: TimeInterval = 14 * 24 * 3600
    static let minInterval: TimeInterval = 300

    @Published private(set) var enabled: Bool
    @Published private(set) var lastWrite: Date?
    @Published private(set) var lastCount = 0
    @Published private(set) var lastError: String?

    private let store: DataStore
    private let log: EventLog
    private let writer: HealthWriting
    private let defaults: UserDefaults
    private let isDemo: () -> Bool
    private let now: () -> Date
    private var running = false
    private var scheduled: Task<Void, Never>?

    // Marks are stored as Date: a Double round trip via 1970 could put the mark a hair before
    // the last written value, which was then written again.
    private var glucoseMark: Date {
        get { (defaults.object(forKey: "healthGlucoseMark") as? Date) ?? .distantPast }
        set { defaults.set(newValue, forKey: "healthGlucoseMark") }
    }
    private var treatmentMark: Date {
        get { (defaults.object(forKey: "healthTreatmentMark") as? Date) ?? .distantPast }
        set { defaults.set(newValue, forKey: "healthTreatmentMark") }
    }

    init(store: DataStore, log: EventLog, writer: HealthWriting = HealthStoreWriter(),
         defaults: UserDefaults = .standard, isDemo: @escaping () -> Bool = { DemoMode.isOn },
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.log = log
        self.writer = writer
        self.defaults = defaults
        self.isDemo = isDemo
        self.now = now
        enabled = defaults.bool(forKey: "healthEnabled")
        let t = defaults.double(forKey: "healthLastWrite")
        lastWrite = t > 0 ? Date(timeIntervalSince1970: t) : nil
        lastCount = defaults.integer(forKey: "healthLastCount")
    }

    /// Switch from the settings. On: ask for permission, then backfill the last 14 days.
    func setEnabled(_ on: Bool) async {
        scheduled?.cancel()
        guard on else {
            enabled = false
            defaults.set(false, forKey: "healthEnabled")
            return
        }
        do {
            try await writer.requestAuthorization()
        } catch {
            fail("Berechtigung: \(error)")
            enabled = false
            defaults.set(false, forKey: "healthEnabled")
            return
        }
        lastError = nil
        enabled = true
        defaults.set(true, forKey: "healthEnabled")
        let since = now().addingTimeInterval(-Self.backfill)
        glucoseMark = since
        treatmentMark = since
        await sync(force: true)
    }

    /// New value or history arrived. Writes batched, at most every 5 minutes; a write that
    /// is too early is postponed to the end of the interval.
    func dataChanged() {
        guard enabled, !isDemo() else { return }
        if HealthMapping.isDue(last: lastWrite, now: now(), minInterval: Self.minInterval) {
            Task { [weak self] in await self?.sync() }
        } else if scheduled == nil, let last = lastWrite {
            let wait = max(1, Self.minInterval - now().timeIntervalSince(last))
            scheduled = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.scheduled = nil
                await self?.sync()
            }
        }
    }

    /// Pump history can add values older than the newest one: look back a bit again
    /// (HealthKit drops what is already there via the sync identifier).
    func historyAdded(oldestReading: Date?) {
        if let oldest = oldestReading, oldest <= glucoseMark { glucoseMark = oldest.addingTimeInterval(-1) }
        let back = now().addingTimeInterval(-6 * 3600)
        if treatmentMark > back { treatmentMark = back }
        dataChanged()
    }

    func sync(force: Bool = false) async {
        guard enabled, !running, !isDemo() else { return }
        guard force || HealthMapping.isDue(last: lastWrite, now: now(), minInterval: Self.minInterval) else { return }
        running = true
        defer { running = false }
        let readings = store.readings, treatments = store.treatments
        let samples = HealthMapping.pending(readings: readings, treatments: treatments,
                                            glucoseSince: glucoseMark, treatmentsSince: treatmentMark)
        guard !samples.isEmpty else { return }
        do {
            try await writer.save(samples)
        } catch {
            fail("Schreiben: \(error)")
            return
        }
        if let g = readings.map(\.date).max() { glucoseMark = max(glucoseMark, g) }
        if let t = treatments.filter({ HealthMapping.sample($0) != nil }).map(\.date).max() { treatmentMark = max(treatmentMark, t) }
        lastWrite = now()
        lastCount = samples.count
        lastError = nil
        defaults.set(lastWrite?.timeIntervalSince1970 ?? 0, forKey: "healthLastWrite")
        defaults.set(lastCount, forKey: "healthLastCount")
        log.add("Apple Health: \(samples.count) Probe(n) geschrieben")
    }

    private func fail(_ text: String) {
        lastError = text
        log.add("Apple Health: \(text)", .warning)
    }
}
