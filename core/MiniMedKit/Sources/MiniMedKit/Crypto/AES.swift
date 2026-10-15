// SPDX-License-Identifier: GPL-3.0-or-later
// AES-128 primitives (ECB block, CTR, CMAC) on top of CommonCrypto.
import CommonCrypto
import Foundation

/// Errors of the CommonCrypto wrappers (AES-ECB, AES-CTR, AES-CMAC).
public enum CryptoError: Error, Equatable {
    case invalidKeyLength
    case invalidBlockLength
    case commonCrypto(Int32)
}

enum AES128 {
    static let blockSize = 16

    static func encryptBlock(key: [UInt8], block: [UInt8]) throws -> [UInt8] {
        try crypt(CCOperation(kCCEncrypt), key: key, block: block)
    }

    static func decryptBlock(key: [UInt8], block: [UInt8]) throws -> [UInt8] {
        try crypt(CCOperation(kCCDecrypt), key: key, block: block)
    }

    private static func crypt(_ op: CCOperation, key: [UInt8], block: [UInt8]) throws -> [UInt8] {
        guard key.count == kCCKeySizeAES128 else { throw CryptoError.invalidKeyLength }
        guard block.count == blockSize else { throw CryptoError.invalidBlockLength }
        var out = [UInt8](repeating: 0, count: blockSize)
        var moved = 0
        let status = CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, block, block.count, &out, out.count, &moved)
        guard status == kCCSuccess else { throw CryptoError.commonCrypto(status) }
        return out
    }

    /// AES-CTR with a 16-byte initial counter block. The counter is the whole block
    /// interpreted as a big-endian integer (same as PyCryptodome/BouncyCastle for our sizes).
    static func ctr(key: [UInt8], iv: [UInt8], data: [UInt8]) throws -> [UInt8] {
        guard iv.count == blockSize else { throw CryptoError.invalidBlockLength }
        var counter = iv
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        var offset = 0
        while offset < data.count {
            let keystream = try encryptBlock(key: key, block: counter)
            let n = min(blockSize, data.count - offset)
            for i in 0..<n { out.append(data[offset + i] ^ keystream[i]) }
            offset += n
            increment(&counter)
        }
        return out
    }

    private static func increment(_ block: inout [UInt8]) {
        for i in stride(from: block.count - 1, through: 0, by: -1) {
            block[i] &+= 1
            if block[i] != 0 { break }
        }
    }

    /// AES-CMAC (RFC 4493), truncated to `length` bytes.
    static func cmac(key: [UInt8], message: [UInt8], length: Int = 16) throws -> [UInt8] {
        let zero = [UInt8](repeating: 0, count: blockSize)
        let l = try encryptBlock(key: key, block: zero)
        let k1 = subkey(l)
        let k2 = subkey(k1)

        let blocks = max(1, (message.count + blockSize - 1) / blockSize)
        let complete = !message.isEmpty && message.count % blockSize == 0
        var last = [UInt8](repeating: 0, count: blockSize)
        let lastStart = (blocks - 1) * blockSize
        if complete {
            for i in 0..<blockSize { last[i] = message[lastStart + i] ^ k1[i] }
        } else {
            let rest = message.count - lastStart
            for i in 0..<rest { last[i] = message[lastStart + i] }
            last[rest] = 0x80
            for i in 0..<blockSize { last[i] ^= k2[i] }
        }

        var x = zero
        for b in 0..<(blocks - 1) {
            var y = [UInt8](repeating: 0, count: blockSize)
            for i in 0..<blockSize { y[i] = x[i] ^ message[b * blockSize + i] }
            x = try encryptBlock(key: key, block: y)
        }
        var y = [UInt8](repeating: 0, count: blockSize)
        for i in 0..<blockSize { y[i] = x[i] ^ last[i] }
        let tag = try encryptBlock(key: key, block: y)
        return Array(tag.prefix(length))
    }

    private static func subkey(_ input: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: blockSize)
        var carry: UInt8 = 0
        for i in stride(from: blockSize - 1, through: 0, by: -1) {
            out[i] = (input[i] << 1) | carry
            carry = input[i] >> 7
        }
        if input[0] & 0x80 != 0 { out[blockSize - 1] ^= 0x87 }
        return out
    }
}

/// Constant-time comparison for MAC tags.
func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
}
