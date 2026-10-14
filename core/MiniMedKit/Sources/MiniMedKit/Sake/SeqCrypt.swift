// SPDX-License-Identifier: GPL-3.0-or-later
// Sequenced AES-CTR + truncated CMAC used after the SAKE handshake.
// Swift port of OpenMinimed PythonSake/JavaSake `SeqCrypt` (GPL-3.0).
//
// Wire format: ciphertext || seqByte || cmac4[0..<2]
// IV/CMAC prefix: seq (5 bytes BE) || sessionNonce (8 bytes) || 00 00 00
import Foundation

public enum SakeError: Error, Equatable {
    case invalidMessageLength(Int)
    case unexpectedHandshakeStart
    case unexpectedDeviceType(UInt8)
    case missingStaticKeys
    case macFailure(String)
    case permitRejected
    case handshakeAlreadyComplete
    case sequenceExhausted
}

public final class SeqCrypt {
    static let maxRxDelta = 128
    static let maxSeq: UInt64 = 1 << 40

    let key: [UInt8]
    let nonce: [UInt8]
    public internal(set) var txSeq: UInt64
    public internal(set) var rxSeq: UInt64

    init(key: [UInt8], nonce: [UInt8], initialSeq: UInt64) {
        precondition(key.count == 16 && nonce.count == 8)
        self.key = key
        self.nonce = nonce
        txSeq = initialSeq
        rxSeq = initialSeq
    }

    public func encrypt(_ plaintext: [UInt8]) throws -> [UInt8] {
        let seq = txSeq
        guard seq < Self.maxSeq else { throw SakeError.sequenceExhausted }
        let iv = Self.prefix(seq: seq, nonce: nonce)
        let ciphertext = try AES128.ctr(key: key, iv: iv, data: plaintext)
        let tag = try AES128.cmac(key: key, message: iv + ciphertext, length: 4)
        txSeq = seq + 2
        return ciphertext + [UInt8((seq >> 1) & 0xFF), tag[0], tag[1]]
    }

    public func decrypt(_ message: [UInt8]) throws -> [UInt8] {
        guard message.count >= 3 else { throw SakeError.invalidMessageLength(message.count) }
        let seqByte = Int(message[message.count - 3])
        let delta = (seqByte - Int((rxSeq >> 1) & 0xFF)) & 0xFF
        guard delta <= Self.maxRxDelta else {
            throw SakeError.macFailure("sequence delta \(delta) out of window")
        }
        let seq = rxSeq + 2 * UInt64(delta)
        let ciphertext = Array(message[0..<(message.count - 3)])
        let iv = Self.prefix(seq: seq, nonce: nonce)
        let tag = try AES128.cmac(key: key, message: iv + ciphertext, length: 4)
        // rxSeq only advances on success, see JavaSake PR #2.
        guard constantTimeEqual(Array(tag.prefix(2)), Array(message.suffix(2))) else {
            throw SakeError.macFailure("seq \(seq)")
        }
        rxSeq = seq + 2
        return try AES128.ctr(key: key, iv: iv, data: ciphertext)
    }

    static func prefix(seq: UInt64, nonce: [UInt8]) -> [UInt8] {
        var block = [UInt8](repeating: 0, count: 16)
        for i in 0..<5 { block[i] = UInt8((seq >> (8 * UInt64(4 - i))) & 0xFF) }
        for i in 0..<8 { block[5 + i] = nonce[i] }
        return block
    }
}
