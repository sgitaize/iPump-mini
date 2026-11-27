// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// "Muster": up to three neutral observations from the last 14 days. Hidden without findings.
struct PatternCard: View {
    @EnvironmentObject private var store: DataStore
    @AppStorage(Prefs.unitKey, store: Prefs.defaults) private var unitRaw = GlucoseUnit.mgdl.rawValue
    @AppStorage(Prefs.lowKey, store: Prefs.defaults) private var low = 70
    @AppStorage(Prefs.highKey, store: Prefs.defaults) private var high = 180

    var body: some View {
        let finder = PatternFinder(low: low, high: high)
        let hints = finder.hints(readings: store.readings, treatments: store.treatments, now: Date())
        let unit = GlucoseUnit(rawValue: unitRaw) ?? .mgdl
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Muster").font(.headline)
                ForEach(hints) { hint in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: hint.kind == .low ? "arrow.down.circle.fill"
                              : hint.kind == .high ? "arrow.up.circle.fill" : "chart.bar.fill")
                            .foregroundStyle(hint.kind == .low ? .red : hint.kind == .high ? .orange : .secondary)
                            .frame(width: 22)
                        Text(hint.message(unit: unit)).font(.subheadline)
                    }
                }
                Text("Statistik der letzten 14 Tage, keine Therapieempfehlung.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
