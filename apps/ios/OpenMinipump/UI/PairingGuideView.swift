// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct PairingGuideView: View {
    @EnvironmentObject private var link: PumpLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Diese App erscheint an der Pumpe als")
                            .foregroundStyle(.secondary)
                        Text("Mobile \(link.advertisedName)")
                            .font(.title2.monospaced().weight(.bold))
                        HStack {
                            Circle().fill(link.pairingMode ? .green : .gray).frame(width: 8, height: 8)
                            Text(link.pairingMode ? "Kopplungsmodus aktiv" : link.phase.label)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("So koppelst du die Pumpe") {
                    Step(n: 1, text: "Die Pumpe nimmt nur **ein** Mobilgerät an. Ist noch MiniMed Mobile gekoppelt, entferne diese Kopplung zuerst an der Pumpe (Menü › Kopplungsoptionen › gekoppelte Geräte).")
                    Step(n: 2, text: "Lass diese App im Vordergrund geöffnet und das iPhone entsperrt, bis die Kopplung fertig ist.")
                    Step(n: 3, text: "An der Pumpe: **Menü › Kopplungsoptionen › Neues Gerät koppeln**. Die Bezeichnungen können je nach Softwarestand leicht abweichen.")
                    Step(n: 4, text: "Die Pumpe zeigt **Mobile \(link.advertisedName)**. Wähle es aus und bestätige.")
                    Step(n: 5, text: "Auf dem iPhone erscheint eine **Bluetooth-Kopplungsanfrage**. Tippe auf „Koppeln“.")
                    Step(n: 6, text: "Danach erscheinen nach kurzer Zeit die ersten Werte. Ab jetzt die App nicht mehr wegwischen; im Hintergrund läuft sie weiter.")
                }

                Section {
                    Text("Die App liest nur. Sie kann keinen Bolus abgeben, keine Einstellungen ändern und keine Alarme quittieren.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pumpe koppeln")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear { link.setPairingMode(true) }
            .onDisappear { if link.pairingMode { link.setPairingMode(false) } }
        }
    }
}

private struct Step: View {
    let n: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.callout.weight(.bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text)
        }
        .padding(.vertical, 2)
    }
}
