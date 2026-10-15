// SPDX-License-Identifier: GPL-3.0-or-later
import MiniMedKit
import SwiftUI
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Watchdog.appTerminated()
    }

    /// Alarms also show (with sound) while the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// Snooze actions of an alarm notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let key = response.notification.request.content.userInfo["alarmKey"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            if let key, let snooze = AlarmEngine.snoozeActions.first(where: { $0.id == action }) {
                AlarmEngine.shared.snooze(key: key, minutes: snooze.minutes)
            }
            completionHandler()
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let config = AppConfig.load()
    let store = DataStore()
    let log = EventLog()
    let api: LocalAPIServer
    private(set) var link: PumpLink!
    let uploader: NightscoutUploader

    @Published var apiState = L10n.tr("gestartet")
    @Published var apiAllowLAN = UserDefaults.standard.bool(forKey: "apiAllowLAN") {
        didSet { UserDefaults.standard.set(apiAllowLAN, forKey: "apiAllowLAN") }
    }
    // Stored in UserDefaults for now; moves to the keychain together with the Nightscout secret.
    @Published var apiSecret = UserDefaults.standard.string(forKey: "apiSecret") ?? "" {
        didSet { UserDefaults.standard.set(apiSecret, forKey: "apiSecret") }
    }

    /// iOS suspends the app a few seconds after each pump wake-up; the local API (watch
    /// faces poll it) would then not answer. A background task keeps it reachable for
    /// ~25 s after every new value, so clients polling around that time get it.
    private var apiKeepAlive: UIBackgroundTaskIdentifier = .invalid

    func keepAPIAwake() {
        guard UIApplication.shared.applicationState != .active, apiKeepAlive == .invalid else { return }
        api.revive()
        apiKeepAlive = UIApplication.shared.beginBackgroundTask(withName: "LocalAPI") { [weak self] in
            self?.endAPIKeepAlive()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.endAPIKeepAlive() }
    }

    private func endAPIKeepAlive() {
        guard apiKeepAlive != .invalid else { return }
        UIApplication.shared.endBackgroundTask(apiKeepAlive)
        apiKeepAlive = .invalid
    }

    init() {
        api = LocalAPIServer(shared: store.shared)
        uploader = NightscoutUploader(store: store, log: log)
        let uploader = uploader
        link = PumpLink(config: config, store: store, log: log, onData: {
            Watchdog.arm()
        }, onHistory: { oldest in
            uploader.historyAdded(oldestReading: oldest)
        })
        let store = store
        store.onNewReading = { [weak self] in
            self?.keepAPIAwake()
            uploader.newReading()
            if let latest = store.latest { AlarmEngine.shared.evaluate(latest) }
            WidgetBridge.update(store: store)
        }
        AlarmEngine.shared.log = log
        WidgetBridge.log = log
        AlarmEngine.shared.registerCategories()
        api.onStateChange = { [weak self] text in
            Task { @MainActor in self?.apiState = text }
        }
        let log = log
        api.onLog = { text in
            Task { @MainActor in log.add(text, .warning) }
        }
        api.onRequest = { text in
            Task { @MainActor in log.add(text) }
        }
        restartAPI()
        #if DEBUG
        let isDemo = ProcessInfo.processInfo.arguments.contains("-demoData")
        #else
        let isDemo = false
        #endif
        // Simulator tests with demo data skip the permission dialog (it blocks the UI).
        // Asked during onboarding; afterwards refreshes the critical/time-sensitive state.
        if !isDemo && Terms.isAccepted { AlarmEngine.shared.requestAuthorization() }
        Watchdog.configure(enabled: AlarmEngine.shared.config.noDataEnabled, minutes: AlarmEngine.shared.config.noDataMinutes)
        link.migrateHistoryIfNeeded()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            store.loadDemoData()
            WidgetBridge.update(store: store)
        }
        if ProcessInfo.processInfo.arguments.contains("-demoAlarm") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                AlarmEngine.shared.evaluate(GlucoseReading(date: Date(), mgdl: 52, trendMgdlPerMin: -2.5, sessionOffsetMinutes: nil))
            }
        }
        if let url = ProcessInfo.processInfo.environment["OMP_NS_URL"] {
            uploader.url = url
            uploader.secret = ProcessInfo.processInfo.environment["OMP_NS_SECRET"] ?? ""
            uploader.enabled = true
            uploader.newReading()
        }
        #endif
    }

    func restartAPI() {
        api.start(allowLAN: apiAllowLAN && !apiSecret.isEmpty, secret: apiSecret)
    }
}

@main
struct OpenMinipumpApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Prefs.languageKey, store: Prefs.defaults) private var language = AppLanguage.system.rawValue
    @AppStorage(Prefs.themeKey, store: Prefs.defaults) private var theme = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.link)
                .environmentObject(model.log)
                .environmentObject(model.uploader)
                .appPreferences(language: language, theme: theme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Watchdog.appOpened()
                model.api.revive()
                WidgetBridge.appBecameActive(store: model.store)
            }
        }
    }
}
