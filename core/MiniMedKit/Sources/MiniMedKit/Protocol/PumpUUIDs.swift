// SPDX-License-Identifier: GPL-3.0-or-later
// GATT UUIDs of the 700-series pump and of the app side (OpenMinimed Documentation).
import Foundation

public enum PumpUUID {
    private static func mdt(_ short: String) -> String { "0000\(short)-0000-1000-0000-009132591325" }

    // App side (we host these as BLE peripheral)
    public static let sakeService = "FE82"
    public static let reconnectService = "FE81"
    public static let sakePort = mdt("FE82")
    public static let appDeviceInfoService = mdt("0900")

    // Pump: Insulin Delivery Service (Medtronic UUIDs)
    public static let iddService = mdt("0100")
    public static let iddStatusChanged = mdt("0101")
    public static let iddStatus = mdt("0102")
    public static let iddAnnunciation = mdt("0103")
    public static let iddFeatures = mdt("0104")
    public static let iddStatusReaderCP = mdt("0105")
    public static let iddCommandCP = mdt("0106")
    public static let iddCommandData = mdt("0107")
    public static let iddHistoryData = mdt("0108")
    public static let gstBatteryLevel = mdt("0400")

    // Pump: CGM service (SIG UUIDs + Medtronic extensions)
    public static let cgmService = "181F"
    public static let cgmMeasurement = "2AA7"
    public static let cgmFeature = "2AA8"
    public static let cgmStatus = "2AA9"
    public static let cgmSessionStartTime = "2AAA"
    public static let cgmSessionRunTime = "2AAB"
    public static let cgmSpecificOpsCP = "2AAC"
    public static let sensorExpiration = mdt("0202")

    // Shared
    public static let recordAccessCP = "2A52"
    public static let deviceInfoService = "180A"
    public static let serialNumber = "2A25"
    public static let firmwareRevision = "2A26"
    public static let modelNumber = "2A24"
    public static let batteryService = "180F"
    public static let batteryLevel = "2A19"
}
