// SPDX-License-Identifier: GPL-3.0-or-later
import MiniMedKit
import SwiftUI

/// Import of the SAKE key database "Mobile Application ↔ Insulin Pump" for builds that do
/// not contain it (e.g. installed via AltStore).
struct KeyImportView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var link: PumpLink
    @State private var hex = ""
    @State private var message: String?
    @State private var ok = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status", value: status)
            } footer: {
                Text("Die App braucht diese Datenbank für die verschlüsselte Verbindung zur Pumpe. Sie ist nicht in der App enthalten. Du findest sie in der Dokumentation von OpenMinimed (key_databases.md, Abschnitt „Mobile Application ↔ Insulin Pump“). Füge die Zeile aus Hex-Zeichen unten ein; Leerzeichen sind egal.")
            }

            if model.config.keyDatabaseSource != .bundle {
                Section("Einfügen") {
                    TextEditor(text: $hex)
                        .font(.caption.monospaced())
                        .frame(minHeight: 120)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Prüfen und speichern") {
                        do {
                            let db = try KeyImport.save(hex)
                            link.setKeyDatabase(db)
                            ok = true
                            message = "Gespeichert. Die App kann jetzt mit der Pumpe sprechen."
                            hex = ""
                        } catch {
                            ok = false
                            message = "Nicht gültig: \(error.localizedDescription)"
                        }
                    }
                    .disabled(hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let message {
                        Text(message).font(.caption).foregroundStyle(ok ? .green : .red)
                    }
                }
                if KeyImport.stored() != nil {
                    Section {
                        Button("Importierte Datenbank entfernen", role: .destructive) {
                            KeyImport.remove()
                            message = "Entfernt. Wirkt nach einem Neustart der App."
                            ok = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Schlüsseldatenbank")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var status: String {
        if link.keyDatabase == nil { return "fehlt" }
        switch model.config.keyDatabaseSource {
        case .bundle: return "im App-Paket enthalten"
        case .imported, .missing: return "importiert"
        }
    }
}
