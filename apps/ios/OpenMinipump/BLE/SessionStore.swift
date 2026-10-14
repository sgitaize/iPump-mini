// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import MiniMedKit

/// Persists the SAKE session cipher (session key, nonce, sequence counters) so a relaunch
/// by iOS does not lose the running session. Stored in the app container with file
/// protection; it is only valid for the current pump connection.
enum SessionStore {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sake-session.json")
    }()

    static func save(_ crypt: SeqCrypt) {
        guard let data = try? JSONEncoder().encode(crypt.state) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> SeqCrypt? {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SeqCrypt.State.self, from: data) else { return nil }
        return SeqCrypt(state: state)
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }
}
