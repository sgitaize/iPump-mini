// SPDX-License-Identifier: GPL-3.0-or-later
import MiniMedKit
import SwiftUI

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
                                Text(preset.title).foregroundStyle(.primary)
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
                    Stepper("nach \(engine.config.noDataMinutes) min", value: $engine.config.noDataMinutes, in: 10...60, step: 5)
                }
            } footer: {
                Text("Meldet sich, wenn so lange keine Pumpendaten kamen – auch wenn die App weggewischt wurde.")
            }

            Section {
                ForEach(PumpAlarmCategory.allCases) { category in
                    Toggle(category.title, isOn: Binding(
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
                LabeledContent("Kritische Alarme", value: engine.criticalAvailable ? "verfügbar" : "nicht verfügbar")
            } footer: {
                Text(engine.criticalAvailable
                     ? "„Dringend niedrig“ und dringende Pumpenmeldungen kommen auch bei Stummschalter und Fokus."
                     : engine.timeSensitiveAvailable
                     ? "Kritische Alarme (durch Stummschalter) brauchen eine Freigabe von Apple. Bis dahin kommen dringende Alarme als „zeitkritisch“: Sie durchbrechen Fokus-Modi, folgen aber dem Stummschalter. In den iPhone-Einstellungen › Mitteilungen › iPump-mini „Zeitkritische Mitteilungen“ aktiviert lassen."
                     : "Kritische und zeitkritische Alarme sind in diesem Build nicht verfügbar (kostenloses Entwickler-Team). Alarme kommen als normale Mitteilungen: mit Ton, aber nicht durch Stummschalter oder Fokus-Modi. Für die Nacht den Fokus so einstellen, dass iPump-mini durchkommt.")
            }
        }
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
                    Stepper(String(format: "ab %.1f mg/dL pro Minute", rule.threshold), value: $rule.threshold, in: 1...4, step: 0.5)
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
        let prefix = kind == .high ? "ab" : "unter"
        return "\(prefix) \(Int(rule.threshold)) mg/dL (\(String(format: "%.1f", rule.threshold / 18)) mmol/L)"
    }
}
