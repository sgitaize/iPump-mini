// SPDX-License-Identifier: GPL-3.0-or-later
import HealthKit
import MiniMedKit
import XCTest
@testable import OpenMinipump

final class FakeHealthWriter: HealthWriting {
    var saved: [[HKSample]] = []
    var authFails = false
    var saveFails = false
    func requestAuthorization() async throws { if authFails { throw HealthSync.Failure.denied } }
    func save(_ samples: [HKSample]) async throws {
        if saveFails { throw HealthSync.Failure.unavailable }
        saved.append(samples)
    }
    var count: Int { saved.reduce(0) { $0 + $1.count } }
}

final class HealthSyncTests: XCTestCase {
    let t0 = Fixtures.t0

    func reading(_ mgdl: Int, at d: Date) -> GlucoseReading {
        GlucoseReading(date: d, mgdl: mgdl, trendMgdlPerMin: 0, sessionOffsetMinutes: nil)
    }

    func testGlucoseMapping() throws {
        let s = try XCTUnwrap(HealthMapping.sample(reading(123, at: t0)))
        XCTAssertEqual(s.quantityType, HKQuantityType(.bloodGlucose))
        XCTAssertEqual(s.quantity.doubleValue(for: HealthMapping.glucoseUnit), 123)
        XCTAssertEqual(s.startDate, t0)
        XCTAssertEqual(s.metadata?[HKMetadataKeySyncIdentifier] as? String, "omp-sgv-\(Int(t0.timeIntervalSince1970))")
        XCTAssertEqual(s.metadata?[HKMetadataKeySyncVersion] as? Int, 1)
        // Stable: same input, same identifier.
        XCTAssertEqual(HealthMapping.sample(reading(123, at: t0))?.metadata?[HKMetadataKeySyncIdentifier] as? String,
                       s.metadata?[HKMetadataKeySyncIdentifier] as? String)
    }

    func testBolusAndAutoCorrectionAreBolusDelivery() throws {
        for kind in [Treatment.Kind.bolus, .autoCorrection] {
            let s = try XCTUnwrap(HealthMapping.sample(Treatment(id: 42, date: t0, kind: kind, value: 2.5)))
            XCTAssertEqual(s.quantityType, HKQuantityType(.insulinDelivery))
            XCTAssertEqual(s.quantity.doubleValue(for: HealthMapping.insulinUnit), 2.5)
            XCTAssertEqual(s.metadata?[HKMetadataKeyInsulinDeliveryReason] as? Int, HKInsulinDeliveryReason.bolus.rawValue)
            XCTAssertEqual(s.metadata?[HKMetadataKeySyncIdentifier] as? String, "omp-tr-42")
            XCTAssertEqual(s.metadata?[HKMetadataKeySyncVersion] as? Int, 1)
        }
    }

    func testCarbs() throws {
        let s = try XCTUnwrap(HealthMapping.sample(Treatment(id: 7, date: t0, kind: .carbs, value: 45)))
        XCTAssertEqual(s.quantityType, HKQuantityType(.dietaryCarbohydrates))
        XCTAssertEqual(s.quantity.doubleValue(for: HealthMapping.carbUnit), 45)
        XCTAssertEqual(s.metadata?[HKMetadataKeySyncIdentifier] as? String, "omp-tr-7")
    }

    func testOtherTreatmentsAndEmptyValuesAreSkipped() {
        for kind in [Treatment.Kind.autoBasal, .bgCheck, .calibration, .basalChange, .suspend, .resume] {
            XCTAssertNil(HealthMapping.sample(Treatment(id: 1, date: t0, kind: kind, value: 1)), "\(kind)")
        }
        XCTAssertNil(HealthMapping.sample(Treatment(id: 1, date: t0, kind: .bolus, value: 0)))
        XCTAssertNil(HealthMapping.sample(Treatment(id: 1, date: t0, kind: .bolus, value: nil)))
    }

    func testPendingOnlyNewerThanMarks() {
        let readings = [reading(100, at: t0), reading(110, at: t0.addingTimeInterval(300)), reading(120, at: t0.addingTimeInterval(600))]
        let treatments = [Treatment(id: 1, date: t0, kind: .bolus, value: 1),
                          Treatment(id: 2, date: t0.addingTimeInterval(400), kind: .carbs, value: 30),
                          Treatment(id: 3, date: t0.addingTimeInterval(500), kind: .autoBasal, value: 0.1)]
        let p = HealthMapping.pending(readings: readings, treatments: treatments,
                                      glucoseSince: t0.addingTimeInterval(300), treatmentsSince: t0)
        XCTAssertEqual(p.count, 2)   // reading at +600 and carbs at +400; auto basal is skipped
        XCTAssertEqual(p.map(\.startDate), [t0.addingTimeInterval(400), t0.addingTimeInterval(600)])
        XCTAssertTrue(HealthMapping.pending(readings: readings, treatments: treatments,
                                            glucoseSince: t0.addingTimeInterval(600), treatmentsSince: t0.addingTimeInterval(500)).isEmpty)
    }

    func testThrottle() {
        XCTAssertTrue(HealthMapping.isDue(last: nil, now: t0))
        XCTAssertFalse(HealthMapping.isDue(last: t0, now: t0.addingTimeInterval(299)))
        XCTAssertTrue(HealthMapping.isDue(last: t0, now: t0.addingTimeInterval(300)))
    }

    // MARK: HealthSync with a fake writer

    @MainActor
    func makeSync(writer: FakeHealthWriter, demo: Bool = false, clock: @escaping () -> Date) -> (HealthSync, DataStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "health-test-\(UUID().uuidString)")!
        let store = DataStore(fileURL: Fixtures.tempFile())
        let sync = HealthSync(store: store, log: EventLog(), writer: writer, defaults: defaults, isDemo: { demo }, now: clock)
        return (sync, store, defaults)
    }

    @MainActor
    func testEnableBackfillsAndThenOnlyNew() async {
        let now = Date()
        var clock = now
        let writer = FakeHealthWriter()
        let (sync, store, _) = makeSync(writer: writer, clock: { clock })
        _ = store.add(reading(120, at: now.addingTimeInterval(-3600)))
        await sync.setEnabled(true)
        XCTAssertTrue(sync.enabled)
        XCTAssertEqual(writer.count, 1)
        // Nothing new: nothing written, even after the throttle.
        clock = now.addingTimeInterval(400)
        await sync.sync()
        XCTAssertEqual(writer.count, 1)
        _ = store.add(reading(130, at: now.addingTimeInterval(-60)))
        await sync.sync()
        XCTAssertEqual(writer.count, 2)
        XCTAssertEqual(sync.lastCount, 1)
    }

    @MainActor
    func testThrottleInSync() async {
        let now = Date()
        var clock = now
        let writer = FakeHealthWriter()
        let (sync, store, _) = makeSync(writer: writer, clock: { clock })
        _ = store.add(reading(120, at: now.addingTimeInterval(-600)))
        await sync.setEnabled(true)
        _ = store.add(reading(130, at: now.addingTimeInterval(-30)))
        clock = now.addingTimeInterval(120)
        await sync.sync()
        XCTAssertEqual(writer.count, 1, "within 5 minutes nothing is written")
        clock = now.addingTimeInterval(301)
        await sync.sync()
        XCTAssertEqual(writer.count, 2)
    }

    @MainActor
    func testDemoModeNeverWrites() async {
        let writer = FakeHealthWriter()
        let (sync, store, _) = makeSync(writer: writer, demo: true, clock: Date.init)
        _ = store.add(reading(120, at: Date().addingTimeInterval(-60)))
        await sync.setEnabled(true)
        await sync.sync(force: true)
        sync.dataChanged()
        XCTAssertEqual(writer.count, 0)
    }

    @MainActor
    func testDeniedPermissionStaysOffWithoutCrash() async {
        let writer = FakeHealthWriter()
        writer.authFails = true
        let (sync, store, _) = makeSync(writer: writer, clock: Date.init)
        _ = store.add(reading(120, at: Date().addingTimeInterval(-60)))
        await sync.setEnabled(true)
        XCTAssertFalse(sync.enabled)
        XCTAssertNotNil(sync.lastError)
        XCTAssertEqual(writer.count, 0)
    }

    @MainActor
    func testSaveErrorKeepsMarkSoItRetries() async {
        let now = Date()
        var clock = now
        let writer = FakeHealthWriter()
        let (sync, store, _) = makeSync(writer: writer, clock: { clock })
        _ = store.add(reading(120, at: now.addingTimeInterval(-60)))
        await sync.setEnabled(true)   // writes once
        _ = store.add(reading(130, at: now.addingTimeInterval(-30)))
        writer.saveFails = true
        clock = now.addingTimeInterval(400)
        await sync.sync()
        XCTAssertNotNil(sync.lastError)
        writer.saveFails = false
        await sync.sync()
        XCTAssertEqual(writer.count, 2)
    }
}
