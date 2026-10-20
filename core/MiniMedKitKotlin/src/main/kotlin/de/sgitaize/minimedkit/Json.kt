// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal JSON writer, so the library stays free of dependencies (the app and the tests
// run on plain JVM as well as on Android).
package de.sgitaize.minimedkit

/** A number written exactly as given, e.g. "0.050" for insulin amounts without binary noise. */
@JvmInline
value class JsonNumber(val literal: String)

object Json {
    /**
     * Serialises maps (String keys), lists, strings, numbers, booleans, null and [JsonNumber].
     * [sortedKeys] gives a stable key order (like `.sortedKeys` on iOS).
     */
    fun write(value: Any?, sortedKeys: Boolean = true): String = StringBuilder().also { append(it, value, sortedKeys) }.toString()

    private fun append(sb: StringBuilder, value: Any?, sorted: Boolean) {
        when (value) {
            null -> sb.append("null")
            is String -> string(sb, value)
            is Boolean -> sb.append(value)
            is JsonNumber -> sb.append(value.literal)
            is Int, is Long, is Short, is Byte -> sb.append(value.toString())
            is Double -> number(sb, value)
            is Float -> number(sb, value.toDouble())
            is Map<*, *> -> {
                sb.append('{')
                val entries = value.entries.map { it.key.toString() to it.value }
                    .let { if (sorted) it.sortedBy { e -> e.first } else it }
                entries.forEachIndexed { i, (k, v) ->
                    if (i > 0) sb.append(',')
                    string(sb, k)
                    sb.append(':')
                    append(sb, v, sorted)
                }
                sb.append('}')
            }
            is Iterable<*> -> {
                sb.append('[')
                value.forEachIndexed { i, v ->
                    if (i > 0) sb.append(',')
                    append(sb, v, sorted)
                }
                sb.append(']')
            }
            else -> string(sb, value.toString())
        }
    }

    private fun number(sb: StringBuilder, d: Double) {
        when {
            d.isNaN() || d.isInfinite() -> sb.append("null")
            d == Math.rint(d) && kotlin.math.abs(d) < 1e15 -> sb.append(d.toLong())
            else -> sb.append(java.math.BigDecimal(d.toString()).stripTrailingZeros().toPlainString())
        }
    }

    private fun string(sb: StringBuilder, s: String) {
        sb.append('"')
        for (ch in s) {
            when (ch) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (ch < ' ') sb.append("\\u%04x".format(ch.code)) else sb.append(ch)
            }
        }
        sb.append('"')
    }
}
