// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UserNotifications

/// First start: welcome and language, terms of use (must be accepted), then a setup
/// checklist. Shown again when `Terms.version` rises; the checklist then shows what is
/// already done.
struct OnboardingView: View {
    @EnvironmentObject private var link: PumpLink
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.languageKey, store: Prefs.defaults) private var language = AppLanguage.system.rawValue
    @AppStorage(SensorType.key) private var sensorType = ""
    @State private var page = 0
    @State private var readTerms = false
    @State private var understoodAlarms = false
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var showPairing = false
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case 0: welcome
                case 1: terms
                default: setup
                }
            }
            .animation(.default, value: page)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showPairing) { PairingGuideView() }
        .task { await refreshNotificationStatus() }
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("AppIconImage")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(spacing: 8) {
                Text("iPump-mini").font(.largeTitle.weight(.bold))
                Text("Liest deine MiniMed 780G per Bluetooth aus, nur lesend und ohne Cloud.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Picker("Sprache", selection: $language) {
                Text("Wie System").tag(AppLanguage.system.rawValue)
                Text("Deutsch").tag(AppLanguage.de.rawValue)
                Text("English").tag(AppLanguage.en.rawValue)
            }
            .pickerStyle(.segmented)
            Spacer()
            Button { page = 1 } label: {
                Text("Weiter").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    private var terms: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Bitte lies diese Bedingungen. Ohne Zustimmung lässt sich die App nicht verwenden.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TermsText()
                }
                .padding()
            }
            VStack(spacing: 12) {
                Toggle(isOn: $readTerms) {
                    Text("Ich habe die Nutzungsbedingungen gelesen und stimme ihnen zu.").font(.subheadline)
                }
                Toggle(isOn: $understoodAlarms) {
                    Text("Ich habe verstanden: Für Behandlungsentscheidungen und Alarme ist die Pumpe maßgeblich. Die App kann ausfallen, ihre Alarme können verspätet oder stumm kommen.")
                        .font(.subheadline)
                }
                Button {
                    Terms.accept()
                    page = 2
                } label: {
                    Text("Zustimmen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!(readTerms && understoodAlarms))
            }
            .toggleStyle(CheckboxToggleStyle())
            .padding()
            .background(.bar)
        }
        .navigationTitle("Nutzungsbedingungen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var setup: some View {
        List {
            Section {
                Text("Diese Schritte kannst du auch später in den Einstellungen erledigen.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Einrichtung") {
                NavigationLink {
                    KeyImportView()
                } label: {
                    SetupRow(done: link.keyDatabase != nil, title: "Schlüsseldatenbank",
                             detail: link.keyDatabase != nil ? "vorhanden" : "fehlt, jetzt laden")
                }
                Button {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
                        AlarmEngine.shared.requestAuthorization()
                        await refreshNotificationStatus()
                    }
                } label: {
                    SetupRow(done: notifications == .authorized, title: "Mitteilungen erlauben",
                             detail: notificationDetail)
                }
                .disabled(notifications == .authorized)
                Picker(selection: $sensorType) {
                    Text("Nicht festgelegt").tag("")
                    Text(SensorType.simplera.label).tag(SensorType.simplera.rawValue)
                    Text(SensorType.guardian.label).tag(SensorType.guardian.rawValue)
                } label: {
                    SetupRow(done: !sensorType.isEmpty, title: "Sensor", detail: nil)
                }
                Button { showPairing = true } label: {
                    SetupRow(done: link.isPaired, title: "Pumpe koppeln",
                             detail: link.isPaired ? "gekoppelt" : "Anleitung öffnen")
                }
                .disabled(link.keyDatabase == nil)
            }
            Section {
                GuideItem(icon: "moon", title: "Fokus und Schlafmodus",
                          text: "Füge iPump-mini in deinem Schlaf-Fokus unter „Erlaubte Apps“ hinzu, sonst bleiben Alarme nachts stumm.")
                GuideItem(icon: "iphone", title: "App nicht wegwischen",
                          text: "Nur im Hintergrund laufend bekommt die App alle 5 Minuten neue Werte.")
                NavigationLink("Ganze Anleitung") { GuideView() }
            } header: {
                Text("Wichtig")
            }
            Section {
                Button { onFinish() } label: {
                    Text("Fertig").frame(maxWidth: .infinity).font(.headline)
                }
            }
        }
        .navigationTitle("Einrichten")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await refreshNotificationStatus() } }
    }

    private var notificationDetail: LocalizedStringKey {
        switch notifications {
        case .authorized: return "erlaubt"
        case .denied: return "abgelehnt: in den iPhone-Einstellungen erlauben"
        default: return "für Alarme nötig"
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = settings.authorizationStatus
    }
}

private struct SetupRow: View {
    let done: Bool
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Checkbox look for the consent toggles.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }
}
