// SPDX-License-Identifier: GPL-3.0-or-later
// BLE link to the pump.
//
// Roles (see docs/landscape.md): the pump is the BLE central and SAKE client, the phone
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
            case .bluetoothOff: "Bluetooth aus"
            case .waitingForPump: "Warte auf Pumpe"
            case .pairing: "Kopplungsmodus"
            case .handshake: "Handshake läuft"
            case .connecting: "Verbinde"
            case .verifying: "Prüfe Pumpe"
            case .connected: "Verbunden"
            case .blocked: "Blockiert"
            case .failed: "Fehler"
            }
        }
    }

    @Published private(set) var phase: Phase = .waitingForPump
    @Published private(set) var pairingMode = false
    @Published private(set) var pumpSerial: String?
    @Published private(set) var pumpFirmware: String?

    let advertisedName: String

    private let config: AppConfig
    private let store: DataStore
    private let log: EventLog
    private let onData: () -> Void

    private var peripheralManager: CBPeripheralManager!
    private var centralManager: CBCentralManager!
    private var sakePort: CBMutableCharacteristic?
    private var sake: SakeServer?
    private var pumpCentral: CBCentral?
    private var outbox: [Data] = []

    private var pump: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var pendingDiscovery = 0
    private var serialVerified = false
    private var sessionStart: Date?
    private var operations: [Operation] = []
    private var current: Operation?
    private var operationTimer: Timer?
    private var lastRefresh: Date = .distantPast
    private var retrieveAttempts = 0

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

        var description: String {
            switch self {
            case .read(_, let c): "Lesen \(c)"
            case .statusReader(let op): "SRCP \(op)"
            case .cgmLastRecord: "CGM letzter Wert"
            }
        }
    }

    init(config: AppConfig, store: DataStore, log: EventLog, onData: @escaping () -> Void) {
        self.config = config
        self.store = store
        self.log = log
        self.onData = onData
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "advertisedName") {
            advertisedName = name
        } else {
            advertisedName = String(format: "%06d", Int.random(in: 0...999_999))
            defaults.set(advertisedName, forKey: "advertisedName")
        }
        super.init()
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

    func refreshNow() {
        guard phase == .connected else { return }
        scheduleRefresh(force: true)
    }

    // MARK: - Peripheral side (GATT server, SAKE)

    private func setUpServices() {
        guard sakePort == nil else { updateAdvertising(); return }
        let dis = CBMutableService(type: CBUUID(string: PumpUUID.appDeviceInfoService), primary: true)
        func ro(_ uuid: String, _ value: Data) -> CBMutableCharacteristic {
            CBMutableCharacteristic(type: CBUUID(string: uuid), properties: [.read], value: value, permissions: [.readable])
        }
        dis.characteristics = [
            ro("2A29", Data("openMinipump".utf8)),
            ro("2A24", Data("iPhone".utf8)),
            ro("2A25", Data(advertisedName.utf8)),
            ro("2A27", Data("1.0".utf8)),
            ro("2A26", Data("1.0".utf8)),
            ro("2A28", Data("0.1.0".utf8)),
            ro("2A23", Data(count: 8)),
            ro("2A50", Data(count: 7)),
        ]
        let port = CBMutableCharacteristic(type: CBUUID(string: PumpUUID.sakePort),
                                           properties: [.write, .notify], value: nil, permissions: [.writeable])
        let sakeService = CBMutableService(type: CBUUID(string: PumpUUID.sakeService), primary: true)
        sakeService.characteristics = [port]
        sakePort = port
        peripheralManager.add(dis)
        peripheralManager.add(sakeService)
        log.add("GATT-Server registriert (DIS 0x0900, SAKE 0xFE82)")
    }

    private func updateAdvertising() {
        guard peripheralManager.state == .poweredOn, sakePort != nil else { return }
        peripheralManager.stopAdvertising()
        if case .blocked = phase { return }
        if pairingMode {
            peripheralManager.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: PumpUUID.sakeService)],
                CBAdvertisementDataLocalNameKey: "Mobile \(advertisedName)",
            ])
            if phase != .connected { phase = .pairing }
        } else if phase != .connected {
            // Reconnects work via the bond (IRK) as well, see lab notebook capture 2.
            peripheralManager.startAdvertising([
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
            guard peripheralManager.updateValue(next, for: port, onSubscribedCentrals: [central]) else { return }
            outbox.removeFirst()
        }
    }

    private func handleSake(_ value: Data) {
        guard let db = config.keyDatabase else { return }
        if sake == nil || sake?.isComplete == true { sake = SakeServer(keyDatabase: db) }
        do {
            if let reply = try sake?.handle([UInt8](value)) {
                send(reply)
            } else if sake?.isComplete == true {
                log.add("SAKE-Handshake abgeschlossen")
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
        guard centralManager.state == .poweredOn else { log.add("Central nicht bereit", .warning); return }
        var candidates: [CBPeripheral] = []
        if let id = pumpCentral?.identifier {
            candidates = centralManager.retrievePeripherals(withIdentifiers: [id])
        }
        if candidates.isEmpty {
            candidates = centralManager.retrieveConnectedPeripherals(withServices: [
                CBUUID(string: PumpUUID.cgmService), CBUUID(string: PumpUUID.iddService),
            ])
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
        centralManager.connect(peripheral)
    }

    private func resetClientState() {
        characteristics = [:]
        serialVerified = false
        operations = []
        current = nil
        operationTimer?.invalidate()
        sessionStart = nil
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
        log.add("Pumpe verifiziert (\(config.devGuard.devMode ? "Testpumpe" : "DEV_MODE aus"))")
        phase = .connected
        updateAdvertising()
        for (service, uuid) in [
            (PumpUUID.cgmService, PumpUUID.cgmMeasurement),
            (PumpUUID.cgmService, PumpUUID.recordAccessCP),
            (PumpUUID.iddService, PumpUUID.iddStatusReaderCP),
            (PumpUUID.iddService, PumpUUID.iddStatusChanged),
        ] {
            if let c = characteristic(service, uuid) { guardedSubscribe(c) }
        }
        scheduleRefresh(force: true)
    }

    private func block(_ reason: String) {
        log.add(reason, .blocked)
        phase = .blocked(reason)
        if let pump { centralManager.cancelPeripheralConnection(pump) }
        pump = nil
        resetClientState()
        sake = nil
        peripheralManager.stopAdvertising()
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
            guard let crypt = sake?.crypt else { return false }
            do { payload = try crypt.encrypt(plaintext) } catch {
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
        if !force, Date().timeIntervalSince(lastRefresh) < 45 { return }
        if current != nil || !operations.isEmpty { return }
        lastRefresh = Date()
        operations = [
            .read(service: PumpUUID.iddService, characteristic: PumpUUID.iddStatus),
            .statusReader(.getInsulinOnBoard),
            .statusReader(.getTherapyAlgorithmStates),
            .statusReader(.getActiveBasalRateDelivery),
            .statusReader(.getTimeInRange),
            .read(service: PumpUUID.batteryService, characteristic: PumpUUID.batteryLevel),
            .read(service: PumpUUID.iddService, characteristic: PumpUUID.gstBatteryLevel),
            .read(service: PumpUUID.cgmService, characteristic: PumpUUID.sensorExpiration),
        ]
        if sessionStart == nil {
            operations.append(.read(service: PumpUUID.cgmService, characteristic: PumpUUID.cgmSessionStartTime))
        }
        operations.append(.cgmLastRecord)
        nextOperation()
    }

    private func nextOperation() {
        operationTimer?.invalidate()
        current = nil
        while !operations.isEmpty {
            let op = operations.removeFirst()
            if start(op) {
                current = op
                operationTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, let op = self.current else { return }
                        self.log.add("Zeitüberschreitung: \(op)", .warning)
                        self.nextOperation()
                    }
                }
                return
            }
        }
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
        if Self.encrypted.contains(uuid) {
            guard let crypt = sake?.crypt else { return }
            do { plain = try crypt.decrypt(data) } catch {
                log.add("Entschlüsselung \(uuid) fehlgeschlagen: \(error)", .warning)
                finish { _ in true }
                return
            }
        }

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
                if let start = sessionStart {
                    let candidate = start.addingTimeInterval(Double(m.timeOffsetMinutes) * 60)
                    if candidate <= now.addingTimeInterval(300), candidate > now.addingTimeInterval(-24 * 3600) { date = candidate }
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
            log.add("RACP-Antwort \(plain.hex)")
            if service == PumpUUID.cgmService { finish { if case .cgmLastRecord = $0 { true } else { false } } }

        case PumpUUID.iddStatusReaderCP.uppercased():
            handleStatusReader(plain)

        case PumpUUID.iddStatusChanged.uppercased():
            log.add("Pumpe meldet Statusänderung")
            scheduleRefresh()

        case PumpUUID.iddStatus.uppercased():
            if let s = try? PumpStatus(plain) {
                store.update { $0.status = s }
                onData()
            } else { log.add("IDD-Status nicht lesbar: \(plain.hex)", .warning) }
            finish { if case .read = $0 { true } else { false } }

        case PumpUUID.batteryLevel:
            if let b = plain.first { store.update { $0.pumpBatteryPercent = Int(b) } }
            finish { if case .read = $0 { true } else { false } }

        case PumpUUID.gstBatteryLevel.uppercased():
            if let b = plain.first { store.update { $0.transmitterBatteryPercent = Int(b) } }
            finish { if case .read = $0 { true } else { false } }

        case PumpUUID.sensorExpiration.uppercased():
            if plain.count >= 2 {
                let minutes = Int(plain[0]) | Int(plain[1]) << 8
                store.update { $0.sensorExpiresInMinutes = minutes }
            }
            finish { if case .read = $0 { true } else { false } }

        case PumpUUID.cgmSessionStartTime:
            if let t = try? CGMSessionStartTime(plain), let date = t.date() {
                sessionStart = date
                store.update { $0.sensorStart = date }
                log.add("Sensorstart \(date.formatted())")
            } else { log.add("Sensorstart nicht lesbar: \(plain.hex)", .warning) }
            finish { if case .read = $0 { true } else { false } }

        default:
            log.add("Wert von \(uuid): \(plain.hex)")
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

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        MainActor.assumeIsolated {
            for request in requests {
                guard request.characteristic.uuid == CBUUID(string: PumpUUID.sakePort), let value = request.value else {
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

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { flushOutbox() }
    }
}

// MARK: - CBCentralManagerDelegate

extension PumpLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { log.add("Central-Status: \(central.state.rawValue)") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
            log.add("Central wiederhergestellt (\(peripherals.count) Geräte)")
            // The pump starts a new SAKE handshake after every reconnect; we attach then.
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            log.add("GATT-Client verbunden mit \(peripheral.name ?? "Pumpe")")
            resetClientState()
            peripheral.discoverServices([
                CBUUID(string: PumpUUID.deviceInfoService), CBUUID(string: PumpUUID.iddService),
                CBUUID(string: PumpUUID.cgmService), CBUUID(string: PumpUUID.batteryService),
            ])
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
            pump = nil
            if case .blocked = phase { return }
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
