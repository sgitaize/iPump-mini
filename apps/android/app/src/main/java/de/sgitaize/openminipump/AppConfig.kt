// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.content.Context
import de.sgitaize.minimedkit.DevModeGuard
import de.sgitaize.minimedkit.KeyDatabase
import java.net.HttpURLConnection
import java.net.URL

/** Build-time configuration (BuildConfig from app/build.gradle.kts) and the key database. */
class AppConfig(
    val devGuard: DevModeGuard,
    val keyDatabase: KeyDatabase?,
    val keyDatabaseError: String?,
    val keyDatabaseSource: KeySource,
) {
    enum class KeySource { BUNDLE, IMPORTED, MISSING }

    companion object {
        fun load(context: Context, prefs: Prefs): AppConfig {
            val guard = DevModeGuard(BuildConfig.DEV_MODE, BuildConfig.TEST_PUMP_SERIAL)
            val bundled = try {
                context.assets.open("mobile-pump.keydb.hex").bufferedReader().readText()
            } catch (_: Exception) {
                null
            }
            if (bundled != null) {
                return try {
                    AppConfig(guard, KeyDatabase.fromHex(bundled), null, KeySource.BUNDLE)
                } catch (e: Exception) {
                    AppConfig(guard, null, context.getString(R.string.keydb_invalid, e.message), KeySource.MISSING)
                }
            }
            val imported = prefs.importedKeyDatabase.takeIf { it.isNotEmpty() }?.let { runCatching { KeyImport.validate(it) }.getOrNull() }
            if (imported != null) return AppConfig(guard, imported, null, KeySource.IMPORTED)
            return AppConfig(guard, null, context.getString(R.string.keydb_missing), KeySource.MISSING)
        }
    }
}

/** Key database imported by the user (public builds ship without it). */
object KeyImport {
    class WrongDatabase : Exception(OpenMinipumpApp.string(R.string.keydb_wrong))
    class NotFound : Exception(OpenMinipumpApp.string(R.string.keydb_not_found))
    class Http(code: Int) : Exception(OpenMinipumpApp.string(R.string.keydb_http, code))

    /** Public documentation of OpenMinimed that lists the dumped key databases. */
    const val OPEN_MINIMED_URL = "https://raw.githubusercontent.com/OpenMinimed/Documentation/main/key_databases.md"
    const val OPEN_MINIMED_PAGE = "https://github.com/OpenMinimed/Documentation/blob/main/key_databases.md"

    /** Checks CRC and that it is the "Mobile Application ↔ Insulin Pump" database. */
    fun validate(hex: String): KeyDatabase {
        val db = KeyDatabase.fromHex(hex)
        if (!KeyDatabase.isMobilePump(db)) throw WrongDatabase()
        return db
    }

    /** Finds the matching database in plain hex or a page like key_databases.md. */
    fun extract(text: String): String? = KeyDatabase.findHex(text, KeyDatabase::isMobilePump)

    fun save(prefs: Prefs, hex: String): KeyDatabase {
        val clean = hex.filterNot { it.isWhitespace() }
        val db = validate(clean)
        prefs.importedKeyDatabase = clean
        return db
    }

    /** Downloads a page or file, extracts the database and stores it. Blocking; call off the main thread. */
    fun load(prefs: Prefs, url: String): KeyDatabase {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 20_000
        conn.readTimeout = 20_000
        try {
            if (conn.responseCode !in 200..299) throw Http(conn.responseCode)
            val text = conn.inputStream.bufferedReader().readText()
            return save(prefs, extract(text) ?: throw NotFound())
        } finally {
            conn.disconnect()
        }
    }
}
