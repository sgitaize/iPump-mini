// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import MiniMedKit
@testable import OpenMinipump

enum Fixtures {
    /// Fixed reference time so that expectations do not depend on the clock.
    static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    static func reading(_ mgdl: Int, minutesAgo: Double, trend: Double? = 0, offset: UInt16? = nil, now: Date = Date()) -> GlucoseReading {
        GlucoseReading(date: now.addingTimeInterval(-minutesAgo * 60), mgdl: mgdl, trendMgdlPerMin: trend, sessionOffsetMinutes: offset)
    }

    static func decode<T: Decodable>(_ json: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func iob(_ units: Double) -> InsulinOnBoard { decode(#"{"units":\#(units),"remainingDurationMinutes":120}"#) }

    static func tempFile(_ name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("omp-test-\(name).json")
    }

    /// German, mg/dL, for deterministic number formats.
    static func useGerman() {
        Prefs.defaults.set("de", forKey: Prefs.languageKey)
    }
}
