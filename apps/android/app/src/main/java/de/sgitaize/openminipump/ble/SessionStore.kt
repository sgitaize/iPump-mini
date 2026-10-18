// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump.ble

import android.content.Context
import de.sgitaize.minimedkit.SeqCrypt
import java.io.File

/**
 * Persists the SAKE session cipher (session key, nonce, sequence counters) so a restart of the
 * app process does not lose the running session. App-private storage; only valid for the
 * current pump connection.
 */
class SessionStore(context: Context) {
    private val file = File(context.noBackupFilesDir, "sake-session.txt")

    fun save(crypt: SeqCrypt) {
        try {
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(crypt.state.encode())
            tmp.renameTo(file)
        } catch (_: Exception) {
        }
    }

    fun load(): SeqCrypt? = try {
        SeqCrypt.State.decode(file.readText())?.let { SeqCrypt.fromState(it) }
    } catch (_: Exception) {
        null
    }

    fun clear() {
        file.delete()
    }
}
