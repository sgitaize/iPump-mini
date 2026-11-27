// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import MiniMedKit
@testable import OpenMinipump

@MainActor
final class DataStoreTests: XCTestCase {
    private var file: URL!
    private var store: DataStore!

    override func setUp() async throws {
        file = Fixtures.tempFile()
        store = DataStore(fileURL: file)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: file)
    }

    func testAddKeepsReadingsSortedAndFiresNewReadingOnce() {
        var fired = 0
        store.onNewReading = { fired += 1 }
        store.add(Fixtures.reading(120, minutesAgo: 10, offset: 1))
        store.add(Fixtures.reading(110, minutesAgo: 20, offset: 2))
        store.add(Fixtures.reading(130, minutesAgo: 0, offset: 3))
        XCTAssertEqual(store.readings.map(\.mgdl), [110, 120, 130])
        XCTAssertEqual(store.latest?.mgdl, 130)
        XCTAssertEqual(fired, 3)
    }

    func testDuplicateBySessionOffsetReplacesAndDoesNotFireNewReading() {
        var fired = 0, latestChanged = 0
        store.onNewReading = { fired += 1 }
        store.onLatestChanged = { latestChanged += 1 }
        let a = Fixtures.reading(120, minutesAgo: 10, offset: 500)
        store.add(a)
        // Same sensor record, time differs by a few minutes (clock correction): still one value.
        store.add(GlucoseReading(date: a.date.addingTimeInterval(240), mgdl: 125, trendMgdlPerMin: 0.5, sessionOffsetMinutes: 500))
        XCTAssertEqual(store.readings.count, 1)
        XCTAssertEqual(store.readings[0].mgdl, 125)
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(latestChanged, 1)
    }

    func testValuesWithinTwoMinutesCountAsDuplicate() {
        store.add(Fixtures.reading(120, minutesAgo: 10))
        store.add(GlucoseReading(date: store.readings[0].date.addingTimeInterval(100), mgdl: 121, trendMgdlPerMin: 0, sessionOffsetMinutes: nil))
        XCTAssertEqual(store.readings.count, 1)
        store.add(GlucoseReading(date: store.readings[0].date.addingTimeInterval(130), mgdl: 122, trendMgdlPerMin: 0, sessionOffsetMinutes: nil))
        XCTAssertEqual(store.readings.count, 2, "130 s apart is a new value")
    }

    func testReadingsOlderThanRetentionAreDropped() {
        store.add(Fixtures.reading(100, minutesAgo: 8 * 24 * 60))
        XCTAssertTrue(store.readings.isEmpty)
        store.add(Fixtures.reading(100, minutesAgo: 6 * 24 * 60))
        XCTAssertEqual(store.readings.count, 1)
    }

    func testMergeDeduplicatesAndRejectsFutureAndOld() {
        store.add(Fixtures.reading(120, minutesAgo: 30))
        let existing = store.readings[0]
        let incoming = [
            GlucoseReading(date: existing.date.addingTimeInterval(60), mgdl: 121, trendMgdlPerMin: nil, sessionOffsetMinutes: nil), // dup
            Fixtures.reading(130, minutesAgo: 20),
            Fixtures.reading(140, minutesAgo: -60),                 // 1 h in the future
            Fixtures.reading(150, minutesAgo: 8 * 24 * 60),         // too old
            Fixtures.reading(135, minutesAgo: 15),
        ]
        let added = store.merge(incoming)
        XCTAssertEqual(added.map(\.mgdl), [130, 135])
        XCTAssertEqual(store.readings.map(\.mgdl), [120, 130, 135])
        XCTAssertTrue(store.merge(incoming).isEmpty, "second merge adds nothing")
    }

    func testMergeSignalsLatestChangedOnlyWhenNewest() {
        store.add(Fixtures.reading(120, minutesAgo: 5))
        var changed = 0
        store.onLatestChanged = { changed += 1 }
        store.merge([Fixtures.reading(100, minutesAgo: 60)])   // older: latest stays
        XCTAssertEqual(changed, 0)
        store.merge([Fixtures.reading(140, minutesAgo: 0)])    // newer
        XCTAssertEqual(changed, 1)
    }

    /// Known issue: `merge` rejects values more than 5 min in the future, `add` does not.
    /// The live path (PumpLink) filters at the source, so this is only a missing second line of defence.
    func testAddRejectsReadingsFromTheFuture() {
        XCTExpectFailure("DataStore.add has no future-timestamp guard (merge has)")
        store.add(Fixtures.reading(140, minutesAgo: -60))
        XCTAssertTrue(store.readings.isEmpty, "a value one hour in the future must not be stored")
    }

    func testTreatmentsAreDeduplicatedBySequenceAndSorted() {
        let now = Date()
        let a = Treatment(id: 5, date: now.addingTimeInterval(-600), kind: .bolus, value: 2)
        let b = Treatment(id: 4, date: now.addingTimeInterval(-1200), kind: .carbs, value: 30)
        XCTAssertEqual(store.addTreatments([a, b]).count, 2)
        XCTAssertEqual(store.treatments.map(\.id), [4, 5])
        XCTAssertTrue(store.addTreatments([a, b]).isEmpty, "re-reading the history must not duplicate")
        // Same dose at the same second but another sequence is a different event.
        XCTAssertEqual(store.addTreatments([Treatment(id: 6, date: a.date, kind: .bolus, value: 2)]).count, 1)
        store.resetTreatments()
        XCTAssertTrue(store.treatments.isEmpty)
    }

    func testOldTreatmentsAreDropped() {
        store.addTreatments([Treatment(id: 1, date: Date().addingTimeInterval(-9 * 86400), kind: .bolus, value: 1)])
        XCTAssertTrue(store.treatments.isEmpty)
    }

    func testIOBHistoryAppendsOnChangeAndOnTimeout() {
        store.update { $0.iob = Fixtures.iob(2.0) }
        XCTAssertEqual(store.iobHistory.map(\.units), [2.0])
        store.update { $0.iob = Fixtures.iob(2.0) }
        XCTAssertEqual(store.iobHistory.count, 1, "unchanged value within 4 min: no new sample")
        store.update { $0.iob = Fixtures.iob(1.9) }
        XCTAssertEqual(store.iobHistory.map(\.units), [2.0, 1.9])
        XCTAssertGreaterThan(store.snapshot.updatedAt, .distantPast)
        XCTAssertNotNil(store.lastDataAt)
    }

    func testIOBLookupWithinFiveMinutes() {
        store.update { $0.iob = Fixtures.iob(1.5) }
        let at = store.iobHistory[0].date
        XCTAssertEqual(store.iob(at: at.addingTimeInterval(200)), 1.5)
        XCTAssertNil(store.iob(at: at.addingTimeInterval(400)))
        XCTAssertNil(DataStore(fileURL: Fixtures.tempFile()).iob(at: Date()))
    }

    func testPersistenceRoundTrip() {
        store.add(Fixtures.reading(123, minutesAgo: 5, offset: 77))
        store.addTreatments([Treatment(id: 9, date: Date().addingTimeInterval(-300), kind: .carbs, value: 20)])
        store.update { $0.pumpBatteryPercent = 66; $0.iob = Fixtures.iob(1.1) }
        let reloaded = DataStore(fileURL: file)
        XCTAssertEqual(reloaded.readings, store.readings)
        XCTAssertEqual(reloaded.treatments, store.treatments)
        XCTAssertEqual(reloaded.snapshot.pumpBatteryPercent, 66)
        XCTAssertEqual(reloaded.iobHistory, store.iobHistory)
    }

    func testCorruptStoreFileIsIgnored() throws {
        try Data("{ not json".utf8).write(to: file)
        let s = DataStore(fileURL: file)
        XCTAssertTrue(s.readings.isEmpty)
        XCTAssertNil(s.latest)
    }

    func testSharedCopyFollowsStore() {
        store.add(Fixtures.reading(111, minutesAgo: 1))
        XCTAssertEqual(store.shared.get().readings.last?.mgdl, 111)
        store.addTreatments([Treatment(id: 1, date: Date().addingTimeInterval(-60), kind: .bolus, value: 1)])
        XCTAssertEqual(store.shared.treatments.count, 1)
    }
}

final class SharedDataWakeTests: XCTestCase {
    func testNoWakeNoSchedule() {
        XCTAssertNil(SharedData().wakeSchedule())
    }

    func testIntervalIsMedianOfPlausibleGaps() throws {
        let s = SharedData()
        let t = Fixtures.t0
        for offset in [0.0, 300, 600, 960, 1260] { s.recordWake(t.addingTimeInterval(offset)) }
        let w = try XCTUnwrap(s.wakeSchedule(now: t.addingTimeInterval(1270)))
        XCTAssertEqual(w.interval, 300)
        XCTAssertEqual(w.last, t.addingTimeInterval(1260))
        XCTAssertGreaterThan(w.next, t.addingTimeInterval(1270), "next wake is always in the future")
    }

    func testWakesWithinAMinuteAreMergedAndGapsOutsideRangeIgnored() throws {
        let s = SharedData()
        let t = Fixtures.t0
        s.recordWake(t); s.recordWake(t.addingTimeInterval(30))
        XCTAssertEqual(try XCTUnwrap(s.wakeSchedule(now: t)).last, t)
        s.recordWake(t.addingTimeInterval(7200))   // 2 h gap: not a typical interval
        XCTAssertEqual(try XCTUnwrap(s.wakeSchedule(now: t.addingTimeInterval(7200))).interval, 300, "falls back to 5 min")
    }

    func testNextWakeCatchesUpWhenOverdue() throws {
        let s = SharedData()
        s.recordWake(Fixtures.t0)
        let now = Fixtures.t0.addingTimeInterval(3000)
        let w = try XCTUnwrap(s.wakeSchedule(now: now))
        XCTAssertGreaterThanOrEqual(w.next, now)
        XCTAssertLessThanOrEqual(w.next.timeIntervalSince(now), 300)
    }

    func testOnlyLastSevenWakesKept() throws {
        let s = SharedData()
        for i in 0..<20 { s.recordWake(Fixtures.t0.addingTimeInterval(Double(i) * 300)) }
        XCTAssertEqual(try XCTUnwrap(s.wakeSchedule(now: Fixtures.t0)).last, Fixtures.t0.addingTimeInterval(19 * 300))
    }
}
