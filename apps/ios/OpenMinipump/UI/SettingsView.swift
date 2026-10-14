// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var link: PumpLink
    @Environment(\.dismiss) private var dismiss
    @State private var watchdog = Watchdog.enabled

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: model.apiState)
                    LabeledContent("Adresse", value: "http://127.0.0.1:\(LocalAPIServer.port)")
                    Toggle("Im WLAN freigeben", isOn: $model.apiAllowLAN)
                        .onChange(of: model.apiAllowLAN) { _, _ in model.restartAPI() }
                    if model.apiAllowLAN {
                        SecureField("API-Secret (Pflicht für WLAN)", text: $model.apiSecret)
                            .onSubmit { model.restartAPI() }
                        if model.apiSecret.isEmpty {
                            Text("Ohne API-Secret bleibt die API auf dieses iPhone beschränkt.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Lokale API (Nightscout-kompatibel)")
                } footer: {
                    Text("Endpunkte wie Nightscout: /api/v1/entries.json, /api/v1/devicestatus.json, /pebble. iOS pausiert die App im Hintergrund zwischen den Bluetooth-Ereignissen; dann antwortet die API nicht.")
                }

                Section {
                    Toggle("Erinnern, wenn keine Daten kommen", isOn: $watchdog)
                        .onChange(of: watchdog) { _, on in Watchdog.enabled = on }
                } header: {
                    Text("Benachrichtigungen")
                } footer: {
                    Text("Kommen 20 Minuten lang keine Pumpendaten (z. B. weil die App weggewischt wurde), erscheint eine Mitteilung zum erneuten Öffnen.")
                }

                Section("Pumpe") {
                    LabeledContent("Name in der Pumpe", value: "Mobile \(link.advertisedName)")
                    LabeledContent("Seriennummer", value: link.pumpSerial ?? "–")
                    LabeledContent("Firmware", value: link.pumpFirmware ?? "–")
                    LabeledContent("Verbindung", value: link.phase.label)
                    LabeledContent("Entwicklermodus", value: model.config.devGuard.devMode ? "an (nur Testpumpe)" : "aus")
                }

                Section {
                    NavigationLink("Protokoll") { LogView() }
                    NavigationLink("Über & Impressum") { AboutView() }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { model.restartAPI(); dismiss() }
                }
            }
        }
    }
}

struct LogView: View {
    @EnvironmentObject private var log: EventLog

    var body: some View {
        List(log.entries.reversed()) { e in
            VStack(alignment: .leading, spacing: 2) {
                Text(e.date.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                Text(e.text)
                    .font(.caption.monospaced())
                    .foregroundStyle(e.level == .error || e.level == .blocked ? .red : e.level == .warning ? .orange : .primary)
            }
        }
        .navigationTitle("Protokoll")
        .toolbar {
            ShareLink(item: log.exportText) { Image(systemName: "square.and.arrow.up") }
        }
    }
}
