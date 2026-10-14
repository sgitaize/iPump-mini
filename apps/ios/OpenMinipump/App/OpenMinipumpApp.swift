// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        Watchdog.appTerminated()
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

    @Published var apiState = "gestartet"
    @Published var apiAllowLAN = UserDefaults.standard.bool(forKey: "apiAllowLAN") {
        didSet { UserDefaults.standard.set(apiAllowLAN, forKey: "apiAllowLAN") }
    }
    // Stored in UserDefaults for now; moves to the keychain together with the Nightscout secret.
    @Published var apiSecret = UserDefaults.standard.string(forKey: "apiSecret") ?? "" {
        didSet { UserDefaults.standard.set(apiSecret, forKey: "apiSecret") }
    }

    init() {
        api = LocalAPIServer(shared: store.shared)
        uploader = NightscoutUploader(store: store, log: log)
        let uploader = uploader
        link = PumpLink(config: config, store: store, log: log) {
            Watchdog.arm()
            uploader.dataChanged()
        }
        api.onStateChange = { [weak self] text in
            Task { @MainActor in self?.apiState = text }
        }
        let log = log
        api.onLog = { text in
            Task { @MainActor in log.add(text, .warning) }
        }
        restartAPI()
        Watchdog.requestAuthorization()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoData") { store.loadDemoData() }
        if let url = ProcessInfo.processInfo.environment["OMP_NS_URL"] {
            uploader.url = url
            uploader.secret = ProcessInfo.processInfo.environment["OMP_NS_SECRET"] ?? ""
            uploader.enabled = true
            uploader.dataChanged()
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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environmentObject(model.link)
                .environmentObject(model.log)
                .environmentObject(model.uploader)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Watchdog.appOpened()
                model.api.ensureRunning()
            }
        }
    }
}
