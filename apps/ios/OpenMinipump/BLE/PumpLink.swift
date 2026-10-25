// SPDX-License-Identifier: GPL-3.0-or-later
// BLE link to the pump.
//
// Roles (see docs/internal/landscape.md): the pump is the BLE central and SAKE client, the phone
// is the BLE peripheral and SAKE server. After the SAKE handshake the phone additionally
// acts as GATT client on the same link to read the pump's services.
//
// HARD RULE 1: every write towards the pump goes through `guardedWrite`, which asks
// MiniMedKit.ReadOnlyPolicy. There is no other code path that calls writeValue on a pump
// characteristic.
import CoreBluetooth
import Foundation
import MiniMedKit

@MainActor
final class PumpLink: NSObject, ObservableObject {
    enum Phase: Equatable {
        case bluetoothOff
        case waitingForPump
        case pairing
        case handshake
        case connecting
        case verifying
        case connected
        case blocked(String)
        case failed(String)

        var label: String {
            switch self {
            case .bluetoothOff: L10n.tr("Bluetooth aus")
            case .waitingForPump: L10n.tr("Warte auf Pumpe")
            case .pairing: L10n.tr("Kopplungsmodus")
            case .handshake: L10n.tr("Handshake läuft")
            case .connecting: L10n.tr("Verbinde")
            case .verifying: L10n.tr("Prüfe Pumpe")
            case .connected: L10n.tr("Verbunden")
            case .blocked: L10n.tr("Blockiert")
            case .failed: L10n.tr("Fehler")
            }
        }
    }

    @Published private(set) var phase: Phase = .waitingForPump
    @Published private(set) var pairingMode = false
    @Published private(set) var pumpSerial: String?
    @Published private(set) var pumpFirmware: String?
    /// True once a pump was paired with this app (survives updates). The UI then shows
    /// "waiting for connection" instead of asking to pair again.
    @Published private(set) var isPaired = UserDefaults.standard.bool(forKey: "isPaired")
    /// Set when we are waiting for the pump to reconnect without a session; the UI shows
    /// the Bluetooth off/on hint after a while.
    @Published private(set) var waitingSince: Date?

    let advertisedName: String

    private let config: AppConfig
    @Published private(set) var keyDatabase: KeyDatabase?
    private let store: DataStore
    private let log: EventLog
    private let onData: () -> Void
    /// New history data was merged; argument is the oldest newly added sensor value.
    private let onHistory: (Date?) -> Void

    // nil in demo mode: no Bluetooth at all.
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var sakePort: CBMutableCharacteristic?
    private var sake: SakeServer?
    private var pumpCentral: CBCentral?
    private var outbox: [Data] = []

    private var pump: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var pendingDiscovery = 0
    private var serialVerified = false
    private var sessionStart: Date?
    /// Correction of the reported session start (clock shift, see `SensorClock`), kept across
    /// reconnects for the same reported start.
    private var sessionStartShift: (reported: Date, shift: TimeInterval)? {
        get {
            let d = UserDefaults.standard
            guard let reported = d.object(forKey: "sessionStartReported") as? Date else { return nil }
            return (reported, d.double(forKey: "sessionStartShift"))
        }
        set {
            UserDefaults.standard.set(newValue?.reported, forKey: "sessionStartReported")
            UserDefaults.standard.set(newValue?.shift, forKey: "sessionStartShift")
        }
    }
    /// Session offset of the last live value; a different one was just measured.
    private var lastLiveOffset: Int?
    private var operations: [Operation] = []
    private var current: Operation?
    private var operationTimer: Timer?
    private var lastRefresh: Date = .distantPast
    private var retrieveAttempts = 0
    private var sensorRunHours: Int?
    /// Session cipher after the handshake; persisted so it survives an app relaunch.
    private var crypt: SeqCrypt?
    private var decryptFailures = 0
    private var currentStartedAt: Date?
    private var refreshPending = false
    /// Pump history (IDD RACP): records collected during one sync run.
    private var historyBuffer: [HistoryRecord] = []
    private var historyNewestSeq: UInt32?
    private var lastHistorySync: Date = .distantPast

    /// Characteristics whose values are SAKE-encrypted (OpenMinimed pump-services.md).
    private static let encrypted: Set<String> = Set([
        PumpUUID.iddStatusChanged, PumpUUID.iddStatus, PumpUUID.iddAnnunciation, PumpUUID.iddFeatures,
        PumpUUID.iddStatusReaderCP, PumpUUID.iddCommandCP, PumpUUID.iddCommandData, PumpUUID.iddHistoryData,
        PumpUUID.cgmMeasurement, PumpUUID.cgmStatus, PumpUUID.cgmSessionStartTime, PumpUUID.cgmSpecificOpsCP,
    ].map { $0.uppercased() })

    private enum Operation: CustomStringConvertible {
        case read(service: String, characteristic: String)
        case statusReader(StatusReaderOpcode)
        case cgmLastRecord
        case historyLast
        case historyRange(from: UInt32, to: UInt32)

        var description: String {
            switch self {
            case .read(_, let c): "Lesen \(c)"
            case .statusReader(let op): "SRCP \(op)"
            case .cgmLastRecord: "CGM letzter Wert"
            case .historyLast: "History: letzter Eintrag"
            case .historyRange(let a, let b): "History \(a)…\(b)"
            }
        }
    }

    /// `bluetooth: false` (demo mode): no Bluetooth managers at all, the pump is not touched.
    init(config: AppConfig, store: DataStore, log: EventLog, bluetooth: Bool = true,
         onData: @escaping () -> Void, onHistory: @escaping (Date?) -> Void = { _ in }) {
        self.config = config
        self.keyDatabase = config.keyDatabase
        self.store = store
        self.log = log
        self.onData = onData
        self.onHistory = onHistory
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "advertisedName") {
            advertisedName = name
        } else {
            advertisedName = String(format: "%06d", Int.random(in: 0...999_999))
            defaults.set(advertisedName, forKey: "advertisedName")
        }
        super.init()
        guard bluetooth else {
            log.add("Demo-Modus: Bluetooth aus")
            return
        }
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [
            CBPeripheralManagerOptionRestoreIdentifierKey: "openminipump.peripheral",
        ])
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "openminipump.central",
        ])
        if let error = config.keyDatabaseError { phase = .failed(error); log.add(error, .error) }
        log.add("DEV_MODE=\(config.devGuard.devMode ? "1" : "0"), Testpumpe \(config.devGuard.testPumpSerial.isEmpty ? "nicht gesetzt" : "gesetzt")")
    }

    // MARK: - Public controls

    func setPairingMode(_ on: Bool) {
        pairingMode = on
        log.add(on ? "Kopplungsmodus an (Mobile \(advertisedName))" : "Kopplungsmodus aus")
        updateAdvertising()
    }

    /// A key database was imported in the settings.
    /// Demo mode switched on while no pump is paired: release Bluetooth for this run.
    func stopForDemo() {
        guard !isPaired else { return }
        peripheralManager?.stopAdvertising()
        peripheralManager?.delegate = nil
        centralManager?.delegate = nil
        peripheralManager = nil
        centralManager = nil
        log.add("Demo-Modus: Bluetooth aus")
    }

    func setKeyDatabase(_ db: KeyDatabase) {
        keyDatabase = db
        if case .failed = phase { phase = .waitingForPump }
        log.add("Schlüsseldatenbank importiert")
    }

    func refreshNow() {
        guard phase == .connected else { return }
        scheduleRefresh(force: true)
    }

    // MARK: - Peripheral side (GATT server, SAKE)

    /// Values of the app's Device Information Service (custom UUID 0x0900). The pump reads
    /// all of them before it starts the SAKE handshake. They mirror what the official iOS app
    /// serves (lab notebook, capture 1) for interoperability; with other values the pump
    /// reported "device not compatible".
    private lazy var deviceInfo: [CBUUID: Data] = {
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return [
            CBUUID(string: "2A29"): Data("Apple".utf8),
            CBUUID(string: "2A24"): Data(machine.utf8),
            CBUUID(string: "2A25"): Data("Mobile \(advertisedName)".utf8),
            CBUUID(string: "2A27"): Data("iPhone".utf8),
            CBUUID(string: "2A26"): Data("iOS".utf8),
            CBUUID(string: "2A28"): Data(Self.compatSoftwareRevision.utf8),
            CBUUID(string: "2A23"): Data(count: 8),
            CBUUID(string: "2A50"): Data(count: 7),
            CBUUID(string: "2A2A"): Data(),
        ]
    }()

    /// Software revision reported to the pump. The pump may check the companion app
    /// version; we report the version seen in capture 1. See docs/internal/lab-notebook.md.
    static let compatSoftwareRevision = "3.3.0(80)"

    /// Bump when the GATT table changes, so restored (old) services get replaced.
    private static let gattVersion = 2

    private func setUpServices() {
        let defaults = UserDefaults.standard
        if sakePort != nil, defaults.integer(forKey: "gattVersion") == Self.gattVersion {
            updateAdvertising()
            return
        }
        peripheralManager?.removeAllServices()
        defaults.set(Self.gattVersion, forKey: "gattVersion")
        let port = CBMutableCharacteristic(type: CBUUID(string: PumpUUID.sakePort),
                                           properties: [.write, .notify], value: nil, permissions: [.writeable])
        let sakeService = CBMutableService(type: CBUUID(string: PumpUUID.sakeService), primary: true)
        sakeService.characteristics = [port]
        sakePort = port

        // Values are served dynamically in didReceiveRead, so every read gets logged.
        let order = ["2A29", "2A24", "2A25", "2A27", "2A26", "2A28", "2A23", "2A50", "2A2A"]
        let dis = CBMutableService(type: CBUUID(string: PumpUUID.appDeviceInfoService), primary: true)
        dis.characteristics = order.map {
            CBMutableCharacteristic(type: CBUUID(string: $0), properties: [.read], value: nil, permissions: [.readable])
        }
        // Same order as the official app: SAKE service first, then device information.
        peripheralManager?.add(sakeService)
        peripheralManager?.add(dis)
        log.add("GATT-Server registriert (SAKE 0xFE82, DIS 0x0900)")
    }

    private func updateAdvertising() {
        guard peripheralManager?.state == .poweredOn, sakePort != nil else { return }
        peripheralManager?.stopAdvertising()
        if case .blocked = phase { return }
        if pairingMode {
            peripheralManager?.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: PumpUUID.sakeService)],
                CBAdvertisementDataLocalNameKey: "Mobile \(advertisedName)",
            ])
            if phase != .connected { phase = .pairing }
        } else if phase != .connected {
            // Reconnects work via the bond (IRK) as well, see lab notebook capture 2.
            peripheralManager?.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: PumpUUID.reconnectService)],
            ])
            if phase == .pairing { phase = .waitingForPump }
        }
    }

    private func send(_ data: [UInt8]) {
        outbox.append(Data(data))
        flushOutbox()
    }

    private func flushOutbox() {
        guard let port = sakePort, let central = pumpCentral else { return }
        while let next = outbox.first {
            guard peripheralManager?.updateValue(next, for: port, onSubscribedCentrals: [central]) == true else { return }
            outbox.removeFirst()
        }
    }

    private func handleSake(_ value: Data) {
        guard let db = keyDatabase else { return }
        if sake == nil || sake?.isComplete == true { sake = SakeServer(keyDatabase: db) }
        do {
            let stage = sake?.stage ?? 0
            if let reply = try sake?.handle([UInt8](value)) {
                log.add("SAKE Stufe \(stage) → \(sake?.stage ?? 0)")
                send(reply)
            } else if sake?.isComplete == true {
                log.add("SAKE-Handshake abgeschlossen")
                crypt = sake?.crypt
                decryptFailures = 0
                if let crypt { SessionStore.save(crypt) }
                if let id = pumpCentral?.identifier { UserDefaults.standard.set(id.uuidString, forKey: "pumpID") }
                UserDefaults.standard.set(true, forKey: "isPaired")
                isPaired = true
                waitingSince = nil
                if pairingMode { setPairingMode(false) }
                connectAsGattClient()
            }
        } catch {
            log.add("SAKE-Fehler: \(error)", .error)
            sake = nil
        }
    }

    // MARK: - Central side (GATT client on the pump)

    private func connectAsGattClient() {
        phase = .connecting
        guard centralManager?.state == .poweredOn else { log.add("Central nicht bereit", .warning); return }
        var candidates: [CBPeripheral] = []
        if let id = pumpCentral?.identifier {
            candidates = centralManager?.retrievePeripherals(withIdentifiers: [id]) ?? []
        }
        if candidates.isEmpty {
            candidates = centralManager?.retrieveConnectedPeripherals(withServices: [
                CBUUID(string: PumpUUID.cgmService), CBUUID(string: PumpUUID.iddService),
            ]) ?? []
        }
        log.add("GATT-Client: \(candidates.count) Kandidat(en) gefunden")
        guard let peripheral = candidates.first else {
            retrieveAttempts += 1
            if retrieveAttempts <= 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.connectAsGattClient() }
            } else {
                phase = .failed("Pumpe nicht als GATT-Server erreichbar")
                log.add("Pumpe nicht als GATT-Server gefunden", .error)
            }
            return
        }
        retrieveAttempts = 0
        pump = peripheral
        peripheral.delegate = self
        if peripheral.state == .connected {
            startDiscovery(peripheral)
        } else {
            centralManager?.connect(peripheral)
        }
    }

    private func startDiscovery(_ peripheral: CBPeripheral) {
        resetClientState()
        peripheral.discoverServices([
            CBUUID(string: PumpUUID.deviceInfoService), CBUUID(string: PumpUUID.iddService),
            CBUUID(string: PumpUUID.cgmService), CBUUID(string: PumpUUID.batteryService),
        ])
    }

    /// After iOS relaunched the app in the background, the pump may still be connected
    /// with the old SAKE session. Continue with the saved cipher instead of losing data.
    /// IMPORTANT: the app never initiates a connection to the pump itself. The pump is the
    /// central of the bonded link; a connection started by the iPhone is a second, unencrypted
    /// link on which the pump neither encrypts nor starts SAKE, and it keeps the pump from
    /// reconnecting properly (lab notebook 2026-10-15). We only attach to the pump's link.
    private static let linkFixVersion = 1

    private func resumeSavedSession() {
        guard crypt == nil, sake == nil else { return }
        let savedID = UserDefaults.standard.string(forKey: "pumpID").flatMap(UUID.init(uuidString:))
        let known = pump ?? savedID.flatMap { centralManager?.retrievePeripherals(withIdentifiers: [$0]).first }

        // One-time cleanup after the build that issued own connection requests: drop a
        // pending/own connection and ask the pump for a fresh handshake on its own link.
        if UserDefaults.standard.integer(forKey: "linkFixVersion") < Self.linkFixVersion {
            UserDefaults.standard.set(Self.linkFixVersion, forKey: "linkFixVersion")
            if let known { centralManager?.cancelPeripheralConnection(known) }
            pump = nil
            SessionStore.clear()
            log.add("Eigene Verbindungsanfrage zur Pumpe verworfen, warte auf Neuverbindung durch die Pumpe", .warning)
            requestNewHandshakeIfLinked()
            return
        }
        // A pending connection request from an earlier run: cancel it.
        if let known, known.state == .connecting {
            centralManager?.cancelPeripheralConnection(known)
            log.add("Hängende Verbindungsanfrage abgebrochen")
        }
        guard let saved = SessionStore.load(), let peripheral = known, peripheral.state == .connected else {
            SessionStore.clear()
            requestNewHandshakeIfLinked()
            return
        }
        crypt = saved
        pump = peripheral
        peripheral.delegate = self
        log.add("Setze gespeicherte Sitzung fort (Pumpe verbunden)")
        phase = .connecting
        startDiscovery(peripheral)
    }

    /// The pump is linked (restored by iOS) but we have no session, e.g. after an app update.
    /// Re-registering our GATT services makes iOS send "Service Changed"; the pump then
    /// rediscovers and subscribes to the SAKE port again, which starts a new handshake.
    /// This only changes our own GATT table, never anything on the pump.
    private var didRequestHandshake = false
    private func requestNewHandshakeIfLinked() {
        guard !didRequestHandshake, isPaired || store.lastDataAt != nil else { return }
        if !isPaired {
            // Paired with an older build that did not store the flag yet.
            UserDefaults.standard.set(true, forKey: "isPaired")
            isPaired = true
        }
        waitingSince = Date()
        if phase != .connected { phase = .waitingForPump }
        didRequestHandshake = true
        guard sakePort != nil else {
            // Services are registered fresh anyway (first setup after launch).
            log.add("Keine gespeicherte Sitzung, warte auf Handshake der Pumpe")
            return
        }
        log.add("Keine gespeicherte Sitzung, fordere neuen Handshake an (GATT-Dienste neu registrieren)")
        sakePort = nil
        UserDefaults.standard.set(0, forKey: "gattVersion")
        if peripheralManager?.state == .poweredOn { setUpServices() }
    }

    private func resetClientState() {
        characteristics = [:]
        serialVerified = false
        operations = []
        current = nil
        operationTimer?.invalidate()
        sessionStart = nil
        sensorRunHours = nil
        historyBuffer = []
        historyNewestSeq = nil
    }

    private func key(_ service: CBUUID, _ characteristic: CBUUID) -> String {
        "\(service.uuidString.uppercased())|\(characteristic.uuidString.uppercased())"
    }

    private func characteristic(_ service: String, _ uuid: String) -> CBCharacteristic? {
        characteristics[key(CBUUID(string: service), CBUUID(string: uuid))]
    }

    private func allDiscovered() {
        log.add("\(characteristics.count) Merkmale der Pumpe gefunden")
        phase = .verifying
        // Rule 2: before anything else, read the serial number (unencrypted DIS).
        guard let serial = characteristic(PumpUUID.deviceInfoService, PumpUUID.serialNumber) else {
            block("Seriennummer der Pumpe nicht lesbar")
            return
        }
        guardedRead(serial)
        if let fw = characteristic(PumpUUID.deviceInfoService, PumpUUID.firmwareRevision) { guardedRead(fw) }
    }

    private func serialReceived(_ serial: String) {
        pumpSerial = serial
        guard config.devGuard.accepts(serial: serial) else {
            block("DEV_MODE: Pumpe \(serial) ist nicht die Testpumpe")
            return
        }
        serialVerified = true
        waitingSince = nil
        log.add("Pumpe verifiziert (\(config.devGuard.devMode ? "Testpumpe" : "DEV_MODE aus"))")
        phase = .connected
        updateAdvertising()
        for (service, uuid) in [
            (PumpUUID.cgmService, PumpUUID.cgmMeasurement),
            (PumpUUID.cgmService, PumpUUID.recordAccessCP),
            (PumpUUID.iddService, PumpUUID.iddStatusReaderCP),
            (PumpUUID.iddService, PumpUUID.iddStatusChanged),
            (PumpUUID.iddService, PumpUUID.iddHistoryData),
            (PumpUUID.iddService, PumpUUID.recordAccessCP),
            (PumpUUID.iddService, PumpUUID.gstBatteryLevel),
            (PumpUUID.batteryService, PumpUUID.batteryLevel),
        ] {
            if let c = characteristic(service, uuid) { guardedSubscribe(c) }
        }
        scheduleRefresh(force: true)
    }

    private func block(_ reason: String) {
        log.add(reason, .blocked)
        phase = .blocked(reason)
        if let pump { centralManager?.cancelPeripheralConnection(pump) }
        pump = nil
        resetClientState()
        sake = nil
        peripheralManager?.stopAdvertising()
    }

    // MARK: - Guarded access (hard rule 1)

    private func guardedRead(_ c: CBCharacteristic) {
        guard ReadOnlyPolicy.mayRead(c.uuid.uuidString) else {
            log.add("BLOCKIERT: Lesen von \(c.uuid.uuidString) nicht freigegeben", .blocked)
            return
        }
        pump?.readValue(for: c)
    }

    private func guardedSubscribe(_ c: CBCharacteristic) {
        guard ReadOnlyPolicy.maySubscribe(c.uuid.uuidString) else {
            log.add("BLOCKIERT: Abo auf \(c.uuid.uuidString) nicht freigegeben", .blocked)
            return
        }
        pump?.setNotifyValue(true, for: c)
    }

    /// The only place that writes to a pump characteristic.
    @discardableResult
    private func guardedWrite(service: String, characteristic uuid: String, plaintext: [UInt8]) -> Bool {
        guard serialVerified else {
            log.add("BLOCKIERT: Schreiben vor Pumpen-Verifikation", .blocked)
            return false
        }
        let request = WriteRequest(service: CBUUID(string: service).uuidString,
                                   characteristic: CBUUID(string: uuid).uuidString, plaintext: plaintext)
        let decision = ReadOnlyPolicy.check(request)
        guard case .allowed = decision else {
            if case .blocked(let reason) = decision { log.add("BLOCKIERT: \(reason)", .blocked) }
            return false
        }
        guard let c = characteristic(service, uuid), let pump else { return false }
        var payload = plaintext
        if Self.encrypted.contains(c.uuid.uuidString.uppercased()) {
            guard let crypt else { return false }
            do {
                payload = try crypt.encrypt(plaintext)
                SessionStore.save(crypt)
            } catch {
                log.add("Verschlüsselung fehlgeschlagen: \(error)", .error)
                return false
            }
        }
        pump.writeValue(Data(payload), for: c, type: .withResponse)
        return true
    }

    // MARK: - Refresh cycle

    private func scheduleRefresh(force: Bool = false) {
        guard serialVerified else { return }
        // Timers do not fire while iOS suspends the app. Detect a stuck operation by time.
        if let started = currentStartedAt, Date().timeIntervalSince(started) > 20 {
            log.add("Abfrage hängt (\(current.map { "\($0)" } ?? "?")), setze zurück", .warning)
            operations = []
            current = nil
            currentStartedAt = nil
        }
        if current != nil || !operations.isEmpty {
            refreshPending = true
            return
        }
        if !force, Date().timeIntervalSince(lastRefresh) < 50 { return }
        refreshPending = false
        lastRefresh = Date()
        operations = [
            .read(service: PumpUUID.iddService, characteristic: PumpUUID.iddStatus),
            .statusReader(.getInsulinOnBoard),
            .statusReader(.getTherapyAlgorithmStates),
            .statusReader(.getActiveBasalRateDelivery),
            .statusReader(.getTimeInRange),
            .read(service: PumpUUID.batteryService, characteristic: PumpUUID.batteryLevel),
            // GST Battery Level (0x0400) is notify-only on the 780G ("Reading is not permitted").
        ]
        if sessionStart == nil {
            operations.append(.read(service: PumpUUID.cgmService, characteristic: PumpUUID.cgmSessionStartTime))
        }
        if sensorRunHours == nil {
            operations.append(.read(service: PumpUUID.cgmService, characteristic: PumpUUID.cgmSessionRunTime))
        }
        operations.append(.cgmLastRecord)
        // Pump history (boluses, carbs, BG, auto basal, sensor values) every ~5 min.
        if Date().timeIntervalSince(lastHistorySync) > 4 * 60 {
            lastHistorySync = Date()
            historyBuffer = []
            operations.append(.historyLast)
        }
        nextOperation()
    }

    // MARK: - Pump history

    private static let historyChunk: UInt32 = 200
    /// First sync: about three days of history (~700 records per day).
    private static let historyInitialWindow: UInt32 = 2_000

    private var historyLastSeq: UInt32? {
        get { (UserDefaults.standard.object(forKey: "historyLastSeq") as? NSNumber)?.uint32Value }
        set { UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: "historyLastSeq") }
    }

    private var historyReference: (sequence: UInt32, date: Date)? {
        get {
            guard let seq = (UserDefaults.standard.object(forKey: "historyRefSeq") as? NSNumber)?.uint32Value,
                  let date = UserDefaults.standard.object(forKey: "historyRefDate") as? Date else { return nil }
            return (seq, date)
        }
        set {
            UserDefaults.standard.set(newValue.map { NSNumber(value: $0.sequence) }, forKey: "historyRefSeq")
            UserDefaults.standard.set(newValue?.date, forKey: "historyRefDate")
        }
    }

    /// Queues a history read right away (e.g. a pump alert changed), unless one is running.
    private func requestHistoryNow() {
        guard serialVerified else { return }
        let isHistory: (Operation) -> Bool = {
            switch $0 {
            case .historyLast, .historyRange: true
            default: false
            }
        }
        if let current, isHistory(current) { return }
        if operations.contains(where: isHistory) { return }
        lastHistorySync = Date()
        historyBuffer = []
        operations.append(.historyLast)
        if current == nil { nextOperation() }
    }

    /// Bump to re-read the pump history once (e.g. after improving the classification).
    private static let historyVersion = 2

    func migrateHistoryIfNeeded() {
        guard UserDefaults.standard.integer(forKey: "historyVersion") < Self.historyVersion else { return }
        UserDefaults.standard.set(Self.historyVersion, forKey: "historyVersion")
        historyLastSeq = nil
        historyReference = nil
        store.resetTreatments()
        UserDefaults.standard.set(0, forKey: "nsLastTreatment")
        log.add("History wird neu eingelesen (Bolus-Einstufung verbessert)")
    }

    /// After "last record" told us the newest sequence number: queue the missing ranges.
    private func queueHistoryRanges() {
        guard let newest = historyNewestSeq else { return }
        let lower = newest > Self.historyInitialWindow ? newest - Self.historyInitialWindow : 0
        var from = max(lower, (historyLastSeq ?? lower) &+ 1)
        if let last = historyLastSeq, last >= newest { return }
        if from > newest { from = lower }
        log.add("History: lade \(newest - from + 1) Einträge (\(from)…\(newest))")
        var chunks: [Operation] = []
        while from <= newest {
            let to = min(newest, from + Self.historyChunk - 1)
            chunks.append(.historyRange(from: from, to: to))
            from = to + 1
        }
        operations.insert(contentsOf: chunks, at: 0)
    }

    /// Converts the collected records into treatments and sensor values.
    private func processHistory() {
        guard !historyBuffer.isEmpty else { return }
        let records = historyBuffer
        historyBuffer = []
        let (events, reference) = HistoryTimeline.resolve(records, reference: historyReference)
        historyReference = reference
        if let maxSeq = records.map(\.sequence).max() { historyLastSeq = max(historyLastSeq ?? 0, maxSeq) }

        let treatments = Treatment.from(events)
        let auto = treatments.filter { $0.kind == .autoCorrection }.count
        let manual = treatments.filter { $0.kind == .bolus }.count
        let sgv = events.compactMap { e -> GlucoseReading? in
            guard case .sensorGlucose(let mgdl?) = e.event else { return nil }
            return GlucoseReading(date: e.date, mgdl: mgdl, trendMgdlPerMin: nil, sessionOffsetMinutes: nil)
        }
        for e in events {
            if case .annunciation(let id, let type, let status) = e.event {
                AlarmEngine.shared.pumpAlarm(id: id, type: type, status: status, date: e.date)
            }
        }
        let newTreatments = store.addTreatments(treatments)
        let newReadings = store.merge(sgv)
        log.add("History: \(records.count) Einträge, \(newTreatments.count) neue Behandlungen (Boli \(manual), Autokorrekturen \(auto)), \(newReadings.count) Sensorwerte nachgetragen"
                + (reference == nil ? " (noch keine Zeitreferenz)" : ""))
        if !newTreatments.isEmpty || !newReadings.isEmpty { onHistory(newReadings.map(\.date).min()) }
    }

    private func nextOperation() {
        operationTimer?.invalidate()
        current = nil
        currentStartedAt = nil
        while !operations.isEmpty {
            let op = operations.removeFirst()
            if start(op) {
                current = op
                currentStartedAt = Date()
                let timeout: TimeInterval = if case .historyRange = op { 45 } else { 8 }
                operationTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let op = self.current else { return }
                        self.log.add("Zeitüberschreitung: \(op)", .warning)
                        self.nextOperation()
                    }
                }
                return
            }
        }
        // Queue drained (also after a timed-out history range): process collected history.
        if !historyBuffer.isEmpty { processHistory() }
        // Run a refresh that was requested while busy.
        if refreshPending { scheduleRefresh() }
    }

    private func start(_ op: Operation) -> Bool {
        switch op {
        case .read(let service, let uuid):
            guard let c = characteristic(service, uuid) else { return false }
            guardedRead(c)
            return ReadOnlyPolicy.mayRead(c.uuid.uuidString)
        case .statusReader(let opcode):
            return guardedWrite(service: PumpUUID.iddService, characteristic: PumpUUID.iddStatusReaderCP,
                                plaintext: opcode.request)
        case .cgmLastRecord:
            return guardedWrite(service: PumpUUID.cgmService, characteristic: PumpUUID.recordAccessCP,
                                plaintext: [0x01, 0x06])
        case .historyLast:
            return guardedWrite(service: PumpUUID.iddService, characteristic: PumpUUID.recordAccessCP,
                                plaintext: [0x33, 0x69, 0x0F])
        case .historyRange(let from, let to):
            func le(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) } }
            return guardedWrite(service: PumpUUID.iddService, characteristic: PumpUUID.recordAccessCP,
                                plaintext: [0x33, 0x5A, 0x0F] + le(from) + le(to))
        }
    }

    private func finish(_ matches: (Operation) -> Bool) {
        if let op = current, matches(op) { nextOperation() }
    }

    // MARK: - Incoming values

    private func handleValue(_ c: CBCharacteristic, data: [UInt8]) {
        let uuid = c.uuid.uuidString.uppercased()
        let service = c.service?.uuid.uuidString.uppercased() ?? ""
        var plain = data
        // The pump signals new data every ~5 min with a notification on GST Battery Level
        // followed by an indication on IDD Status Changed (capture 2). Any of these starts
        // a refresh, even if the payload cannot be decrypted.
        let isTrigger = uuid == PumpUUID.iddStatusChanged.uppercased() || uuid == PumpUUID.gstBatteryLevel.uppercased()
            || (uuid == PumpUUID.cgmMeasurement.uppercased() && current == nil)
        if Self.encrypted.contains(uuid) {
            guard let crypt else {
                log.add("Keine Sitzung zum Entschlüsseln von \(uuid)", .warning)
                return
            }
            do {
                plain = try crypt.decrypt(data)
                decryptFailures = 0
                SessionStore.save(crypt)
            } catch {
                decryptFailures += 1
                log.add("Entschlüsselung \(uuid) fehlgeschlagen (\(decryptFailures)×): \(error)", .warning)
                if decryptFailures >= 5 {
                    log.add("Sitzung ungültig, warte auf neuen Handshake der Pumpe", .error)
                    self.crypt = nil
                    SessionStore.clear()
                    phase = .failed("Sitzung verloren – die Pumpe verbindet sich neu")
                }
                finish { _ in true }
                if isTrigger { scheduleRefresh() }
                return
            }
        }
        defer { if isTrigger { scheduleRefresh() } }

        switch uuid {
        case PumpUUID.serialNumber:
            serialReceived(String(decoding: plain, as: UTF8.self))
        case PumpUUID.firmwareRevision:
            pumpFirmware = String(decoding: plain, as: UTF8.self)

        case PumpUUID.cgmMeasurement.uppercased():
            do {
                let m = try CGMMeasurement(plain)
                let now = Date()
                var date = now
                // A new sensor record was just measured: if start + offset is off by whole
                // quarter hours, the pump clock was changed (e.g. daylight saving time).
                let isNewRecord = lastLiveOffset.map { $0 != m.timeOffsetMinutes } ?? false
                lastLiveOffset = m.timeOffsetMinutes
                if isNewRecord, let start = sessionStart,
                   let shift = SensorClock.shift(sessionStart: start, offsetMinutes: m.timeOffsetMinutes, now: now) {
                    sessionStart = start.addingTimeInterval(shift)
                    let previous = sessionStartShift ?? (reported: start, shift: 0)
                    sessionStartShift = (previous.reported, previous.shift + shift)
                    store.update { $0.sensorStart = start.addingTimeInterval(shift) }
                    updateSensorExpiry()
                    log.add("Sensorstart um \(Int(shift / 60)) min korrigiert (Pumpenuhr verstellt, z. B. Zeitumstellung)", .warning)
                }
                if let start = sessionStart {
                    let candidate = start.addingTimeInterval(Double(m.timeOffsetMinutes) * 60)
                    if candidate <= now.addingTimeInterval(300), candidate > now.addingTimeInterval(-11 * 24 * 3600) { date = candidate }
                }
                // SG values outside 40…400 are sensor states, not glucose values.
                if m.glucoseMgdl >= 40, m.glucoseMgdl <= 400 {
                    store.add(GlucoseReading(date: date, mgdl: Int(m.glucoseMgdl.rounded()),
                                             trendMgdlPerMin: m.trendMgdlPerMin, sessionOffsetMinutes: m.timeOffsetMinutes))
                    onData()
                }
                log.add("SG \(Int(m.glucoseMgdl)) mg/dL, Trend \(m.trendMgdlPerMin.map { String($0) } ?? "–")")
            } catch {
                log.add("CGM-Messung nicht lesbar: \(error) \(plain.hex)", .warning)
            }

        case PumpUUID.recordAccessCP:
            if service == PumpUUID.cgmService {
                log.add("CGM-RACP-Antwort \(plain.hex)")
                finish { if case .cgmLastRecord = $0 { true } else { false } }
            } else if service == PumpUUID.iddService.uppercased() {
                // IDS RACP response: 0F 0F <request opcode> <code>; F0 = success, 06 = no records.
                let ok = plain.count >= 4 && plain[3] == 0xF0
                if !ok { log.add("History-RACP-Antwort \(plain.hex)", .warning) }
                switch current {
                case .historyLast?:
                    queueHistoryRanges()
                    finish { _ in true }
                case .historyRange?:
                    finish { _ in true }
                    // Process once, after the last range (which may already be running now).
                    let isRange: (Operation?) -> Bool = { if case .historyRange? = $0 { true } else { false } }
                    if !operations.contains(where: { isRange($0) }), !isRange(current) {
                        processHistory()
                    }
                default:
                    break
                }
            }

        case PumpUUID.iddHistoryData.uppercased():
            do {
                let record = try HistoryRecord(plain)
                if case .historyLast = current {
                    historyNewestSeq = record.sequence
                } else {
                    historyBuffer.append(record)
                }
            } catch {
                log.add("History-Eintrag nicht lesbar: \(plain.hex)", .warning)
            }

        case PumpUUID.iddStatusReaderCP.uppercased():
            handleStatusReader(plain)

        case PumpUUID.iddStatusChanged.uppercased():
            let flags = StatusChangedFlags(plain)
            if flags?.contains(.annunciation) == true {
                // A pump alert changed: read the history right away instead of in ≤5 min.
                log.add("Pumpe meldet geänderte Alarme")
                requestHistoryNow()
            } else {
                log.add("Pumpe meldet Statusänderung")
            }

        case PumpUUID.iddStatus.uppercased():
            if let s = try? PumpStatus(plain) {
                store.update { $0.status = s }
                AlarmEngine.shared.sensorStatus(s)
                onData()
            } else { log.add("IDD-Status nicht lesbar: \(plain.hex)", .warning) }
            finish { if case .read = $0 { true } else { false } }

        case PumpUUID.batteryLevel:
            if let b = plain.first { store.update { $0.pumpBatteryPercent = Int(b) } }
            finish { if case .read(_, let c) = $0 { c == PumpUUID.batteryLevel } else { false } }

        case PumpUUID.gstBatteryLevel.uppercased():
            if let b = plain.first { store.update { $0.transmitterBatteryPercent = Int(b) } }
            finish { if case .read(_, let c) = $0 { c == PumpUUID.gstBatteryLevel } else { false } }

        case PumpUUID.cgmSessionRunTime:
            // u16 expected session run time in hours + E2E-CRC (CGMS).
            if plain.count == 4, Checksums.hasValidE2ECRC(plain) {
                let hours = Int(plain[0]) | Int(plain[1]) << 8
                sensorRunHours = hours
                updateSensorExpiry()
                log.add("Sensorlaufzeit \(hours) h")
            } else { log.add("Sensorlaufzeit nicht lesbar: \(plain.hex)", .warning) }
            finish { if case .read = $0 { true } else { false } }

        case PumpUUID.cgmSessionStartTime:
            if let t = try? CGMSessionStartTime(plain), let reported = t.date() {
                if let s = sessionStartShift, s.reported != reported { sessionStartShift = nil }
                let date = reported.addingTimeInterval(sessionStartShift?.shift ?? 0)
                sessionStart = date
                store.update { $0.sensorStart = date }
                updateSensorExpiry()
                log.add("Sensorstart \(date.formatted())")
            } else { log.add("Sensorstart nicht lesbar: \(plain.hex)", .warning) }
            finish { if case .read = $0 { true } else { false } }

        default:
            log.add("Wert von \(uuid): \(plain.hex)")
        }
    }

    private func updateSensorExpiry() {
        guard let start = sessionStart, let hours = sensorRunHours else { return }
        let end = start.addingTimeInterval(Double(hours) * 3600)
        store.update {
            $0.sensorEnd = end
            $0.sensorExpiresInMinutes = Int(end.timeIntervalSinceNow / 60)
        }
    }

    private func handleStatusReader(_ plain: [UInt8]) {
        guard let opcode = statusReaderResponseOpcode(plain) else { return }
        do {
            switch opcode {
            case StatusReaderOpcode.getInsulinOnBoard.responseOpcode:
                let v = try InsulinOnBoard(plain); store.update { $0.iob = v }
            case StatusReaderOpcode.getTherapyAlgorithmStates.responseOpcode:
                let v = try TherapyAlgorithmStates(plain); store.update { $0.algorithm = v }
            case StatusReaderOpcode.getActiveBasalRateDelivery.responseOpcode:
                let v = try ActiveBasalRate(plain); store.update { $0.basal = v }
            case StatusReaderOpcode.getTimeInRange.responseOpcode:
                let v = try TimeInRange(plain); store.update { $0.timeInRange = v }
            default:
                log.add(String(format: "SRCP-Antwort 0x%04x: %@", opcode, plain.hex), .warning)
            }
            onData()
        } catch {
            log.add("SRCP-Antwort nicht lesbar: \(error) \(plain.hex)", .warning)
        }
        finish { if case .statusReader = $0 { true } else { false } }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension PumpLink: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated {
            log.add("Peripheral-Status: \(peripheral.state.rawValue)")
            if peripheral.state == .poweredOn {
                if case .bluetoothOff = phase { phase = .waitingForPump }
                setUpServices()
            } else {
                phase = .bluetoothOff
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] ?? []
            for service in services {
                for c in service.characteristics ?? [] where c.uuid == CBUUID(string: PumpUUID.sakePort) {
                    sakePort = c as? CBMutableCharacteristic
                }
            }
            log.add("Peripheral wiederhergestellt (\(services.count) Services)")
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            if let error { log.add("Service \(service.uuid) nicht registriert: \(error)", .error) }
            else { log.add("Service \(service.uuid) registriert") }
            updateAdvertising()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == CBUUID(string: PumpUUID.sakePort) else { return }
            log.add("Pumpe hat SAKE abonniert, starte Handshake (MTU \(central.maximumUpdateValueLength))")
            pumpCentral = central
            peripheral.setDesiredConnectionLatency(.low, for: central)
            resetClientState()
            sake = nil
            crypt = nil
            SessionStore.clear()
            outbox = []
            phase = .handshake
            send([UInt8](repeating: 0, count: SakeServer.messageSize))
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == CBUUID(string: PumpUUID.sakePort) else { return }
            log.add("Pumpe hat SAKE-Abo beendet (Verbindung getrennt?)", .warning)
            pumpCentral = nil
            if case .blocked = phase { return }
            phase = .waitingForPump
            updateAdvertising()
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        MainActor.assumeIsolated {
            guard let value = deviceInfo[request.characteristic.uuid] else {
                log.add("Pumpe liest unbekanntes Merkmal \(request.characteristic.uuid.uuidString)", .warning)
                peripheral.respond(to: request, withResult: .readNotPermitted)
                return
            }
            guard request.offset <= value.count else {
                peripheral.respond(to: request, withResult: .invalidOffset)
                return
            }
            request.value = value.subdata(in: request.offset..<value.count)
            peripheral.respond(to: request, withResult: .success)
            if request.offset == 0 {
                log.add("Pumpe liest \(request.characteristic.uuid.uuidString): \"\(String(decoding: value, as: UTF8.self))\"")
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        MainActor.assumeIsolated {
            for request in requests {
                guard request.characteristic.uuid == CBUUID(string: PumpUUID.sakePort), let value = request.value else {
                    log.add("Pumpe schreibt auf \(request.characteristic.uuid.uuidString), abgelehnt", .warning)
                    peripheral.respond(to: request, withResult: .requestNotSupported)
                    continue
                }
                if pumpCentral == nil { pumpCentral = request.central }
                peripheral.respond(to: request, withResult: .success)
                if case .blocked = phase { continue }
                handleSake(value)
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                log.add("Advertising fehlgeschlagen: \(error.localizedDescription)", .error)
            } else {
                log.add(pairingMode ? "Advertising: Kopplung (FE82, Mobile \(advertisedName))" : "Advertising: Wiederverbindung (FE81)")
            }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { flushOutbox() }
    }
}

// MARK: - CBCentralManagerDelegate

extension PumpLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            log.add("Central-Status: \(central.state.rawValue)")
            if central.state == .poweredOn { resumeSavedSession() }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
            log.add("Central wiederhergestellt (\(peripherals.count) Geräte)")
            let savedID = UserDefaults.standard.string(forKey: "pumpID")
            if let p = peripherals.first(where: { $0.identifier.uuidString == savedID }) ?? peripherals.first {
                pump = p
                p.delegate = self
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            log.add("GATT-Client verbunden mit \(peripheral.name ?? "Pumpe")")
            // A handshake is running: discovery starts once it completed.
            if phase == .handshake || crypt == nil {
                log.add("Warte auf SAKE-Handshake")
                return
            }
            startDiscovery(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            log.add("GATT-Client-Verbindung fehlgeschlagen: \(error?.localizedDescription ?? "?")", .error)
            phase = .failed("Verbindung zur Pumpe fehlgeschlagen")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            log.add("Pumpe getrennt\(error.map { ": \($0.localizedDescription)" } ?? "")", .warning)
            resetClientState()
            if case .blocked = phase { pump = nil; return }
            // No reconnect from our side: the pump reconnects to us (see linkFixVersion).
            pump = nil
            phase = .waitingForPump
            updateAdvertising()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension PumpLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let services = peripheral.services ?? []
            pendingDiscovery = services.count
            for s in services { peripheral.discoverCharacteristics(nil, for: s) }
            if services.isEmpty { log.add("Keine Services gefunden \(error?.localizedDescription ?? "")", .error) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            for c in service.characteristics ?? [] { characteristics[key(service.uuid, c.uuid)] = c }
            pendingDiscovery -= 1
            if pendingDiscovery == 0 { allDiscovered() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                log.add("Lesefehler \(characteristic.uuid.uuidString): \(error.localizedDescription)", .warning)
                finish { _ in true }
                return
            }
            guard let value = characteristic.value else { return }
            handleValue(characteristic, data: [UInt8](value))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error {
                log.add("Schreibfehler \(characteristic.uuid.uuidString): \(error.localizedDescription)", .warning)
                finish { _ in true }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            if let error { log.add("Abo \(characteristic.uuid.uuidString) fehlgeschlagen: \(error.localizedDescription)", .warning) }
        }
    }
}
