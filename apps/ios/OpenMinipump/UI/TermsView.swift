// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Terms of use and disclaimer. Raising `version` asks every user to accept again.
enum Terms {
    static let version = 1
    static let acceptedVersionKey = "termsAcceptedVersion"
    static let acceptedAtKey = "termsAcceptedAt"

    static var isAccepted: Bool { UserDefaults.standard.integer(forKey: acceptedVersionKey) >= version }

    static func accept() {
        UserDefaults.standard.set(version, forKey: acceptedVersionKey)
        UserDefaults.standard.set(Date(), forKey: acceptedAtKey)
    }

    /// Simulator screenshots with demo data skip the onboarding unless `-onboarding` is passed.
    static var needsOnboarding: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-onboarding") { return true }
        if args.contains("-demoData") { return false }
        #endif
        return !isAccepted
    }

    static var acceptedAt: Date? { UserDefaults.standard.object(forKey: acceptedAtKey) as? Date }
}

/// The text of the terms. Shown during onboarding and in Settings › Info.
struct TermsText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            block("1. Zweck",
                  "iPump-mini ist ein privates, nicht-kommerzielles Open-Source-Projekt. Die App liest Daten einer Insulinpumpe der Reihe MiniMed 780G per Bluetooth aus und zeigt sie an. Sie dient nur der Information und dem Komfort.")
            block("2. Kein Medizinprodukt",
                  "Die App ist kein Medizinprodukt, hat keine Zulassung und keine CE-Kennzeichnung. Sie darf nicht für Therapie- oder Behandlungsentscheidungen verwendet werden, zum Beispiel für die Berechnung oder Abgabe von Insulin oder die Behandlung einer Unterzuckerung.")
            block("3. Die Pumpe ist maßgeblich",
                  "Maßgeblich sind immer die Anzeigen, Werte und Alarme der Pumpe und des Sensors. Die Alarme der Pumpe müssen eingeschaltet bleiben. Die Alarme dieser App sind eine unverbindliche Ergänzung und ersetzen die Alarme der Pumpe nicht.")
            block("4. Grenzen der App",
                  "Angezeigte Werte können falsch, veraltet oder unvollständig sein. Die App kann jederzeit ausfallen, etwa wenn iOS sie beendet, die Bluetooth-Verbindung abbricht, das iPhone stummgeschaltet ist, ein Fokus-Modus aktiv ist, Mitteilungen deaktiviert sind oder der Akku leer ist. Alarme können verspätet, stumm oder gar nicht kommen.")
            block("5. Nur lesend",
                  "Die App ist so gebaut, dass sie keine Befehle sendet, die Therapie, Einstellungen oder Zustand der Pumpe verändern. Eine Garantie dafür, dass die Pumpe sich durch die Verbindung in keiner Weise anders verhält, gibt es nicht.")
            block("6. Keine Verbindung zum Hersteller",
                  "Das Projekt steht in keiner Verbindung zu Medtronic und wird von Medtronic weder unterstützt noch geprüft. MiniMed, SmartGuard, Guardian, Simplera und CareLink sind Marken ihrer Inhaber. Die Nutzung kann Garantie- oder Supportbedingungen des Herstellers berühren; das prüfst du selbst.")
            block("7. Haftung",
                  "Die App wird unentgeltlich und ohne Gewährleistung bereitgestellt, so wie sie ist (siehe GPL-3.0, Abschnitte 15 und 16). Die Haftung der Entwickler ist ausgeschlossen, soweit das gesetzlich zulässig ist. Unberührt bleibt die Haftung für Vorsatz und grobe Fahrlässigkeit sowie nach zwingenden gesetzlichen Vorschriften.")
            block("8. Daten",
                  "Die Daten bleiben auf deinem iPhone. Die Entwickler erhalten keine Daten. Sie verlassen das Gerät nur, wenn du selbst den Nightscout-Upload oder die lokale API im WLAN einschaltest; dafür bist du verantwortlich.")
            block("9. Eigene Verantwortung",
                  "Du nutzt die App auf eigene Verantwortung und prüfst selbst, ob die Nutzung in deinem Land zulässig ist. Sprich bei Fragen zu deiner Therapie mit deinem Diabetes-Team.")
        }
    }

    private func block(_ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline)
        }
    }
}

/// Read-only view of the accepted terms (Settings › Info).
struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TermsText()
                if let at = Terms.acceptedAt {
                    Text("Zugestimmt am \(at.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(L10n.locale))) (Version \(Terms.version)).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Nutzungsbedingungen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
