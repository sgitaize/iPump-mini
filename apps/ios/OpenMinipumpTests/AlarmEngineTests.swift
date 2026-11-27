// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
import MiniMedKit
@testable import OpenMinipump

@MainActor
final class AlarmEngineTests: XCTestCase {
    private var engine: AlarmEngine!
    private let now = Date()

    private static let keys = ["alarmConfig", "alarmMutedUntil", "alarmSnoozes", "alarmLastFired", "alarmSeenPump", "alarmSensorState"]

    override func setUp() async throws {
        for k in Self.keys { UserDefaults.standard.removeObject(forKey: k) }
        UserDefaults.standard.set(false, forKey: DemoMode.key)
        engine = AlarmEngine()
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(false, forKey: DemoMode.key)
        for k in Self.keys { UserDefaults.standard.removeObject(forKey: k) }
    }

    /// Reading measured `ageMinutes` before the evaluation time `at` (minutes after `now`).
    private func r(_ mgdl: Int, trend: Double? = 0, ageMinutes: Double = 1, at: Double = 0) -> GlucoseReading {
        GlucoseReading(date: now.addingTimeInterval((at - ageMinutes) * 60), mgdl: mgdl, trendMgdlPerMin: trend, sessionOffsetMinutes: nil)
    }
    private func t(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }

    func testInRangeFiresNothing() {
        engine.evaluate(r(120), now: now)
        XCTAssertTrue(engine.lastFired.isEmpty)
    }

    func testThresholdsOfStandardPreset() {
        engine.evaluate(r(55), now: now)
        XCTAssertEqual(Set(engine.lastFired.keys), ["urgentLow"], "55 is urgent low and not additionally low")
        engine.evaluate(r(56, at: 60), now: t(60))
        XCTAssertNotNil(engine.lastFired["low"])
        engine.evaluate(r(70, at: 120), now: t(120))
        XCTAssertNotNil(engine.lastFired["low"], "70 is still low")
    }

    func testHighAndBoundaries() {
        engine.evaluate(r(249), now: now); XCTAssertNil(engine.lastFired["high"])
        engine.evaluate(r(250), now: now); XCTAssertNotNil(engine.lastFired["high"])
        engine.evaluate(r(71), now: now);  XCTAssertNil(engine.lastFired["low"])
    }

    func testRecoveryClearsTheAlarm() {
        engine.evaluate(r(60), now: now)
        XCTAssertNotNil(engine.lastFired["low"])
        engine.evaluate(r(110), now: now.addingTimeInterval(300))
        XCTAssertNil(engine.lastFired["low"], "back in range must re-arm the alarm")
    }

    func testStaleReadingIsIgnored() {
        engine.evaluate(r(40, ageMinutes: 11), now: now)
        XCTAssertTrue(engine.lastFired.isEmpty)
    }

    func testRepeatInterval() {
        engine.evaluate(r(60), now: now)
        let first = engine.lastFired["low"]
        engine.evaluate(r(60, at: 5), now: t(5))
        XCTAssertEqual(engine.lastFired["low"], first, "no repeat within 15 min")
        engine.evaluate(r(60, at: 15), now: t(15))
        XCTAssertGreaterThan(engine.lastFired["low"]!, first!)
    }

    func testSnoozeSuppressesAndExpires() {
        engine.snooze(key: "high", minutes: 30)
        engine.evaluate(r(300), now: now)
        XCTAssertNil(engine.lastFired["high"])
        engine.evaluate(r(300, at: 31), now: t(31))
        XCTAssertNotNil(engine.lastFired["high"])
    }

    func testGlobalMuteSilencesAllButUrgentLow() {
        engine.muteAll(minutes: 60)
        engine.evaluate(r(300), now: now); XCTAssertNil(engine.lastFired["high"])
        engine.evaluate(r(60), now: now);  XCTAssertNil(engine.lastFired["low"])
        engine.evaluate(r(45), now: now);  XCTAssertNotNil(engine.lastFired["urgentLow"])
        engine.muteAll(minutes: nil)
        XCTAssertNil(engine.mutedUntil)
    }

    func testRateAlarmsOnlyInAllPreset() {
        engine.evaluate(r(120, trend: -2.5), now: now); XCTAssertNil(engine.lastFired["fallingFast"])
        engine.applyPreset(.all)
        engine.evaluate(r(120, trend: -2.0), now: now); XCTAssertNotNil(engine.lastFired["fallingFast"])
        engine.evaluate(r(120, trend: 2.0), now: now);  XCTAssertNotNil(engine.lastFired["risingFast"])
        engine.evaluate(r(120, trend: 1.9), now: now);  XCTAssertNil(engine.lastFired["risingFast"])
        engine.evaluate(r(120, trend: nil), now: now);  XCTAssertNil(engine.lastFired["fallingFast"])
    }

    func testDemoModeNeverAlarms() {
        UserDefaults.standard.set(true, forKey: DemoMode.key)
        engine.evaluate(r(40), now: now)
        XCTAssertTrue(engine.lastFired.isEmpty)
    }

    func testUrgentOnlyPreset() {
        engine.applyPreset(.urgentOnly)
        engine.evaluate(r(65), now: now);  XCTAssertNil(engine.lastFired["low"])
        engine.evaluate(r(300), now: now); XCTAssertNil(engine.lastFired["high"])
        engine.evaluate(r(50), now: now);  XCTAssertNotNil(engine.lastFired["urgentLow"])
    }

    // MARK: Pump alarms

    func testPumpAlarmFiresOnceForPendingRecentEntry() {
        engine.pumpAlarm(id: 7, type: 0x0007, status: 0x33, date: now.addingTimeInterval(-60), now: now)
        XCTAssertNotNil(engine.lastFired["pump.7"], "delivery category is on in the standard preset")
        let first = engine.lastFired["pump.7"]
        engine.pumpAlarm(id: 7, type: 0x0007, status: 0x33, date: now.addingTimeInterval(-60), now: now.addingTimeInterval(600))
        XCTAssertEqual(engine.lastFired["pump.7"], first, "the same history entry must not alarm twice")
    }

    func testPumpAlarmIgnoresOldConfirmedAndDisabledCategories() {
        engine.pumpAlarm(id: 1, type: 0x0007, status: 0x33, date: now.addingTimeInterval(-31 * 60), now: now)
        engine.pumpAlarm(id: 2, type: 0x0007, status: 0x55, date: now.addingTimeInterval(-60), now: now)
        engine.pumpAlarm(id: 3, type: 0x0067, status: 0x33, date: now.addingTimeInterval(-60), now: now)   // reminders: off
        XCTAssertTrue(engine.lastFired.isEmpty)
    }

    // MARK: Config plausibility

    func testPresetsAreConsistent() {
        for p in AlarmConfig.Preset.allCases {
            let c = AlarmConfig.preset(p)
            XCTAssertEqual(Set(c.glucose.keys), Set(GlucoseAlarmKind.allCases))
            XCTAssertEqual(Set(c.pump.keys), Set(PumpAlarmCategory.allCases))
            let low = c.glucose[.low]!.threshold, urgent = c.glucose[.urgentLow]!.threshold, high = c.glucose[.high]!.threshold
            XCTAssertLessThan(urgent, low, "\(p)")
            XCTAssertLessThan(low, high, "\(p)")
            XCTAssertTrue((40...400).contains(urgent) && (40...400).contains(high))
            XCTAssertTrue(c.glucose.values.allSatisfy { $0.snoozeMinutes > 0 && $0.repeatMinutes >= 0 })
            XCTAssertGreaterThan(c.noDataMinutes, 0)
            XCTAssertTrue(c.glucose[.urgentLow]!.enabled, "urgent low is always on")
        }
    }

    func testConfigSurvivesRestart() {
        engine.applyPreset(.all)
        XCTAssertEqual(AlarmEngine().config, AlarmConfig.preset(.all))
    }

    func testSensorTexts() {
        let ok: PumpStatus = Fixtures.decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":100,"reservoirAttached":true,"sensorConnectivity":1,"sensorMessageState":0}"#)
        XCTAssertTrue(ok.sensorOK)
        XCTAssertEqual(AlarmEngine.sensorText(ok), "Sensor ok")
        let lost: PumpStatus = Fixtures.decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":100,"reservoirAttached":true,"sensorConnectivity":5,"sensorMessageState":0}"#)
        XCTAssertEqual(AlarmEngine.sensorText(lost), "Sensorsignal verloren")
        let none: PumpStatus = Fixtures.decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":100,"reservoirAttached":true,"sensorConnectivity":0,"sensorMessageState":14}"#)
        XCTAssertEqual(AlarmEngine.sensorText(none), "Kein Sensor aktiv")
    }

    func testSensorStatusFiresOnChangeIntoProblemOnly() {
        let bad: PumpStatus = Fixtures.decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":100,"reservoirAttached":true,"sensorConnectivity":1,"sensorMessageState":7}"#)
        engine.sensorStatus(bad, now: now)
        XCTAssertNotNil(engine.lastFired["sensor"])
        let first = engine.lastFired["sensor"]
        engine.sensorStatus(bad, now: now.addingTimeInterval(900))
        XCTAssertEqual(engine.lastFired["sensor"], first, "unchanged state does not notify again")
        let ok: PumpStatus = Fixtures.decode(#"{"therapyControlState":85,"operationalState":150,"reservoirUnits":100,"reservoirAttached":true,"sensorConnectivity":1,"sensorMessageState":0}"#)
        engine.sensorStatus(ok, now: now.addingTimeInterval(1200))
        XCTAssertNil(engine.lastFired["sensor"])
    }
}
