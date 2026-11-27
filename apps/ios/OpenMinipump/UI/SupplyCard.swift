// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Text building for the supply card (separate from the view so it can be tested).
enum SupplyFormat {
    /// "So. 14 Uhr" (hours) or with minutes ("Mi. 10:34") for exact times.
    static func day(_ date: Date, minutes: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.setLocalizedDateFormatFromTemplate(minutes ? "EEEjmm" : "EEEj")
        return f.string(from: date)
    }

    /// "± 3 h" style half width of the range.
    static func margin(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 90 { return L10n.tr("%d min", max(5, (minutes + 2) / 5 * 5)) }
        if minutes < 48 * 60 { return L10n.tr("%d h", Int((Double(minutes) / 60).rounded())) }
        return L10n.tr("%d T", Int((Double(minutes) / 1440).rounded()))
    }

    static func learning(days: Double, needed: Double) -> String {
        L10n.tr("lernt noch (%@ von %d Tagen)", String(format: "%.1f", locale: L10n.locale, days), Int(needed))
    }

    static func confidence(_ c: Double) -> String {
        c >= 0.7 ? L10n.tr("Konfidenz hoch") : c >= 0.4 ? L10n.tr("Konfidenz mittel") : L10n.tr("Konfidenz niedrig")
    }

    /// Main line of a row, e.g. "Reservoir reicht bis ca. So. 14 Uhr (± 3 h)".
    static func line(_ outcome: SupplyOutcome, kind: SupplyKind) -> String {
        switch outcome {
        case .noData: return L10n.tr("Noch keine Werte")
        case let .learning(days, needed): return learning(days: days, needed: needed)
        case let .ready(p):
            guard let e = p.empty else { return L10n.tr("reicht mehr als 30 Tage") }
            if p.current <= 0 { return kind == .reservoir ? L10n.tr("Reservoir ist leer") : L10n.tr("Akku ist leer") }
            let when = day(e.date), range = margin(e.margin)
            return kind == .reservoir ? L10n.tr("reicht bis ca. %@ (± %@)", when, range)
                                      : L10n.tr("hält bis ca. %@ (± %@)", when, range)
        }
    }

    /// Second line: alarm threshold and confidence.
    static func detail(_ outcome: SupplyOutcome, kind: SupplyKind) -> String? {
        guard case let .ready(p) = outcome else { return nil }
        let limit = kind == .reservoir ? insulinUnits(kind.alarmThreshold, 0) : "\(Int(kind.alarmThreshold)) %"
        var parts: [String] = []
        if let a = p.alarm {
            parts.append(a.date <= p.basis ? L10n.tr("Unter %@ erreicht", limit)
                                           : L10n.tr("Unter %@ ca. %@", limit, day(a.date)))
        }
        parts.append(confidence(p.confidence))
        return parts.joined(separator: " · ")
    }
}

/// "Vorrat (Beta)": estimated end of reservoir and pump battery, and the exact sensor end.
struct SupplyCard: View {
    @EnvironmentObject private var store: DataStore

    var body: some View {
        let s = store.snapshot
        let hasReservoir = s.status?.reservoirAttached == true
        let hasBattery = s.pumpBatteryPercent != nil
        if hasReservoir || hasBattery || s.sensorEnd != nil {
            let forecaster = SupplyForecaster()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Vorrat").font(.headline)
                    Text("Beta")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if hasReservoir {
                    row("drop.fill", "Reservoir", forecaster.forecast(kind: .reservoir, samples: store.supplyHistory, now: Date()), .reservoir)
                }
                if hasBattery {
                    row("battery.50", "Pumpenbatterie", forecaster.forecast(kind: .battery, samples: store.supplyHistory, now: Date()), .battery)
                }
                if let end = s.sensorEnd {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "dot.radiowaves.left.and.right").frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sensor").font(.caption).foregroundStyle(.secondary)
                            Text(end > Date() ? L10n.tr("bis %@", SupplyFormat.day(end, minutes: true)) : L10n.tr("abgelaufen"))
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                Text("Schätzung aus deinem bisherigen Verbrauch, keine Garantie. Die Pumpe zeigt den tatsächlichen Stand.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, _ outcome: SupplyOutcome, _ kind: SupplyKind) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(SupplyFormat.line(outcome, kind: kind)).font(.subheadline.weight(.medium))
                if let d = SupplyFormat.detail(outcome, kind: kind) {
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
