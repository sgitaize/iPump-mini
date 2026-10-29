// SPDX-License-Identifier: GPL-3.0-or-later
// BLE link to the pump (Android port of apps/ios/OpenMinipump/BLE/PumpLink.swift).
//
// Roles (see docs/internal/landscape.md): the pump is the BLE central and SAKE client, the phone
// is the BLE peripheral and SAKE server. After the SAKE handshake the phone additionally acts as
// GATT client on the same link to read the pump's services.
//
// HARD RULE 1: every write towards the pump goes through `guardedWrite`, which asks
// MiniMedKit.ReadOnlyPolicy. There is no other code path that writes a pump characteristic.
// Enabling notifications (CCCD) goes through `guardedSubscribe`, reads through `guardedRead`.
//
// The app never initiates a connection to the pump (lab notebook 2026-10-15): the GATT client is
// only opened while the pump is connected to our GATT server, so Android attaches it to the
// pump's existing link instead of creating a second one.
//
// Threading: all state lives on the main thread. Android BLE callbacks arrive on binder threads
// and are posted to the main looper with a copy of their data.
package de.sgitaize.openminipump.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import de.sgitaize.minimedkit.ActiveBasalRate
import de.sgitaize.minimedkit.CgmMeasurement
import de.sgitaize.minimedkit.CgmSessionStartTime
import de.sgitaize.minimedkit.SensorClock
import de.sgitaize.minimedkit.Checksums
import de.sgitaize.minimedkit.GlucoseReading
import de.sgitaize.minimedkit.HistoryEvent
import de.sgitaize.minimedkit.HistoryRecord
import de.sgitaize.minimedkit.HistoryReference
import de.sgitaize.minimedkit.HistoryTimeline
import de.sgitaize.minimedkit.InsulinOnBoard
import de.sgitaize.minimedkit.KeyDatabase
import de.sgitaize.minimedkit.PolicyDecision
import de.sgitaize.minimedkit.PumpStatus
import de.sgitaize.minimedkit.PumpUuid
import de.sgitaize.minimedkit.ReadOnlyPolicy
import de.sgitaize.minimedkit.SakeServer
import de.sgitaize.minimedkit.SeqCrypt
import de.sgitaize.minimedkit.StatusChangedFlags
import de.sgitaize.minimedkit.StatusReaderOpcode
import de.sgitaize.minimedkit.TherapyAlgorithmStates
import de.sgitaize.minimedkit.TimeInRange
import de.sgitaize.minimedkit.Treatment
import de.sgitaize.minimedkit.WriteRequest
import de.sgitaize.minimedkit.bytesOf
import de.sgitaize.minimedkit.le32
import de.sgitaize.minimedkit.statusReaderResponseOpcode
import de.sgitaize.minimedkit.toHex
import de.sgitaize.openminipump.AppConfig
import de.sgitaize.openminipump.DataStore
import de.sgitaize.openminipump.EventLog
import de.sgitaize.openminipump.Prefs
import de.sgitaize.openminipump.R
import de.sgitaize.openminipump.alarms.AlarmEngine
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

@SuppressLint("MissingPermission")
class PumpLink(
    private val context: Context,
    private val config: AppConfig,
    private val prefs: Prefs,
    private val store: DataStore,
    private val log: EventLog,
    private val alarms: AlarmEngine,
    private val onData: () -> Unit,
    /** New history data was merged; argument is the oldest newly added sensor value. */
    private val onHistory: (Instant?) -> Unit,
) {
    sealed class Phase {
        object BluetoothOff : Phase()
        object WaitingForPump : Phase()
        object Pairing : Phase()
        object Handshake : Phase()
        object Connecting : Phase()
        object Verifying : Phase()
        object Connected : Phase()
        data class Blocked(val reason: String) : Phase()
        data class Failed(val reason: String) : Phase()

        val labelRes: Int
            get() = when (this) {
                BluetoothOff -> R.string.phase_bluetooth_off
                WaitingForPump -> R.string.phase_waiting
                Pairing -> R.string.phase_pairing
                Handshake -> R.string.phase_handshake
                Connecting -> R.string.phase_connecting
                Verifying -> R.string.phase_verifying
                Connected -> R.string.phase_connected
                is Blocked -> R.string.phase_blocked
                is Failed -> R.string.phase_failed
            }
    }

    private val _phase = MutableStateFlow<Phase>(Phase.WaitingForPump)
    val phase: StateFlow<Phase> = _phase
    private val _pairingMode = MutableStateFlow(false)
    val pairingMode: StateFlow<Boolean> = _pairingMode
    private val _pumpSerial = MutableStateFlow<String?>(null)
    val pumpSerial: StateFlow<String?> = _pumpSerial
    private val _pumpFirmware = MutableStateFlow<String?>(null)
    val pumpFirmware: StateFlow<String?> = _pumpFirmware
    /** True once a pump was paired with this app; the UI then shows "waiting" instead of "pair". */
    private val _isPaired = MutableStateFlow(prefs.isPaired)
    val isPaired: StateFlow<Boolean> = _isPaired
    /** Set while waiting for the pump to reconnect without a session (UI hint after a while). */
    private val _waitingSince = MutableStateFlow<Instant?>(null)
    val waitingSince: StateFlow<Instant?> = _waitingSince
    private val _keyDatabase = MutableStateFlow(config.keyDatabase)
    val keyDatabase: StateFlow<KeyDatabase?> = _keyDatabase

    val advertisedName: String = prefs.advertisedName.ifEmpty {
        "%06d".format((0..999_999).random()).also { prefs.advertisedName = it }
    }

    private val main = Handler(Looper.getMainLooper())
    private val sessions = SessionStore(context)
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? get() = manager.adapter

    private var started = false
    private var demo = false

    // Peripheral side (GATT server, SAKE)
    private var server: BluetoothGattServer? = null
    private var sakePort: BluetoothGattCharacteristic? = null
    private val pendingServices = ArrayDeque<BluetoothGattService>()
    private var servicesReady = false
    private var advertiseCallback: AdvertiseCallback? = null
    private var advertisingMode: String? = null
    private var sake: SakeServer? = null
    private var pumpDevice: BluetoothDevice? = null
    private val outbox = ArrayDeque<ByteArray>()
    private var notifyInFlight = false

    // Central side (GATT client on the pump)
    private var gatt: BluetoothGatt? = null
    private val characteristics = mutableMapOf<String, BluetoothGattCharacteristic>()
    private var serialVerified = false
    private var sessionStart: Instant? = null
    /** Session offset of the last live value; a different one was just measured. */
    private var lastLiveOffset: Int? = null
    private var sensorRunHours: Int? = null
    private var retrieveAttempts = 0

    /** Session cipher after the handshake; persisted so it survives an app restart. */
    private var crypt: SeqCrypt? = null
    private var decryptFailures = 0

    // Refresh cycle (logical operations, one at a time like on iOS)
    private val operations = ArrayDeque<Operation>()
    private var current: Operation? = null
    private var currentStartedAt: Instant? = null
    private var lastRefresh: Instant = Instant.EPOCH
    private var refreshPending = false
    private val operationTimeout = Runnable {
        current?.let { log.warn("Zeitüberschreitung: $it") }
        nextOperation()
    }

    // Pump history (IDD RACP): records collected during one sync run.
    private val historyBuffer = mutableListOf<HistoryRecord>()
    private var historyNewestSeq: Long? = null
    private var lastHistorySync: Instant = Instant.EPOCH

    // Android allows one outstanding GATT operation; commands are queued here.
    private sealed class GattCmd {
        class Read(val c: BluetoothGattCharacteristic) : GattCmd()
        class Write(val c: BluetoothGattCharacteristic, val value: ByteArray) : GattCmd()
        class Subscribe(val c: BluetoothGattCharacteristic) : GattCmd()
    }
    private val gattQueue = ArrayDeque<GattCmd>()
    private var gattBusy = false
    private val gattTimeout = Runnable {
        log.warn("GATT-Befehl ohne Antwort, nächster")
        gattDone()
    }

    private sealed class Operation {
        data class Read(val service: String, val characteristic: String) : Operation() {
            override fun toString() = "Lesen $characteristic"
        }
        data class StatusReader(val opcode: StatusReaderOpcode) : Operation() {
            override fun toString() = "SRCP $opcode"
        }
        object CgmLastRecord : Operation() {
            override fun toString() = "CGM letzter Wert"
        }
        object HistoryLast : Operation() {
            override fun toString() = "History: letzter Eintrag"
        }
        data class HistoryRange(val from: Long, val to: Long) : Operation() {
            override fun toString() = "History $from…$to"
        }
    }

    // MARK: - Lifecycle

    /** Starts Bluetooth (needs the runtime permissions). `bluetooth = false` is demo mode. */
    fun start(bluetooth: Boolean) {
        if (started) return
        started = true
        if (!bluetooth) {
            demo = true
            log.add("Demo-Modus: Bluetooth aus")
            return
        }
        config.keyDatabaseError?.let { _phase.value = Phase.Failed(it); log.error(it) }
        log.add("DEV_MODE=${if (config.devGuard.devMode) "1" else "0"}, Testpumpe ${if (config.devGuard.testPumpSerial.isEmpty()) "nicht gesetzt" else "gesetzt"}")
        context.registerReceiver(stateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        if (adapter?.isEnabled == true) setUpServer() else _phase.value = Phase.BluetoothOff
    }

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)) {
                BluetoothAdapter.STATE_ON -> {
                    log.add("Bluetooth an")
                    if (_phase.value == Phase.BluetoothOff) _phase.value = Phase.WaitingForPump
                    setUpServer()
                }
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                    if (_phase.value == Phase.BluetoothOff) return
                    log.warn("Bluetooth aus")
                    tearDown()
                    _phase.value = Phase.BluetoothOff
                }
            }
        }
    }

    private fun tearDown() {
        stopAdvertising()
        closeClient()
        try { server?.close() } catch (_: Exception) {}
        server = null
        sakePort = null
        servicesReady = false
        pumpDevice = null
        outbox.clear()
        notifyInFlight = false
    }

    // MARK: - Public controls

    fun setPairingMode(on: Boolean) {
        _pairingMode.value = on
        log.add(if (on) "Kopplungsmodus an (Mobile $advertisedName)" else "Kopplungsmodus aus")
        updateAdvertising()
    }

    /** Demo mode switched on while no pump is paired: release Bluetooth for this run. */
    fun stopForDemo() {
        if (_isPaired.value) return
        tearDown()
        demo = true
        log.add("Demo-Modus: Bluetooth aus")
    }

    /** A key database was imported in the settings. */
    fun setKeyDatabase(db: KeyDatabase) {
        _keyDatabase.value = db
        if (_phase.value is Phase.Failed) _phase.value = Phase.WaitingForPump
        log.add("Schlüsseldatenbank importiert")
    }

    fun refreshNow() {
        if (_phase.value == Phase.Connected) scheduleRefresh(force = true)
    }

    // MARK: - Peripheral side (GATT server, SAKE)

    /**
     * Values of the app's Device Information Service (custom UUID 0x0900). The pump reads all of
     * them before it starts the SAKE handshake. On iOS they mirror the official app (lab
     * notebook, capture 1); with other values the pump reported "device not compatible". The
     * same set of characteristics is served here, with Android device data and the same app
     * version string. To be verified on the real pump (see docs/internal/lab-notebook.md).
     */
    private val deviceInfo: Map<String, ByteArray> by lazy {
        mapOf(
            "2A29" to Build.MANUFACTURER.toByteArray(),
            "2A24" to Build.MODEL.toByteArray(),
            "2A25" to "Mobile $advertisedName".toByteArray(),
            "2A27" to "Android".toByteArray(),
            "2A26" to "Android ${Build.VERSION.RELEASE}".toByteArray(),
            "2A28" to COMPAT_SOFTWARE_REVISION.toByteArray(),
            "2A23" to ByteArray(8),
            "2A50" to ByteArray(7),
            "2A2A" to ByteArray(0),
        )
    }

    private fun setUpServer() {
        if (demo || server != null) return
        val s = try {
            manager.openGattServer(context, serverCallback)
        } catch (e: SecurityException) {
            log.error("GATT-Server: Berechtigung fehlt")
            null
        } ?: run {
            log.error("GATT-Server konnte nicht geöffnet werden")
            return
        }
        server = s
        servicesReady = false
        val port = BluetoothGattCharacteristic(
            PumpUuid.parse(PumpUuid.SAKE_PORT),
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_WRITE,
        )
        port.addDescriptor(
            BluetoothGattDescriptor(
                PumpUuid.parse(PumpUuid.CCCD),
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
            ),
        )
        val sakeService = BluetoothGattService(PumpUuid.parse(PumpUuid.SAKE_SERVICE), BluetoothGattService.SERVICE_TYPE_PRIMARY)
        sakeService.addCharacteristic(port)
        sakePort = port

        // Values are served dynamically in onCharacteristicReadRequest, so every read gets logged.
        val dis = BluetoothGattService(PumpUuid.parse(PumpUuid.APP_DEVICE_INFO_SERVICE), BluetoothGattService.SERVICE_TYPE_PRIMARY)
        for (uuid in listOf("2A29", "2A24", "2A25", "2A27", "2A26", "2A28", "2A23", "2A50", "2A2A")) {
            dis.addCharacteristic(
                BluetoothGattCharacteristic(
                    PumpUuid.parse(uuid), BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ,
                ),
            )
        }
        // Same order as the official app: SAKE service first, then device information.
        // Android accepts the next service only after onServiceAdded of the previous one.
        pendingServices.clear()
        pendingServices.add(sakeService)
        pendingServices.add(dis)
        addNextService()
    }

    private fun addNextService() {
        val s = server ?: return
        val next = pendingServices.removeFirstOrNull()
        if (next == null) {
            servicesReady = true
            log.add("GATT-Server registriert (SAKE 0xFE82, DIS 0x0900)")
            updateAdvertising()
            resumeSavedSession()
            return
        }
        if (!s.addService(next)) log.error("Service ${PumpUuid.short(next.uuid)} nicht registriert")
    }

    private fun updateAdvertising() {
        if (demo || !servicesReady || adapter?.isEnabled != true) return
        if (_phase.value is Phase.Blocked) {
            stopAdvertising()
            return
        }
        val wanted = when {
            _pairingMode.value -> "pair"
            _phase.value != Phase.Connected -> "reconnect"
            else -> null
        }
        if (wanted == advertisingMode && advertiseCallback != null) return
        stopAdvertising()
        if (wanted == null) return
        val advertiser = adapter?.bluetoothLeAdvertiser ?: run {
            log.error("Advertising nicht verfügbar")
            return
        }
        // 30 ms like the official app (lab notebook, capture 1).
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()
        val data = AdvertiseData.Builder().setIncludeDeviceName(false).setIncludeTxPowerLevel(false)
        if (wanted == "pair") {
            // Android cannot set a local name per advertisement (only the adapter name), so the
            // "Mobile …" name goes into Medtronic manufacturer data like in OpenMinimed's
            // JavaPumpConnector and GlycemicGPT: company 0x01F9, 00 + name + 00.
            data.addServiceUuid(ParcelUuid(PumpUuid.parse(PumpUuid.SAKE_SERVICE)))
            data.addManufacturerData(MEDTRONIC_COMPANY_ID, byteArrayOf(0) + "Mobile $advertisedName".toByteArray() + byteArrayOf(0))
            if (_phase.value != Phase.Connected) _phase.value = Phase.Pairing
        } else {
            // Reconnects work via the bond (IRK) as well, see lab notebook capture 2.
            data.addServiceUuid(ParcelUuid(PumpUuid.parse(PumpUuid.RECONNECT_SERVICE)))
            if (_phase.value == Phase.Pairing) _phase.value = Phase.WaitingForPump
        }
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                main.post {
                    log.add(if (wanted == "pair") "Advertising: Kopplung (FE82, Mobile $advertisedName)" else "Advertising: Wiederverbindung (FE81)")
                }
            }

            override fun onStartFailure(errorCode: Int) {
                main.post {
                    log.error("Advertising fehlgeschlagen: $errorCode")
                    if (advertiseCallback === this) advertiseCallback = null
                }
            }
        }
        advertiseCallback = callback
        advertisingMode = wanted
        try {
            advertiser.startAdvertising(settings, data.build(), callback)
        } catch (e: SecurityException) {
            log.error("Advertising: Berechtigung fehlt")
            advertiseCallback = null
        }
    }

    private fun stopAdvertising() {
        val cb = advertiseCallback ?: return
        try {
            adapter?.bluetoothLeAdvertiser?.stopAdvertising(cb)
        } catch (_: Exception) {
        }
        advertiseCallback = null
        advertisingMode = null
    }

    private fun send(data: ByteArray) {
        outbox.addLast(data)
        flushOutbox()
    }

    private fun flushOutbox() {
        val s = server ?: return
        val port = sakePort ?: return
        val device = pumpDevice ?: return
        if (notifyInFlight) return
        val next = outbox.firstOrNull() ?: return
        val ok = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                s.notifyCharacteristicChanged(device, port, false, next) == BluetoothStatusCodes.SUCCESS
            } else {
                @Suppress("DEPRECATION")
                port.value = next
                @Suppress("DEPRECATION")
                s.notifyCharacteristicChanged(device, port, false)
            }
        } catch (e: Exception) {
            false
        }
        if (ok) {
            outbox.removeFirst()
            notifyInFlight = true
        } else {
            main.postDelayed({ flushOutbox() }, 50)
        }
    }

    private fun handleSake(value: ByteArray) {
        val db = _keyDatabase.value ?: return
        if (sake == null || sake?.isComplete == true) sake = SakeServer(db)
        val server = sake ?: return
        try {
            val stage = server.stage
            val reply = server.handle(value)
            if (reply != null) {
                log.add("SAKE Stufe $stage → ${server.stage}")
                send(reply)
            } else if (server.isComplete) {
                log.add("SAKE-Handshake abgeschlossen")
                crypt = server.crypt
                decryptFailures = 0
                crypt?.let(sessions::save)
                pumpDevice?.let { prefs.pumpAddress = it.address }
                prefs.isPaired = true
                _isPaired.value = true
                _waitingSince.value = null
                if (_pairingMode.value) setPairingMode(false)
                connectAsGattClient()
            }
        } catch (e: Exception) {
            log.error("SAKE-Fehler: ${e.message}")
            sake = null
        }
    }

    // MARK: - Central side (GATT client on the pump)

    private fun isLinked(device: BluetoothDevice): Boolean =
        manager.getConnectedDevices(BluetoothProfile.GATT_SERVER).any { it.address == device.address } ||
            manager.getConnectedDevices(BluetoothProfile.GATT).any { it.address == device.address }

    private fun connectAsGattClient() {
        _phase.value = Phase.Connecting
        val device = pumpDevice
        if (device == null || !isLinked(device)) {
            // Never open a connection ourselves; wait for the pump's link.
            retrieveAttempts++
            if (retrieveAttempts <= 5) {
                main.postDelayed({ connectAsGattClient() }, 2000)
            } else {
                retrieveAttempts = 0
                _phase.value = Phase.Failed("Pumpe nicht als GATT-Server erreichbar")
                log.error("Pumpe nicht als GATT-Server gefunden")
            }
            return
        }
        retrieveAttempts = 0
        val existing = gatt
        if (existing != null && existing.device.address == device.address) {
            startDiscovery(existing)
            return
        }
        closeClient()
        log.add("GATT-Client: verbinde mit der bestehenden Verbindung der Pumpe")
        gatt = device.connectGatt(context, false, clientCallback, BluetoothDevice.TRANSPORT_LE)
    }

    private fun startDiscovery(g: BluetoothGatt) {
        resetClientState()
        if (!g.discoverServices()) log.warn("Service-Suche nicht gestartet")
    }

    private fun closeClient() {
        gatt?.let {
            try { it.close() } catch (_: Exception) {}
        }
        gatt = null
        gattQueue.clear()
        gattBusy = false
        main.removeCallbacks(gattTimeout)
    }

    /**
     * After the app process was restarted, the pump may still be connected with the old SAKE
     * session. Continue with the saved cipher instead of losing data. Without a session, ask
     * the pump for a fresh handshake (see [requestNewHandshakeIfLinked]).
     */
    private fun resumeSavedSession() {
        if (crypt != null || sake != null) return
        val address = prefs.pumpAddress.takeIf { it.isNotEmpty() } ?: return requestNewHandshakeIfLinked(null)
        val device = try { adapter?.getRemoteDevice(address) } catch (_: Exception) { null }
        val saved = sessions.load()
        if (device == null || !isLinked(device) || saved == null) {
            sessions.clear()
            requestNewHandshakeIfLinked(device?.takeIf { isLinked(it) })
            return
        }
        crypt = saved
        pumpDevice = device
        log.add("Setze gespeicherte Sitzung fort (Pumpe verbunden)")
        connectAsGattClient()
    }

    /**
     * The pump is paired but we have no session, e.g. after the app process was killed. If the
     * pump is still linked without subscribing to the SAKE port after a grace period, drop our
     * side of the link: the pump reconnects and starts a new handshake (as after an app update
     * on iOS). This only touches our own connection state, never anything on the pump.
     */
    private fun requestNewHandshakeIfLinked(device: BluetoothDevice?) {
        if (!_isPaired.value && store.lastDataAt.value == null) return
        _waitingSince.value = Instant.now()
        if (_phase.value != Phase.Connected) _phase.value = Phase.WaitingForPump
        if (device == null) {
            log.add("Keine gespeicherte Sitzung, warte auf Handshake der Pumpe")
            return
        }
        log.add("Keine gespeicherte Sitzung, Pumpe verbunden – warte kurz auf neuen Handshake")
        main.postDelayed({
            if (sake == null && crypt == null && isLinked(device)) {
                log.warn("Pumpe verbunden ohne Sitzung, trenne eigene Verbindung für einen neuen Handshake")
                try { server?.cancelConnection(device) } catch (_: Exception) {}
            }
        }, 20_000)
    }

    private fun resetClientState() {
        characteristics.clear()
        serialVerified = false
        operations.clear()
        current = null
        currentStartedAt = null
        main.removeCallbacks(operationTimeout)
        sessionStart = null
        sensorRunHours = null
        historyBuffer.clear()
        historyNewestSeq = null
        gattQueue.clear()
        gattBusy = false
        main.removeCallbacks(gattTimeout)
    }

    private fun key(service: String, characteristic: String) =
        "${PumpUuid.normalize(service)}|${PumpUuid.normalize(characteristic)}"

    private fun characteristic(service: String, uuid: String): BluetoothGattCharacteristic? = characteristics[key(service, uuid)]

    private fun allDiscovered(g: BluetoothGatt) {
        for (s in g.services) for (c in s.characteristics) characteristics[key(s.uuid.toString(), c.uuid.toString())] = c
        log.add("${characteristics.size} Merkmale der Pumpe gefunden")
        _phase.value = Phase.Verifying
        // Rule 2: before anything else, read the serial number (unencrypted DIS).
        val serial = characteristic(PumpUuid.DEVICE_INFO_SERVICE, PumpUuid.SERIAL_NUMBER)
            ?: return block("Seriennummer der Pumpe nicht lesbar")
        guardedRead(serial)
        characteristic(PumpUuid.DEVICE_INFO_SERVICE, PumpUuid.FIRMWARE_REVISION)?.let(::guardedRead)
    }

    private fun serialReceived(serial: String) {
        _pumpSerial.value = serial
        if (!config.devGuard.accepts(serial)) return block("DEV_MODE: Pumpe $serial ist nicht die Testpumpe")
        serialVerified = true
        _waitingSince.value = null
        log.add("Pumpe verifiziert (${if (config.devGuard.devMode) "Testpumpe" else "DEV_MODE aus"})")
        _phase.value = Phase.Connected
        updateAdvertising()
        for ((service, uuid) in listOf(
            PumpUuid.CGM_SERVICE to PumpUuid.CGM_MEASUREMENT,
            PumpUuid.CGM_SERVICE to PumpUuid.RECORD_ACCESS_CP,
            PumpUuid.IDD_SERVICE to PumpUuid.IDD_STATUS_READER_CP,
            PumpUuid.IDD_SERVICE to PumpUuid.IDD_STATUS_CHANGED,
            PumpUuid.IDD_SERVICE to PumpUuid.IDD_HISTORY_DATA,
            PumpUuid.IDD_SERVICE to PumpUuid.RECORD_ACCESS_CP,
            PumpUuid.IDD_SERVICE to PumpUuid.GST_BATTERY_LEVEL,
            PumpUuid.BATTERY_SERVICE to PumpUuid.BATTERY_LEVEL,
        )) {
            characteristic(service, uuid)?.let(::guardedSubscribe)
        }
        scheduleRefresh(force = true)
    }

    private fun block(reason: String) {
        log.blocked(reason)
        _phase.value = Phase.Blocked(reason)
        closeClient()
        pumpDevice?.let { d -> try { server?.cancelConnection(d) } catch (_: Exception) {} }
        pumpDevice = null
        resetClientState()
        sake = null
        stopAdvertising()
    }

    // MARK: - Guarded access (hard rule 1)

    private fun guardedRead(c: BluetoothGattCharacteristic) {
        if (!ReadOnlyPolicy.mayRead(c.uuid.toString())) {
            log.blocked("BLOCKIERT: Lesen von ${PumpUuid.short(c.uuid)} nicht freigegeben")
            return
        }
        enqueue(GattCmd.Read(c))
    }

    private fun guardedSubscribe(c: BluetoothGattCharacteristic) {
        if (!ReadOnlyPolicy.maySubscribe(c.uuid.toString())) {
            log.blocked("BLOCKIERT: Abo auf ${PumpUuid.short(c.uuid)} nicht freigegeben")
            return
        }
        enqueue(GattCmd.Subscribe(c))
    }

    /** The only place that writes to a pump characteristic. */
    private fun guardedWrite(service: String, uuid: String, plaintext: ByteArray): Boolean {
        if (!serialVerified) {
            log.blocked("BLOCKIERT: Schreiben vor Pumpen-Verifikation")
            return false
        }
        val decision = ReadOnlyPolicy.check(WriteRequest(service, uuid, plaintext))
        if (decision is PolicyDecision.Blocked) {
            log.blocked("BLOCKIERT: ${decision.reason}")
            return false
        }
        val c = characteristic(service, uuid) ?: return false
        if (gatt == null) return false
        var payload = plaintext
        if (PumpUuid.short(c.uuid) in ENCRYPTED) {
            val cr = crypt ?: return false
            try {
                payload = cr.encrypt(plaintext)
                sessions.save(cr)
            } catch (e: Exception) {
                log.error("Verschlüsselung fehlgeschlagen: ${e.message}")
                return false
            }
        }
        enqueue(GattCmd.Write(c, payload))
        return true
    }

    // MARK: - GATT command queue

    private fun enqueue(cmd: GattCmd) {
        gattQueue.addLast(cmd)
        runGattQueue()
    }

    private fun runGattQueue() {
        if (gattBusy) return
        val g = gatt ?: return gattQueue.clear()
        while (gattQueue.isNotEmpty()) {
            val cmd = gattQueue.removeFirst()
            val ok = try {
                execute(g, cmd)
            } catch (e: Exception) {
                log.warn("GATT-Befehl fehlgeschlagen: ${e.message}")
                false
            }
            if (ok) {
                gattBusy = true
                main.postDelayed(gattTimeout, 6000)
                return
            }
        }
    }

    private fun execute(g: BluetoothGatt, cmd: GattCmd): Boolean = when (cmd) {
        is GattCmd.Read -> g.readCharacteristic(cmd.c)
        is GattCmd.Write -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(cmd.c, cmd.value, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            cmd.c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            cmd.c.value = cmd.value
            @Suppress("DEPRECATION")
            g.writeCharacteristic(cmd.c)
        }
        is GattCmd.Subscribe -> {
            g.setCharacteristicNotification(cmd.c, true)
            val cccd = cmd.c.getDescriptor(PumpUuid.parse(PumpUuid.CCCD))
            if (cccd == null) {
                false
            } else {
                val value = if (cmd.c.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0) {
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
                } else {
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    g.writeDescriptor(cccd, value) == BluetoothStatusCodes.SUCCESS
                } else {
                    @Suppress("DEPRECATION")
                    cccd.value = value
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(cccd)
                }
            }
        }
    }

    private fun gattDone() {
        main.removeCallbacks(gattTimeout)
        gattBusy = false
        runGattQueue()
    }

    // MARK: - Refresh cycle

    private fun scheduleRefresh(force: Boolean = false) {
        if (!serialVerified) return
        // Detect a stuck operation by time as well (timers may be delayed while the phone dozes).
        currentStartedAt?.let {
            if (Duration.between(it, Instant.now()).seconds > 60) {
                log.warn("Abfrage hängt (${current ?: "?"}), setze zurück")
                operations.clear()
                current = null
                currentStartedAt = null
            }
        }
        if (current != null || operations.isNotEmpty()) {
            refreshPending = true
            return
        }
        if (!force && Duration.between(lastRefresh, Instant.now()).seconds < 50) return
        refreshPending = false
        lastRefresh = Instant.now()
        operations.addAll(listOf(
            Operation.Read(PumpUuid.IDD_SERVICE, PumpUuid.IDD_STATUS),
            Operation.StatusReader(StatusReaderOpcode.GET_INSULIN_ON_BOARD),
            Operation.StatusReader(StatusReaderOpcode.GET_THERAPY_ALGORITHM_STATES),
            Operation.StatusReader(StatusReaderOpcode.GET_ACTIVE_BASAL_RATE_DELIVERY),
            Operation.StatusReader(StatusReaderOpcode.GET_TIME_IN_RANGE),
            Operation.Read(PumpUuid.BATTERY_SERVICE, PumpUuid.BATTERY_LEVEL),
            // GST Battery Level (0x0400) is notify-only on the 780G ("Reading is not permitted").
        ))
        if (sessionStart == null) operations.add(Operation.Read(PumpUuid.CGM_SERVICE, PumpUuid.CGM_SESSION_START_TIME))
        if (sensorRunHours == null) operations.add(Operation.Read(PumpUuid.CGM_SERVICE, PumpUuid.CGM_SESSION_RUN_TIME))
        operations.add(Operation.CgmLastRecord)
        // Pump history (boluses, carbs, BG, auto basal, sensor values) every ~5 min.
        if (Duration.between(lastHistorySync, Instant.now()).toMinutes() >= 4) {
            lastHistorySync = Instant.now()
            historyBuffer.clear()
            operations.add(Operation.HistoryLast)
        }
        nextOperation()
    }

    // MARK: - Pump history

    private var historyReference: HistoryReference?
        get() {
            val seq = prefs.historyRefSeq ?: return null
            val date = prefs.historyRefDate ?: return null
            return HistoryReference(seq, date)
        }
        set(value) {
            prefs.historyRefSeq = value?.sequence
            prefs.historyRefDate = value?.date
        }

    /** Queues a history read right away (e.g. a pump alert changed), unless one is running. */
    private fun requestHistoryNow() {
        if (!serialVerified) return
        fun isHistory(op: Operation?) = op is Operation.HistoryLast || op is Operation.HistoryRange
        if (isHistory(current) || operations.any(::isHistory)) return
        lastHistorySync = Instant.now()
        historyBuffer.clear()
        operations.add(Operation.HistoryLast)
        if (current == null) nextOperation()
    }

    /** Bump to re-read the pump history once (e.g. after improving the classification). */
    fun migrateHistoryIfNeeded() {
        if (prefs.historyVersion >= HISTORY_VERSION) return
        prefs.historyVersion = HISTORY_VERSION
        prefs.historyLastSeq = null
        historyReference = null
        store.resetTreatments()
        prefs.nsLastTreatment = 0
    }

    /** After "last record" told us the newest sequence number: queue the missing ranges. */
    private fun queueHistoryRanges() {
        val newest = historyNewestSeq ?: return
        val last = prefs.historyLastSeq
        if (last != null && last >= newest) return
        val lower = if (newest > HISTORY_INITIAL_WINDOW) newest - HISTORY_INITIAL_WINDOW else 0
        var from = maxOf(lower, (last ?: lower) + 1)
        if (from > newest) from = lower
        log.add("History: lade ${newest - from + 1} Einträge ($from…$newest)")
        val chunks = mutableListOf<Operation>()
        while (from <= newest) {
            val to = minOf(newest, from + HISTORY_CHUNK - 1)
            chunks.add(Operation.HistoryRange(from, to))
            from = to + 1
        }
        for (op in chunks.reversed()) operations.addFirst(op)
    }

    /** Converts the collected records into treatments and sensor values. */
    private fun processHistory() {
        if (historyBuffer.isEmpty()) return
        val records = historyBuffer.toList()
        historyBuffer.clear()
        val (events, reference) = HistoryTimeline.resolve(records, historyReference, ZoneId.systemDefault())
        historyReference = reference
        records.maxOfOrNull { it.sequence }?.let { prefs.historyLastSeq = maxOf(prefs.historyLastSeq ?: 0, it) }

        val treatments = Treatment.from(events)
        val auto = treatments.count { it.kind == Treatment.Kind.AUTO_CORRECTION }
        val manual = treatments.count { it.kind == Treatment.Kind.BOLUS }
        val sgv = events.mapNotNull { e ->
            val mgdl = (e.event as? HistoryEvent.SensorGlucose)?.mgdl ?: return@mapNotNull null
            GlucoseReading(e.date, mgdl, null, null)
        }
        for (e in events) {
            val ev = e.event
            if (ev is HistoryEvent.Annunciation) alarms.pumpAlarm(ev.id, ev.type, ev.status, e.date)
        }
        val newTreatments = store.addTreatments(treatments)
        val newReadings = store.merge(sgv)
        log.add(
            "History: ${records.size} Einträge, ${newTreatments.size} neue Behandlungen (Boli $manual, Autokorrekturen $auto), " +
                "${newReadings.size} Sensorwerte nachgetragen" + if (reference == null) " (noch keine Zeitreferenz)" else "",
        )
        if (newTreatments.isNotEmpty() || newReadings.isNotEmpty()) onHistory(newReadings.minOfOrNull { it.date })
    }

    private fun nextOperation() {
        main.removeCallbacks(operationTimeout)
        current = null
        currentStartedAt = null
        while (operations.isNotEmpty()) {
            val op = operations.removeFirst()
            if (start(op)) {
                current = op
                currentStartedAt = Instant.now()
                main.postDelayed(operationTimeout, if (op is Operation.HistoryRange) 45_000 else 8_000)
                return
            }
        }
        // Queue drained (also after a timed-out history range): process collected history.
        if (historyBuffer.isNotEmpty()) processHistory()
        // Run a refresh that was requested while busy.
        if (refreshPending) scheduleRefresh()
    }

    private fun start(op: Operation): Boolean = when (op) {
        is Operation.Read -> {
            val c = characteristic(op.service, op.characteristic)
            if (c == null) false else {
                guardedRead(c)
                ReadOnlyPolicy.mayRead(c.uuid.toString())
            }
        }
        is Operation.StatusReader -> guardedWrite(PumpUuid.IDD_SERVICE, PumpUuid.IDD_STATUS_READER_CP, op.opcode.request)
        Operation.CgmLastRecord -> guardedWrite(PumpUuid.CGM_SERVICE, PumpUuid.RECORD_ACCESS_CP, bytesOf(0x01, 0x06))
        Operation.HistoryLast -> guardedWrite(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, bytesOf(0x33, 0x69, 0x0F))
        is Operation.HistoryRange ->
            guardedWrite(PumpUuid.IDD_SERVICE, PumpUuid.RECORD_ACCESS_CP, bytesOf(0x33, 0x5A, 0x0F) + le32(op.from) + le32(op.to))
    }

    private fun finish(matches: (Operation) -> Boolean) {
        val op = current ?: return
        if (matches(op)) nextOperation()
    }

    // MARK: - Incoming values

    private fun handleValue(service: String, uuid: String, data: ByteArray) {
        var plain = data
        // The pump signals new data every ~5 min with a notification on GST Battery Level
        // followed by an indication on IDD Status Changed (capture 2). Any of these starts a
        // refresh, even if the payload cannot be decrypted.
        val isTrigger = uuid == IDD_STATUS_CHANGED || uuid == GST_BATTERY ||
            (uuid == PumpUuid.CGM_MEASUREMENT && current == null)
        if (uuid in ENCRYPTED) {
            val cr = crypt ?: run {
                log.warn("Keine Sitzung zum Entschlüsseln von $uuid")
                return
            }
            try {
                plain = cr.decrypt(data)
                decryptFailures = 0
                sessions.save(cr)
            } catch (e: Exception) {
                decryptFailures++
                log.warn("Entschlüsselung $uuid fehlgeschlagen (${decryptFailures}×): ${e.message}")
                if (decryptFailures >= 5) {
                    log.error("Sitzung ungültig, warte auf neuen Handshake der Pumpe")
                    crypt = null
                    sessions.clear()
                    _phase.value = Phase.Failed("Sitzung verloren – die Pumpe verbindet sich neu")
                }
                finish { true }
                if (isTrigger) scheduleRefresh()
                return
            }
        }
        try {
            dispatch(service, uuid, plain)
        } finally {
            if (isTrigger) scheduleRefresh()
        }
    }

    private fun dispatch(service: String, uuid: String, plain: ByteArray) {
        when (uuid) {
            PumpUuid.SERIAL_NUMBER -> serialReceived(String(plain))
            PumpUuid.FIRMWARE_REVISION -> _pumpFirmware.value = String(plain)

            PumpUuid.CGM_MEASUREMENT -> try {
                val m = CgmMeasurement.parse(plain)
                val now = Instant.now()
                var date = now
                // A new sensor record was just measured: if start + offset is off by whole
                // quarter hours, the pump clock was changed (e.g. daylight saving time).
                val isNewRecord = lastLiveOffset?.let { it != m.timeOffsetMinutes } ?: false
                lastLiveOffset = m.timeOffsetMinutes
                val start0 = sessionStart
                if (isNewRecord && start0 != null) {
                    SensorClock.shift(start0, m.timeOffsetMinutes, now)?.let { shift ->
                        val corrected = start0.plus(shift)
                        sessionStart = corrected
                        if (prefs.sessionStartReported == null) {
                            prefs.sessionStartReported = start0
                            prefs.sessionStartShiftSeconds = 0
                        }
                        prefs.sessionStartShiftSeconds += shift.seconds
                        store.update { it.copy(sensorStart = corrected) }
                        updateSensorExpiry()
                        log.warn("Sensorstart um ${shift.toMinutes()} min korrigiert (Pumpenuhr verstellt, z. B. Zeitumstellung)")
                    }
                }
                sessionStart?.let { start ->
                    val candidate = start.plusSeconds(m.timeOffsetMinutes * 60L)
                    if (candidate <= now.plusSeconds(300) && candidate > now.minus(Duration.ofDays(11))) date = candidate
                }
                // SG values outside 40…400 are sensor states, not glucose values.
                if (m.glucoseMgdl in 40.0..400.0) {
                    store.add(GlucoseReading(date, m.glucoseMgdl.roundToInt(), m.trendMgdlPerMin, m.timeOffsetMinutes))
                    onData()
                }
                log.add("SG ${m.glucoseMgdl.toInt()} mg/dL, Trend ${m.trendMgdlPerMin ?: "–"}")
            } catch (e: Exception) {
                log.warn("CGM-Messung nicht lesbar: ${e.message} ${plain.toHex()}")
            }

            PumpUuid.RECORD_ACCESS_CP -> when (service) {
                PumpUuid.CGM_SERVICE -> {
                    log.add("CGM-RACP-Antwort ${plain.toHex()}")
                    finish { it is Operation.CgmLastRecord }
                }
                IDD_SERVICE -> {
                    // IDS RACP response: 0F 0F <request opcode> <code>; F0 = success, 06 = no records.
                    val ok = plain.size >= 4 && plain[3].toInt() and 0xFF == 0xF0
                    if (!ok) log.warn("History-RACP-Antwort ${plain.toHex()}")
                    when (current) {
                        is Operation.HistoryLast -> {
                            queueHistoryRanges()
                            finish { true }
                        }
                        is Operation.HistoryRange -> {
                            finish { true }
                            // Process once, after the last range (which may already be running now).
                            if (operations.none { it is Operation.HistoryRange } && current !is Operation.HistoryRange) processHistory()
                        }
                        else -> {}
                    }
                }
            }

            IDD_HISTORY_DATA -> try {
                val record = HistoryRecord.parse(plain)
                if (current is Operation.HistoryLast) historyNewestSeq = record.sequence else historyBuffer.add(record)
            } catch (e: Exception) {
                log.warn("History-Eintrag nicht lesbar: ${plain.toHex()}")
            }

            IDD_STATUS_READER_CP -> handleStatusReader(plain)

            IDD_STATUS_CHANGED -> {
                val flags = StatusChangedFlags.parse(plain)
                if (flags != null && StatusChangedFlags.ANNUNCIATION in flags) {
                    // A pump alert changed: read the history right away instead of in ≤5 min.
                    log.add("Pumpe meldet geänderte Alarme")
                    requestHistoryNow()
                } else {
                    log.add("Pumpe meldet Statusänderung")
                }
            }

            IDD_STATUS -> {
                val s = runCatching { PumpStatus.parse(plain) }.getOrNull()
                if (s != null) {
                    store.update { it.copy(status = s) }
                    alarms.sensorStatus(s)
                    onData()
                } else {
                    log.warn("IDD-Status nicht lesbar: ${plain.toHex()}")
                }
                finish { it is Operation.Read }
            }

            PumpUuid.BATTERY_LEVEL -> {
                plain.firstOrNull()?.let { b -> store.update { it.copy(pumpBatteryPercent = b.toInt() and 0xFF) } }
                finish { it is Operation.Read && it.characteristic == PumpUuid.BATTERY_LEVEL }
            }

            GST_BATTERY -> {
                plain.firstOrNull()?.let { b -> store.update { it.copy(transmitterBatteryPercent = b.toInt() and 0xFF) } }
            }

            PumpUuid.CGM_SESSION_RUN_TIME -> {
                // u16 expected session run time in hours + E2E-CRC (CGMS).
                if (plain.size == 4 && Checksums.hasValidE2eCrc(plain)) {
                    val hours = (plain[0].toInt() and 0xFF) or ((plain[1].toInt() and 0xFF) shl 8)
                    sensorRunHours = hours
                    updateSensorExpiry()
                    log.add("Sensorlaufzeit $hours h")
                } else {
                    log.warn("Sensorlaufzeit nicht lesbar: ${plain.toHex()}")
                }
                finish { it is Operation.Read }
            }

            PumpUuid.CGM_SESSION_START_TIME -> {
                val reported = runCatching { CgmSessionStartTime.parse(plain).instant() }.getOrNull()
                if (reported != null) {
                    // A different reported start is a new sensor: drop the old correction.
                    if (prefs.sessionStartReported.let { it != null && it != reported }) {
                        prefs.sessionStartReported = null
                        prefs.sessionStartShiftSeconds = 0
                    }
                    val start = reported.plusSeconds(if (prefs.sessionStartReported != null) prefs.sessionStartShiftSeconds else 0)
                    sessionStart = start
                    store.update { it.copy(sensorStart = start) }
                    updateSensorExpiry()
                    log.add("Sensorstart ${DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT).withZone(ZoneId.systemDefault()).format(start)}")
                } else {
                    log.warn("Sensorstart nicht lesbar: ${plain.toHex()}")
                }
                finish { it is Operation.Read }
            }

            else -> log.add("Wert von $uuid: ${plain.toHex()}")
        }
    }

    private fun updateSensorExpiry() {
        val start = sessionStart ?: return
        val hours = sensorRunHours ?: return
        store.update { it.copy(sensorEnd = start.plusSeconds(hours * 3600L)) }
    }

    private fun handleStatusReader(plain: ByteArray) {
        val opcode = statusReaderResponseOpcode(plain) ?: return
        try {
            when (opcode) {
                StatusReaderOpcode.GET_INSULIN_ON_BOARD.responseOpcode -> {
                    val v = InsulinOnBoard.parse(plain); store.update { it.copy(iob = v) }
                }
                StatusReaderOpcode.GET_THERAPY_ALGORITHM_STATES.responseOpcode -> {
                    val v = TherapyAlgorithmStates.parse(plain); store.update { it.copy(algorithm = v) }
                }
                StatusReaderOpcode.GET_ACTIVE_BASAL_RATE_DELIVERY.responseOpcode -> {
                    val v = ActiveBasalRate.parse(plain); store.update { it.copy(basal = v) }
                }
                StatusReaderOpcode.GET_TIME_IN_RANGE.responseOpcode -> {
                    val v = TimeInRange.parse(plain); store.update { it.copy(timeInRange = v) }
                }
                else -> log.warn("SRCP-Antwort 0x%04x: %s".format(opcode, plain.toHex()))
            }
            onData()
        } catch (e: Exception) {
            log.warn("SRCP-Antwort nicht lesbar: ${e.message} ${plain.toHex()}")
        }
        finish { it is Operation.StatusReader }
    }

    // MARK: - GATT server callback (binder threads → main)

    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            main.post {
                if (status != BluetoothGatt.GATT_SUCCESS) log.error("Service ${PumpUuid.short(service.uuid)} nicht registriert ($status)")
                else log.add("Service ${PumpUuid.short(service.uuid)} registriert")
                addNextService()
            }
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            main.post {
                val isPump = device.address == pumpDevice?.address || device.address == prefs.pumpAddress
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    if (isPump) log.add("Pumpe verbunden")
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED && isPump) {
                    pumpDisconnected(status)
                }
            }
        }

        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            val short = PumpUuid.short(characteristic.uuid)
            val value = deviceInfo[short]
            val s = server ?: return
            if (value == null) {
                s.sendResponse(device, requestId, BluetoothGatt.GATT_READ_NOT_PERMITTED, offset, null)
                main.post { log.warn("Pumpe liest unbekanntes Merkmal $short") }
                return
            }
            if (offset > value.size) {
                s.sendResponse(device, requestId, BluetoothGatt.GATT_INVALID_OFFSET, offset, null)
                return
            }
            s.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value.copyOfRange(offset, value.size))
            if (offset == 0) main.post { log.add("Pumpe liest $short: \"${String(value)}\"") }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            val isPort = PumpUuid.short(characteristic.uuid) == PumpUuid.short(PumpUuid.parse(PumpUuid.SAKE_PORT))
            if (responseNeeded) {
                server?.sendResponse(device, requestId, if (isPort) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, offset, null)
            }
            val copy = value?.copyOf()
            main.post {
                if (!isPort || copy == null) {
                    log.warn("Pumpe schreibt auf ${PumpUuid.short(characteristic.uuid)}, abgelehnt")
                    return@post
                }
                if (pumpDevice == null) pumpDevice = device
                if (_phase.value is Phase.Blocked) return@post
                handleSake(copy)
            }
        }

        override fun onDescriptorReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, descriptor: BluetoothGattDescriptor) {
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, byteArrayOf(0, 0))
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            val isSakeCccd = PumpUuid.short(descriptor.uuid) == PumpUuid.CCCD &&
                descriptor.characteristic?.uuid == PumpUuid.parse(PumpUuid.SAKE_PORT)
            if (!isSakeCccd || value == null || value.size < 2) return
            val subscribed = value[0].toInt() and 0x03 != 0
            main.post { if (subscribed) sakeSubscribed(device) else sakeUnsubscribed(device) }
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                notifyInFlight = false
                flushOutbox()
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            main.post { log.add("MTU $mtu") }
        }
    }

    private fun sakeSubscribed(device: BluetoothDevice) {
        log.add("Pumpe hat SAKE abonniert, starte Handshake")
        pumpDevice = device
        closeClient()
        resetClientState()
        sake = null
        crypt = null
        sessions.clear()
        outbox.clear()
        notifyInFlight = false
        _phase.value = Phase.Handshake
        send(ByteArray(SakeServer.MESSAGE_SIZE))
    }

    private fun sakeUnsubscribed(device: BluetoothDevice) {
        if (device.address != pumpDevice?.address) return
        log.warn("Pumpe hat SAKE-Abo beendet")
    }

    private fun pumpDisconnected(status: Int) {
        log.warn("Pumpe getrennt ($status)")
        closeClient()
        resetClientState()
        outbox.clear()
        notifyInFlight = false
        if (_phase.value is Phase.Blocked) {
            pumpDevice = null
            return
        }
        // No reconnect from our side: the pump reconnects to us. The saved session stays valid
        // only for this link, so a reconnect always starts with a new handshake.
        sake = null
        pumpDevice = null
        _phase.value = Phase.WaitingForPump
        updateAdvertising()
    }

    // MARK: - GATT client callback (binder threads → main)

    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (g !== gatt) return@post
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        log.add("GATT-Client verbunden")
                        // A handshake is running: discovery starts once it completed.
                        if (crypt == null) {
                            log.add("Warte auf SAKE-Handshake")
                            return@post
                        }
                        startDiscovery(g)
                    }
                    BluetoothProfile.STATE_DISCONNECTED -> {
                        log.warn("GATT-Client getrennt ($status)")
                        closeClient()
                        resetClientState()
                        if (_phase.value is Phase.Blocked) return@post
                        val device = pumpDevice
                        if (device != null && isLinked(device) && crypt != null) {
                            // The pump link is still up; attach again (no new connection).
                            main.postDelayed({ if (gatt == null && pumpDevice != null) connectAsGattClient() }, 2000)
                        } else {
                            _phase.value = Phase.WaitingForPump
                            updateAdvertising()
                        }
                    }
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (g !== gatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS || g.services.isEmpty()) {
                    log.error("Keine Services gefunden ($status)")
                    return@post
                }
                allDiscovered(g)
            }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            delivered(g, c, value.copyOf(), status, read = true)
        }

        @Suppress("OVERRIDE_DEPRECATION")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            delivered(g, c, c.value?.copyOf() ?: ByteArray(0), status, read = true)
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            delivered(g, c, value.copyOf(), BluetoothGatt.GATT_SUCCESS, read = false)
        }

        @Suppress("OVERRIDE_DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) return
            @Suppress("DEPRECATION")
            delivered(g, c, c.value?.copyOf() ?: ByteArray(0), BluetoothGatt.GATT_SUCCESS, read = false)
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            main.post {
                if (g !== gatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    log.warn("Schreibfehler ${PumpUuid.short(c.uuid)}: $status")
                    finish { true }
                }
                gattDone()
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post {
                if (g !== gatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) log.warn("Abo ${PumpUuid.short(d.characteristic.uuid)} fehlgeschlagen: $status")
                gattDone()
            }
        }
    }

    private fun delivered(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int, read: Boolean) {
        val service = PumpUuid.short(c.service.uuid)
        val uuid = PumpUuid.short(c.uuid)
        main.post {
            if (g !== gatt) return@post
            if (read) gattDone()
            if (status != BluetoothGatt.GATT_SUCCESS) {
                log.warn("Lesefehler $uuid: $status")
                finish { true }
                return@post
            }
            handleValue(service, uuid, value)
        }
    }

    companion object {
        /**
         * Software revision reported to the pump. The pump may check the companion app version;
         * we report the version seen in capture 1. See docs/internal/lab-notebook.md.
         */
        const val COMPAT_SOFTWARE_REVISION = "3.3.0(80)"
        const val MEDTRONIC_COMPANY_ID = 0x01F9

        private const val HISTORY_CHUNK = 200L
        /** First sync: about three days of history (~700 records per day). */
        private const val HISTORY_INITIAL_WINDOW = 2_000L
        private const val HISTORY_VERSION = 2

        private val IDD_SERVICE = PumpUuid.normalize(PumpUuid.IDD_SERVICE)
        private val IDD_STATUS = PumpUuid.normalize(PumpUuid.IDD_STATUS)
        private val IDD_STATUS_CHANGED = PumpUuid.normalize(PumpUuid.IDD_STATUS_CHANGED)
        private val IDD_STATUS_READER_CP = PumpUuid.normalize(PumpUuid.IDD_STATUS_READER_CP)
        private val IDD_HISTORY_DATA = PumpUuid.normalize(PumpUuid.IDD_HISTORY_DATA)
        private val GST_BATTERY = PumpUuid.normalize(PumpUuid.GST_BATTERY_LEVEL)

        /** Characteristics whose values are SAKE-encrypted (OpenMinimed pump-services.md). */
        private val ENCRYPTED: Set<String> = listOf(
            PumpUuid.IDD_STATUS_CHANGED, PumpUuid.IDD_STATUS, PumpUuid.IDD_ANNUNCIATION, PumpUuid.IDD_FEATURES,
            PumpUuid.IDD_STATUS_READER_CP, PumpUuid.IDD_COMMAND_CP, PumpUuid.IDD_COMMAND_DATA, PumpUuid.IDD_HISTORY_DATA,
            PumpUuid.CGM_MEASUREMENT, PumpUuid.CGM_STATUS, PumpUuid.CGM_SESSION_START_TIME, PumpUuid.CGM_SPECIFIC_OPS_CP,
        ).map(PumpUuid::normalize).toSet()
    }
}
