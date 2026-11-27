// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest
@testable import OpenMinipump

final class GlucoseSpeechTests: XCTestCase {
    override func setUp() { Fixtures.useGerman() }
    override func tearDown() { Prefs.defaults.removeObject(forKey: Prefs.languageKey) }

    private func snapshot(_ mgdl: Int, minutesAgo: Double, rate: Double?, iob: Double? = nil, now: Date) -> WidgetSnapshot {
        WidgetSnapshot(points: [.init(date: now.addingTimeInterval(-minutesAgo * 60), mgdl: mgdl)],
                       trendRate: rate, iob: iob, updatedAt: now)
    }

    func testCurrentValueWithTrendAgeAndIOB() {
        let now = Fixtures.t0
        let text = GlucoseSpeech.sentence(snapshot(142, minutesAgo: 3, rate: -1.4, iob: 1.86, now: now), unit: .mgdl, now: now)
        XCTAssertEqual(text, "142 mg/dL, fallend, vor 3 Minuten. Aktives Insulin 1,9 Einheiten.")
    }

    func testJustNowAndNoIOB() {
        let now = Fixtures.t0
        XCTAssertEqual(GlucoseSpeech.sentence(snapshot(98, minutesAgo: 0.2, rate: 0.1, now: now), unit: .mgdl, now: now),
                       "98 mg/dL, stabil, gerade eben.")
    }

    func testStaleValueIsAnnouncedAsOld() {
        let now = Fixtures.t0
        let text = GlucoseSpeech.sentence(snapshot(180, minutesAgo: 40, rate: 2.5, now: now), unit: .mgdl, now: now)
        XCTAssertTrue(text.hasPrefix("Achtung, kein aktueller Wert."), text)
        XCTAssertTrue(text.contains("vor 40 Minuten"), text)
        XCTAssertFalse(text.contains("steigend"), "no trend for an old value")
    }

    func testMmol() {
        let now = Fixtures.t0
        XCTAssertEqual(GlucoseSpeech.sentence(snapshot(90, minutesAgo: 1, rate: nil, now: now), unit: .mmol, now: now),
                       "5,0 mmol/L, vor einer Minute.")
    }

    func testNoData() {
        XCTAssertTrue(GlucoseSpeech.sentence(nil, unit: .mgdl).contains("Keine Werte"))
    }

    func testTrendWordsMatchArrowThresholds() {
        XCTAssertEqual(GlucoseSpeech.trendWord(2), "stark steigend")
        XCTAssertEqual(GlucoseSpeech.trendWord(1), "steigend")
        XCTAssertEqual(GlucoseSpeech.trendWord(0.99), "stabil")
        XCTAssertEqual(GlucoseSpeech.trendWord(-1), "fallend")
        XCTAssertEqual(GlucoseSpeech.trendWord(-2), "stark fallend")
        XCTAssertNil(GlucoseSpeech.trendWord(nil))
    }
}
