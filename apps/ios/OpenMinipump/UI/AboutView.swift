// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Publisher details shown in "Über & Impressum" (same as the imprint on simongutjahr.de).
enum Publisher {
    static let name = "Simon Gutjahr"
    static let address = "Sachsenstr. 1\n76137 Karlsruhe\nDeutschland"
    static let email = "kontakt@simongutjahr.de"
    static let phone = "0157 81640322"
    static let websiteTitle = "simongutjahr.de"
    static let website = URL(string: "https://simongutjahr.de/dev/")!
    static let imprint = URL(string: "https://simongutjahr.de/impressum/")!
    static let privacy = URL(string: "https://simongutjahr.de/impressum/#ipump-mini")!
    static let repository = URL(string: "https://github.com/sgitaize/iPump-mini")!
}

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("App", value: "iPump-mini")
                LabeledContent("Version", value: version)
                LabeledContent("Lizenz", value: "GPL-3.0")
                Link(destination: Publisher.repository) { Label("Quellcode auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            }

            Section("Impressum") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: Publisher.name).font(.body.weight(.semibold))
                    Text(verbatim: Publisher.address).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "mailto:\(Publisher.email)")!) { Label(Publisher.email, systemImage: "envelope") }
                Link(destination: URL(string: "tel:\(Publisher.phone.filter(\.isNumber))")!) { Label(Publisher.phone, systemImage: "phone") }
                Link(destination: Publisher.website) { Label(Publisher.websiteTitle, systemImage: "globe") }
                Link(destination: Publisher.imprint) { Label("Impressum", systemImage: "doc.text") }
                Link(destination: Publisher.privacy) { Label("Datenschutzerklärung der App", systemImage: "hand.raised") }
                Text("Privates, nicht-kommerzielles Open-Source-Projekt.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Wichtiger Hinweis") {
                Text("iPump-mini (Projekt openMinipump) ist kein Medizinprodukt und nicht für Therapieentscheidungen bestimmt. Maßgeblich sind immer die Anzeigen und Alarme der Pumpe. Die App liest die Pumpe ausschließlich aus und kann keine Einstellungen ändern oder Insulin abgeben. Nutzung auf eigene Verantwortung.")
                    .font(.footnote)
            }

            Section {
                Source(title: "OpenMinimed", detail: "Protokoll-Dokumentation, PythonSake, JavaSake, PythonPumpConnector (GPL-3.0). Die SAKE-Implementierung dieser App ist ein Swift-Port davon.",
                       url: "https://github.com/OpenMinimed")
                Source(title: "Bluetooth SIG", detail: "Spezifikationen Insulin Delivery Service (IDS), Continuous Glucose Monitoring Service (CGMS), GATT Specification Supplement.",
                       url: "https://www.bluetooth.com/specifications/specs/")
                Source(title: "Nightscout", detail: "API-Format der lokalen Schnittstelle (cgm-remote-monitor).",
                       url: "https://github.com/nightscout/cgm-remote-monitor")
                Source(title: "xDrip+", detail: "Port 17580 der lokalen Schnittstelle, für kompatible Clients.",
                       url: "https://github.com/NightscoutFoundation/xDrip")
            } header: {
                Text("Quellen & Dank")
            }

            Section("Marken") {
                Text("Medtronic, MiniMed, CareLink, SmartGuard und Guardian sind Marken der Medtronic plc bzw. ihrer Tochtergesellschaften. Dieses Projekt steht in keiner Verbindung zu Medtronic und wird von Medtronic weder unterstützt noch geprüft.")
                    .font(.footnote)
            }

            Section("Datenschutz") {
                Text("Alle Daten bleiben auf diesem iPhone. Die App sendet nichts an Medtronic oder CareLink und nichts an die Entwickler. Ins Internet verbindet sie sich nur, wenn du den Nightscout-Upload einschaltest oder die Schlüsseldatenbank lädst (GitHub). Die lokale API ist standardmäßig nur auf diesem Gerät erreichbar; eine Freigabe im WLAN ist optional und durch ein API-Secret geschützt.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Über & Impressum")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct Source: View {
    let title: String
    let detail: LocalizedStringKey
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link(destination: URL(string: url)!) { Text(verbatim: title) }.font(.body.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
