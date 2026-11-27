// SPDX-License-Identifier: GPL-3.0-or-later
// Siri / Shortcuts: "Wie ist mein Zucker in iPump-mini?" – also hands-free in the car (CarPlay).
// Reads the snapshot the app shares with its widgets, so it answers without waking Bluetooth.
import AppIntents
import Foundation

struct CurrentGlucoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Aktueller Zuckerwert"
    static let description = IntentDescription("Sagt den aktuellen Glukosewert mit Trend, Alter und aktivem Insulin.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let snapshot = SharedStore.read()
        let text = GlucoseSpeech.sentence(snapshot, unit: Prefs.unit)
        return .result(value: snapshot?.latest?.mgdl ?? 0, dialog: IntentDialog(stringLiteral: text))
    }
}

struct GlucoseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CurrentGlucoseIntent(),
            phrases: [
                "Wie ist mein Zucker in \(.applicationName)",
                "Zuckerwert in \(.applicationName)",
                "\(.applicationName) Zuckerwert",
                "Wie ist mein Wert in \(.applicationName)",
            ],
            shortTitle: "Zuckerwert",
            systemImageName: "drop.fill"
        )
    }
}

/// The spoken answer. Kept short for the car: value, unit, trend word, age; IOB if known.
/// An old value is said as such first, so it is never taken for a current one.
enum GlucoseSpeech {
    static let staleAfter: TimeInterval = 15 * 60

    static func sentence(_ snapshot: WidgetSnapshot?, unit: GlucoseUnit, now: Date = Date()) -> String {
        guard let snapshot, let latest = snapshot.latest else {
            return L10n.tr("Keine Werte vorhanden. Ist iPump-mini mit der Pumpe verbunden?")
        }
        let minutes = max(0, Int(now.timeIntervalSince(latest.date) / 60))
        let value = "\(unit.format(latest.mgdl)) \(unit.label)"
        var parts: [String] = []
        if now.timeIntervalSince(latest.date) > staleAfter {
            parts.append(L10n.tr("Achtung, kein aktueller Wert. Der letzte war %@ vor %d Minuten.", value, minutes))
        } else {
            let age = minutes == 0 ? L10n.tr("gerade eben") : minutes == 1 ? L10n.tr("vor einer Minute") : L10n.tr("vor %d Minuten", minutes)
            if let trend = trendWord(snapshot.trendRate) {
                parts.append(L10n.tr("%@, %@, %@.", value, trend, age))
            } else {
                parts.append(L10n.tr("%@, %@.", value, age))
            }
        }
        if let iob = snapshot.iob, iob >= 0.05 {
            parts.append(L10n.tr("Aktives Insulin %@ Einheiten.", String(format: "%.1f", locale: L10n.locale, iob)))
        }
        return parts.joined(separator: " ")
    }

    /// Same thresholds as the arrows and Nightscout directions (±1 and ±2 mg/dL/min).
    static func trendWord(_ rate: Double?) -> String? {
        guard let rate else { return nil }
        if rate >= 2 { return L10n.tr("stark steigend") }
        if rate >= 1 { return L10n.tr("steigend") }
        if rate > -1 { return L10n.tr("stabil") }
        if rate > -2 { return L10n.tr("fallend") }
        return L10n.tr("stark fallend")
    }
}
