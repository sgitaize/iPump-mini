// SPDX-License-Identifier: GPL-3.0-or-later
import MiniMedKit
import SwiftUI
import UIKit

struct AlarmSettingsView: View {
    @ObservedObject private var engine = AlarmEngine.shared

    var body: some View {
        Form {
            Section {
                ForEach(AlarmConfig.Preset.allCases) { preset in
                    Button {
                        engine.applyPreset(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(verbatim: preset.title).foregroundStyle(.primary)
                                Spacer()
                                if engine.config == AlarmConfig.preset(preset) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Voreinstellung")
            } footer: {
                Text("Danach lässt sich jeder Alarm einzeln anpassen.")
            }

            Section {
                if let until = engine.mutedUntil, until > Date() {
                    LabeledContent("Stumm bis", value: until.formatted(date: .omitted, time: .shortened))
                    Button("Stummschaltung aufheben") { engine.muteAll(minutes: nil) }
                } else {
                    Button("1 Stunde stumm") { engine.muteAll(minutes: 60) }
                    Button("2 Stunden stumm") { engine.muteAll(minutes: 120) }
                }
            } header: {
                Text("Alle Alarme stummschalten")
            } footer: {
                Text("Gilt nicht für „Dringend niedrig“. Einzelne Alarme lassen sich direkt in der Mitteilung für 15, 30 oder 60 Minuten stummschalten.")
            }

            Section("Glukose") {
                ForEach(GlucoseAlarmKind.allCases) { kind in
                    GlucoseRuleEditor(kind: kind, rule: binding(for: kind))
                }
            }

            Section {
                Toggle("Keine Daten", isOn: $engine.config.noDataEnabled)
                if engine.config.noDataEnabled {
                    Stepper(L10n.tr("nach %d min", engine.config.noDataMinutes), value: $engine.config.noDataMinutes, in: 10...60, step: 5)
                }
            } footer: {
                Text("Meldet sich, wenn so lange keine Pumpendaten kamen – auch wenn die App weggewischt wurde.")
            }

            Section {
                ForEach(PumpAlarmCategory.allCases) { category in
                    Toggle(L10n.tr(category.title), isOn: Binding(
                        get: { engine.config.pump[category] ?? false },
                        set: { engine.config.pump[category] = $0 }
                    ))
                }
            } header: {
                Text("Meldungen der Pumpe")
            } footer: {
                Text("Die App gibt Alarme und Hinweise der Pumpe weiter, sobald die Pumpe sie meldet. Quittieren musst du sie weiterhin an der Pumpe.")
            }

            Section {
                Button("Test-Alarm senden") { engine.sendTest() }
                StatusRow(title: "Mitteilungen", ok: engine.notificationsAllowed)
                StatusRow(title: "Zeitkritische Mitteilungen", ok: engine.timeSensitiveAvailable)
                Button("iPhone-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            } header: {
                Text("Zustellung")
            } footer: {
                Text("Dringende Alarme („Dringend niedrig“, dringende Pumpenmeldungen) kommen als zeitkritische Mitteilung. Sie erscheinen sofort, bleiben länger auf dem Sperrbildschirm und kommen auch durch einen Fokus wie „Schlafen“, wenn du das erlaubst. Den Stummschalter durchbrechen sie nicht.")
            }

            Section("So richtest du es ein") {
                GuideItem(icon: "bell.badge", title: "1. Mitteilungen erlauben",
                          text: "iPhone-Einstellungen › Mitteilungen › iPump-mini: „Mitteilungen erlauben“, „Töne“ und „Zeitkritische Mitteilungen“ einschalten.")
                GuideItem(icon: "moon", title: "2. Fokus und Schlafen",
                          text: "Einstellungen › Fokus › z. B. „Schlafen“ › Apps: entweder iPump-mini zu den erlaubten Apps hinzufügen oder „Zeitkritische Mitteilungen“ für den Fokus erlauben. Für jeden Fokus, den du nutzt, wiederholen.")
                GuideItem(icon: "speaker.wave.2", title: "3. Ton und Stummschalter",
                          text: "Zeitkritische Mitteilungen folgen dem Stummschalter. Nachts das iPhone nicht stumm schalten, Lautstärke für Klingelton und Hinweise ausreichend hoch einstellen.")
                GuideItem(icon: "checkmark.circle", title: "4. Testen",
                          text: "„Test-Alarm senden“ antippen, iPhone sperren und prüfen, ob der Alarm mit Ton erscheint – am besten auch mit aktivem Fokus.")
            }
        }
        .onAppear { engine.refreshSettings() }
        .navigationTitle("Alarme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for kind: GlucoseAlarmKind) -> Binding<AlarmRule> {
        Binding(
            get: { engine.config.glucose[kind] ?? AlarmConfig.preset(.standard).glucose[kind]! },
            set: { engine.config.glucose[kind] = $0 }
        )
    }
}

private struct GlucoseRuleEditor: View {
    let kind: GlucoseAlarmKind
    @Binding var rule: AlarmRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(kind.title, isOn: $rule.enabled)
            if rule.enabled {
                if kind.isRate {
                    Stepper(L10n.tr("ab %@ mg/dL pro Minute", String(format: "%.1f", rule.threshold)), value: $rule.threshold, in: 1...4, step: 0.5)
                } else {
                    Stepper(thresholdText, value: $rule.threshold, in: range, step: 5)
                }
                Picker("Erneut alarmieren", selection: $rule.repeatMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("alle \($0) min").tag($0) }
                }
            }
        }
        .font(.subheadline)
    }

    private var range: ClosedRange<Double> {
        switch kind {
        case .urgentLow: 40...60
        case .low: 60...100
        default: 150...350
        }
    }

    private var thresholdText: String {
        let mmol = String(format: "%.1f", rule.threshold / 18.0182)
        return kind == .high ? L10n.tr("ab %d mg/dL (%@ mmol/L)", Int(rule.threshold), mmol)
                             : L10n.tr("unter %d mg/dL (%@ mmol/L)", Int(rule.threshold), mmol)
    }
}

/// Green check or orange warning for a delivery prerequisite.
private struct StatusRow: View {
    let title: LocalizedStringKey
    let ok: Bool

    var body: some View {
        LabeledContent {
            Label(ok ? "an" : "aus", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
        } label: {
            Text(title)
        }
    }
}
