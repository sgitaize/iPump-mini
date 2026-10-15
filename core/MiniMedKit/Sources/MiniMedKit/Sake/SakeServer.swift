// SPDX-License-Identifier: GPL-3.0-or-later
// SAKE handshake, server role (the phone app is the BLE peripheral and SAKE server,
// the pump is the client). Swift port of OpenMinimed PythonSake/JavaSake (GPL-3.0).
//
// Stages: 0 (20 zero bytes in → msg0 out) → 1 (msg1 in → msg2 out)
//         → 3 (msg3 in → msg4 out) → 5 (msg5 in → done) → 6
import Foundation
import Security

/// Source of random bytes (injectable for tests with captured handshakes).
public protocol RandomSource {
    func bytes(_ count: Int) -> [UInt8]
}

/// Cryptographically secure random bytes from the system (SecRandomCopyBytes).
public struct SystemRandom: RandomSource {
    /// Creates the system random source.
    public init() {}
    /// Returns `count` random bytes.
    public func bytes(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &out)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return out
    }
}

/// Server side of the SAKE handshake (the phone; the pump is the client). Six 20-byte messages; afterwards `crypt` encrypts the session.
public final class SakeServer {
    public static let messageSize = 20
    static let defaultMsg4Pad: UInt8 = 0x69

    private let keyDatabase: KeyDatabase
    private let localDeviceType: SakeDeviceType
    private let random: RandomSource
    var msg4Pad: UInt8 = SakeServer.defaultMsg4Pad

    public private(set) var stage = 0
    public var isComplete: Bool { stage == 6 }

    private var clientDeviceType: SakeDeviceType?
    private var clientKeyMaterial: [UInt8] = []
    private var clientNonce: [UInt8] = []
    private var serverKeyMaterial: [UInt8] = []
    private var serverNonce: [UInt8] = []
    private var staticKeys: StaticKeys?

    /// Session cipher after the handshake. The server uses one SeqCrypt for both
    /// directions (separate tx/rx counters), as in the reference implementation.
    public private(set) var crypt: SeqCrypt?

    /// Creates a server for a new handshake with the given key database.
    public init(keyDatabase: KeyDatabase,
                localDeviceType: SakeDeviceType = .mobileApplication,
                random: RandomSource = SystemRandom()) {
        self.keyDatabase = keyDatabase
        self.localDeviceType = localDeviceType
        self.random = random
    }

    /// Feeds one message written by the pump into the handshake.
    /// Returns the message to notify back, or nil when the handshake completed.
    public func handle(_ input: [UInt8]) throws -> [UInt8]? {
        guard input.count == Self.messageSize else { throw SakeError.invalidMessageLength(input.count) }
        switch stage {
        case 0:
            guard input.allSatisfy({ $0 == 0 }) else { throw SakeError.unexpectedHandshakeStart }
            stage = 1
            return [localDeviceType.rawValue, 0x01] + random.bytes(18)

        case 1:
            clientKeyMaterial = Array(input[0..<8])
            guard let type = SakeDeviceType(rawValue: input[8]) else {
                throw SakeError.unexpectedDeviceType(input[8])
            }
            clientDeviceType = type
            clientNonce = Array(input[9..<13])
            guard keyDatabase.localDeviceType == localDeviceType,
                  let keys = keyDatabase.remoteDevices[type] else { throw SakeError.missingStaticKeys }
            staticKeys = keys

            serverKeyMaterial = random.bytes(8)
            serverNonce = random.bytes(4)
            let tag = try cmac8(keys, serverKeyMaterial + clientKeyMaterial + keys.derivationKey)
            stage = 3
            return tag + serverKeyMaterial + serverNonce

        case 3:
            guard let keys = staticKeys else { throw SakeError.missingStaticKeys }
            let serverTag = try cmac8(keys, serverKeyMaterial + clientKeyMaterial + keys.derivationKey)
            let expected = try cmac8(keys, serverTag + serverKeyMaterial + keys.derivationKey)
            guard constantTimeEqual(expected, Array(input[0..<8])) else {
                throw SakeError.macFailure("handshake msg3")
            }
            let sessionKey = try AES128.encryptBlock(key: keys.derivationKey,
                                                     block: serverKeyMaterial + clientKeyMaterial)
            let crypt = SeqCrypt(key: sessionKey, nonce: clientNonce + serverNonce, initialSeq: 1)
            self.crypt = crypt
            stage = 5
            return try crypt.encrypt(keys.handshakePayload + [msg4Pad])

        case 5:
            guard let keys = staticKeys, let crypt, let clientDeviceType else {
                throw SakeError.missingStaticKeys
            }
            // msg5 is encrypted with the client's sequence parity (even, starting at 0).
            let clientCrypt = SeqCrypt(key: crypt.key, nonce: crypt.nonce, initialSeq: 0)
            let plain = try clientCrypt.decrypt(input)
            let permit = try AES128.decryptBlock(key: keys.permitDecryptKey, block: Array(plain.prefix(16)))
            let tag = try AES128.cmac(key: keys.permitAuthKey, message: Array(permit[0..<12]), length: 4)
            guard constantTimeEqual(tag, Array(permit[12..<16])) else {
                throw SakeError.macFailure("permit")
            }
            guard permit[0] == 0, permit[1] == clientDeviceType.rawValue else { throw SakeError.permitRejected }
            // Align rx with the native shared counter (see pysake server.py, stage 5).
            crypt.rxSeq = 2
            stage = 6
            return nil

        default:
            throw SakeError.handshakeAlreadyComplete
        }
    }

    private func cmac8(_ keys: StaticKeys, _ message: [UInt8]) throws -> [UInt8] {
        try AES128.cmac(key: keys.handshakeAuthKey, message: message, length: 8)
    }
}
