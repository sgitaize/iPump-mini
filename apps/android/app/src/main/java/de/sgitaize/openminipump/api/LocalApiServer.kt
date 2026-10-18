// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal HTTP server with Nightscout-compatible read endpoints (Android port of
// apps/ios/OpenMinipump/API/LocalAPIServer.swift).
//
// Port 17580 like the xDrip+ local web server, so existing clients work unchanged.
// By default only reachable from this phone (loopback). LAN access is opt-in and then
// requires the API secret (header `api-secret`: SHA-1 hex or plain, `?token=`, or Basic Auth
// with the secret as password). `/status.html` is a human-readable page (Basic Auth).
// Unlike on iOS the app keeps running in the background (foreground service), so the API
// answers all the time.
package de.sgitaize.openminipump.api

import android.util.Base64
import de.sgitaize.minimedkit.GlucoseReading
import de.sgitaize.minimedkit.Json
import de.sgitaize.minimedkit.Nightscout
import de.sgitaize.minimedkit.PumpSnapshot
import de.sgitaize.minimedkit.Treatment
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Immutable view of the data for the server threads. */
data class ApiData(
    val readings: List<GlucoseReading>,
    val snapshot: PumpSnapshot,
    val treatments: List<Treatment>,
    val uploaderBattery: Int?,
)

class LocalApiServer(
    private val version: String,
    private val data: () -> ApiData,
    private val onState: (String) -> Unit,
    private val onLog: (String) -> Unit,
    /** Every /pebble request (watch faces), for the optional Pebble monitor. */
    private val onPebbleRequest: () -> Unit,
    private val statusHtml: (ApiData) -> String,
) {
    @Volatile private var socket: ServerSocket? = null
    @Volatile private var allowLan = false
    @Volatile private var secret = ""
    private val workers = Executors.newFixedThreadPool(4)
    private val lastRequestLog = mutableMapOf<String, Long>()
    private var acceptThread: Thread? = null

    @Synchronized
    fun start(allowLan: Boolean, secret: String) {
        val lanChanged = allowLan != this.allowLan
        this.allowLan = allowLan
        this.secret = secret
        if (socket != null && !lanChanged) return
        stop()
        try {
            val s = ServerSocket()
            s.reuseAddress = true
            val address = if (allowLan) InetSocketAddress(PORT) else InetSocketAddress(InetAddress.getLoopbackAddress(), PORT)
            s.bind(address)
            socket = s
            onState(if (allowLan) "lan" else "local")
            acceptThread = Thread({ acceptLoop(s) }, "omp-api").apply { isDaemon = true; start() }
        } catch (e: Exception) {
            onLog("API-Server konnte nicht starten: ${e.message}")
            onState("error")
        }
    }

    @Synchronized
    fun stop() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
    }

    private fun acceptLoop(s: ServerSocket) {
        while (!s.isClosed) {
            val client = try { s.accept() } catch (_: Exception) { break }
            workers.execute { handle(client) }
        }
    }

    private fun handle(client: Socket) {
        client.use { c ->
            try {
                c.soTimeout = 10_000
                val head = readHead(BufferedInputStream(c.getInputStream())) ?: return
                val response = respond(head, c.inetAddress.isLoopbackAddress)
                c.getOutputStream().apply { write(response); flush() }
            } catch (_: Exception) {
            }
        }
    }

    private fun readHead(input: BufferedInputStream): String? {
        val buf = ByteArrayOutputStream()
        var matched = 0
        val end = byteArrayOf(13, 10, 13, 10)
        while (buf.size() < 16_384) {
            val b = input.read()
            if (b < 0) return null
            buf.write(b)
            matched = if (b.toByte() == end[matched]) matched + 1 else if (b == 13) 1 else 0
            if (matched == 4) return buf.toString(Charsets.UTF_8.name())
        }
        return null
    }

    private fun respond(head: String, loopback: Boolean): ByteArray {
        val lines = head.split("\r\n")
        val parts = lines.first().split(" ")
        if (parts.size < 2) return json("400 Bad Request", mapOf("error" to "bad request"))
        val method = parts[0]
        val headers = lines.drop(1).mapNotNull { line ->
            val i = line.indexOf(':')
            if (i <= 0) null else line.substring(0, i).lowercase() to line.substring(i + 1).trim()
        }.toMap()
        val target = parts[1]
        val path = target.substringBefore('?').lowercase()
        val query = target.substringAfter('?', "").split('&').filter { it.isNotEmpty() }.associate {
            val k = URLDecoder.decode(it.substringBefore('='), "UTF-8")
            val v = URLDecoder.decode(it.substringAfter('=', ""), "UTF-8")
            k to v
        }

        if (method == "OPTIONS") return raw("204 No Content", ByteArray(0), "text/plain")
        if (method != "GET" && method != "HEAD") return json("405 Method Not Allowed", mapOf("error" to "read-only API"))

        val client = (headers["user-agent"] ?: "?").take(40)
        synchronized(lastRequestLog) {
            val k = "$path|$client"
            if (System.currentTimeMillis() - (lastRequestLog[k] ?: 0) > 600_000) {
                lastRequestLog[k] = System.currentTimeMillis()
                onLog("API-Anfrage $path von $client")
            }
        }

        val wantsHtml = path == "/status.html" || (path == "/" && (headers["accept"] ?: "").contains("text/html"))
        if (wantsHtml) {
            // Human-readable page: Basic Auth with the API secret as password (any user name).
            val ok = if (secret.isEmpty()) loopback else basicAuthPassword(headers) == secret
            if (!ok) {
                return raw("401 Unauthorized", "Anmeldung erforderlich: Benutzername beliebig, Passwort = API-Secret.".toByteArray(),
                    "text/plain; charset=utf-8", mapOf("WWW-Authenticate" to "Basic realm=\"iPump-mini\", charset=\"UTF-8\""))
            }
            return raw("200 OK", statusHtml(data()).toByteArray(), "text/html; charset=utf-8")
        }
        if (!authorized(loopback, headers, query)) {
            return json("401 Unauthorized", mapOf("status" to 401, "message" to "api-secret fehlt oder falsch"))
        }

        val d = data()
        val newestFirst = d.readings.sortedByDescending { it.date }
        return when (path) {
            "/api/v1/entries.json", "/api/v1/entries", "/api/v1/entries/sgv.json", "/api/v1/entries/sgv", "/sgv.json" -> {
                val count = query["count"]?.toIntOrNull() ?: 10
                json("200 OK", filtered(newestFirst, query).take(maxOf(0, count)).map { Nightscout.entry(it) })
            }
            "/api/v1/entries/current.json", "/api/v1/entries/current" ->
                json("200 OK", newestFirst.take(1).map { Nightscout.entry(it) })
            "/api/v1/devicestatus.json", "/api/v1/devicestatus" ->
                json("200 OK", if (d.snapshot.hasData) listOf(Nightscout.deviceStatus(d.snapshot, d.uploaderBattery)) else emptyList())
            "/api/v1/treatments.json", "/api/v1/treatments" -> {
                val count = query["count"]?.toIntOrNull() ?: 100
                json("200 OK", d.treatments.sortedByDescending { it.date }
                    .mapNotNull { Nightscout.treatment(it, includeAutoBasal = true) }.take(maxOf(0, count)))
            }
            "/api/v1/status.json", "/api/v1/status" -> json("200 OK", Nightscout.status(version))
            "/pebble" -> {
                onPebbleRequest()
                val count = query["count"]?.toIntOrNull() ?: 1
                val mmol = (query["units"] ?: "").lowercase().startsWith("mmol")
                json("200 OK", Nightscout.pebble(d.readings, d.snapshot, d.uploaderBattery, count, mmol))
            }
            "/", "/api/v1" -> json("200 OK", mapOf(
                "name" to "openMinipump", "readOnly" to true, "endpoints" to listOf(
                    "/status.html", "/api/v1/entries.json?count=N", "/api/v1/entries/current.json", "/api/v1/devicestatus.json",
                    "/api/v1/treatments.json", "/api/v1/status.json", "/pebble", "/sgv.json",
                ),
            ))
            else -> json("404 Not Found", mapOf("status" to 404, "message" to "not found"))
        }
    }

    /** Supports find[date][$gte|$gt|$lte|$lt]=<ms>, as used by Nightscout clients. */
    private fun filtered(readings: List<GlucoseReading>, query: Map<String, String>): List<GlucoseReading> = readings.filter { r ->
        val ms = Nightscout.millis(r.date).toDouble()
        query["find[date][\$gte]"]?.toDoubleOrNull()?.let { if (ms < it) return@filter false }
        query["find[date][\$gt]"]?.toDoubleOrNull()?.let { if (ms <= it) return@filter false }
        query["find[date][\$lte]"]?.toDoubleOrNull()?.let { if (ms > it) return@filter false }
        query["find[date][\$lt]"]?.toDoubleOrNull()?.let { if (ms >= it) return@filter false }
        true
    }

    private fun basicAuthPassword(headers: Map<String, String>): String? {
        val value = headers["authorization"] ?: return null
        if (!value.lowercase().startsWith("basic ")) return null
        val decoded = try { String(Base64.decode(value.substring(6).trim(), Base64.DEFAULT)) } catch (_: Exception) { return null }
        val colon = decoded.indexOf(':')
        return if (colon < 0) null else decoded.substring(colon + 1)
    }

    private fun authorized(loopback: Boolean, headers: Map<String, String>, query: Map<String, String>): Boolean {
        if (loopback) return true
        if (!allowLan || secret.isEmpty()) return false
        if (basicAuthPassword(headers) == secret) return true
        val given = headers["api-secret"] ?: query["token"] ?: ""
        return given == secret || given.lowercase() == sha1(secret)
    }

    private fun json(status: String, body: Any?): ByteArray =
        raw(status, Json.write(body).toByteArray(), "application/json; charset=utf-8")

    private fun raw(status: String, body: ByteArray, type: String, extra: Map<String, String> = emptyMap()): ByteArray {
        val head = StringBuilder("HTTP/1.1 $status\r\n")
        for ((k, v) in extra) head.append("$k: $v\r\n")
        head.append("Content-Type: $type\r\n")
        head.append("Content-Length: ${body.size}\r\n")
        head.append("Access-Control-Allow-Origin: *\r\n")
        head.append("Access-Control-Allow-Headers: api-secret, authorization, content-type\r\n")
        head.append("Cache-Control: no-store\r\n")
        head.append("Connection: close\r\n\r\n")
        return head.toString().toByteArray() + body
    }

    companion object {
        const val PORT = 17580

        fun sha1(text: String): String =
            MessageDigest.getInstance("SHA-1").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }
    }
}
