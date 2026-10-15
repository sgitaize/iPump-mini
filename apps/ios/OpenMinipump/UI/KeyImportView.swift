// SPDX-License-Identifier: GPL-3.0-or-later
import MiniMedKit
import SwiftUI

/// Import of the SAKE key database "Mobile Application ↔ Insulin Pump" for builds that do
/// not contain it (e.g. installed via AltStore). It is not shipped with the app: the user
/// loads it from the public OpenMinimed documentation, another address or pastes it.
struct KeyImportView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var link: PumpLink
    @State private var hex = ""
    @State private var customURL = ""
    @State private var message: String?
    @State private var ok = false
    @State private var loading = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(status, systemImage: link.keyDatabase != nil ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(link.keyDatabase != nil ? .green : .orange)
                }
            } footer: {
                Text("Die App braucht diese Datenbank für die verschlüsselte Verbindung zur Pumpe. Sie ist nicht in der App enthalten, sondern wird von der öffentlichen Dokumentation des Projekts OpenMinimed geladen und mit Prüfsumme und Gerätetyp geprüft.")
            }

            if model.config.keyDatabaseSource != .bundle {
                Section {
                    Button {
                        load(KeyImport.openMinimedURL)
                    } label: {
                        Label(loading ? "Lädt …" : "Von OpenMinimed laden", systemImage: "arrow.down.circle")
                    }
                    .disabled(loading)
                    Link(destination: KeyImport.openMinimedPage) {
                        Label("Quelle ansehen", systemImage: "safari")
                    }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(ok ? .green : .red)
                    }
                } header: {
                    Text("Laden")
                } footer: {
                    Text("Lädt die Seite key_databases.md von GitHub und übernimmt den Block „Mobile Application ↔ Insulin Pump“. Es werden keine Daten von dir gesendet.")
                }

                Section("Andere Adresse") {
                    TextField("https://…", text: $customURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Von dieser Adresse laden") {
                        if let url = URL(string: customURL.trimmingCharacters(in: .whitespaces)) { load(url) }
                    }
                    .disabled(loading || URL(string: customURL)?.scheme?.hasPrefix("http") != true)
                }

                Section("Einfügen") {
                    TextEditor(text: $hex)
                        .font(.caption.monospaced())
                        .frame(minHeight: 100)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Prüfen und speichern") {
                        do {
                            let db = try KeyImport.save(KeyImport.extract(from: hex) ?? hex)
                            done(db)
                            hex = ""
                        } catch {
                            fail(error)
                        }
                    }
                    .disabled(hex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if KeyImport.stored() != nil {
                    Section {
                        Button("Importierte Datenbank entfernen", role: .destructive) {
                            KeyImport.remove()
                            message = L10n.tr("Entfernt. Wirkt nach einem Neustart der App.")
                            ok = true
                        }
                    }
                }
            }
        }
        .navigationTitle("Schlüsseldatenbank")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func load(_ url: URL) {
        loading = true
        message = nil
        Task {
            do { done(try await KeyImport.load(from: url)) } catch { fail(error) }
            loading = false
        }
    }

    private func done(_ db: KeyDatabase) {
        link.setKeyDatabase(db)
        ok = true
        message = L10n.tr("Gespeichert. Die App kann jetzt mit der Pumpe sprechen.")
    }

    private func fail(_ error: Error) {
        ok = false
        message = L10n.tr("Nicht gültig: %@", error.localizedDescription)
    }

    private var status: String {
        if link.keyDatabase == nil { return L10n.tr("fehlt") }
        switch model.config.keyDatabaseSource {
        case .bundle: return L10n.tr("im App-Paket enthalten")
        case .imported, .missing: return L10n.tr("vorhanden")
        }
    }
}
