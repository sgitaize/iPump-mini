// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.content.Context
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Diagnostics log shown in the app. Also written to files/openminipump.log (rotated at 2 MB),
 * so background behaviour can be analysed later (`adb shell run-as … cat files/openminipump.log`
 * for debug builds, or "share" in the app).
 */
class EventLog(context: Context) {
    enum class Level { INFO, WARNING, ERROR, BLOCKED }

    data class Entry(val id: Long, val date: Long, val level: Level, val text: String)

    private val _entries = MutableStateFlow<List<Entry>>(emptyList())
    val entries: StateFlow<List<Entry>> = _entries

    val file = File(context.filesDir, "openminipump.log")
    private val formatter = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.ROOT)
    private var nextId = 0L

    init {
        if (file.length() > 2_000_000) {
            val old = File(context.filesDir, "openminipump.1.log")
            old.delete()
            file.renameTo(old)
        }
    }

    @Synchronized
    fun add(text: String, level: Level = Level.INFO) {
        val entry = Entry(nextId++, System.currentTimeMillis(), level, text)
        _entries.value = (_entries.value + entry).takeLast(500)
        Log.println(if (level == Level.INFO) Log.INFO else Log.WARN, "omp", text)
        try {
            file.appendText("${formatter.format(Date(entry.date))} [${level.name.lowercase()}] $text\n")
        } catch (_: Exception) {
        }
    }

    fun warn(text: String) = add(text, Level.WARNING)
    fun error(text: String) = add(text, Level.ERROR)
    fun blocked(text: String) = add(text, Level.BLOCKED)
}
