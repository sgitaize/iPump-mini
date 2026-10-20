// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import de.sgitaize.openminipump.AppModel
import de.sgitaize.openminipump.R
import de.sgitaize.openminipump.Units
import de.sgitaize.openminipump.api.LocalApiServer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.Inet4Address
import java.net.NetworkInterface
import java.time.Instant

@Composable
fun SettingsScreen(model: AppModel, open: (Screen) -> Unit, back: () -> Unit) {
    val prefs = model.prefs
    val version by prefs.version.collectAsState()
    @Suppress("UNUSED_VARIABLE") val v = version
    val phase by model.link.phase.collectAsState()
    val serial by model.link.pumpSerial.collectAsState()
    val firmware by model.link.pumpFirmware.collectAsState()
    val apiState by model.apiState.collectAsState()
    val nsOk by model.uploader.lastSuccess.collectAsState()
    val nsError by model.uploader.lastError.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var testResult by remember { mutableStateOf<String?>(null) }
    var testing by remember { mutableStateOf(false) }

    ScreenScaffold(stringResource(R.string.settings), onBack = { model.restartApi(); back() }) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            Collapsible(model, "pump", stringResource(R.string.section_pump), initiallyOpen = true) {
                LabeledRow(stringResource(R.string.name_in_pump), "Mobile ${model.link.advertisedName}")
                LabeledRow(stringResource(R.string.serial), serial ?: "–")
                LabeledRow(stringResource(R.string.firmware), firmware ?: "–")
                LabeledRow(stringResource(R.string.connection), if (model.demo) stringResource(R.string.demo_mode) else stringResource(phase.labelRes))
                if (model.config.devGuard.devMode) LabeledRow(stringResource(R.string.dev_mode), stringResource(R.string.dev_mode_on))
                LinkRow(stringResource(R.string.key_database)) { open(Screen.KEY_IMPORT) }
                LinkRow(stringResource(R.string.pair_pump)) { open(Screen.PAIRING) }
                LinkRow(stringResource(R.string.battery_optimization), stringResource(R.string.battery_optimization_detail)) {
                    context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }
            }

            Collapsible(model, "sensor", stringResource(R.string.section_sensor)) {
                for ((value, label) in listOf("" to R.string.sensor_unset, "simplera" to R.string.sensor_simplera, "guardian" to R.string.sensor_guardian)) {
                    RadioRow(stringResource(label), prefs.sensorType == value) { prefs.sensorType = value }
                }
            }

            Collapsible(model, "ns", "Nightscout") {
                SwitchRow(stringResource(R.string.ns_upload), prefs.nsEnabled) { prefs.nsEnabled = it }
                if (prefs.nsEnabled) {
                    TextSetting(prefs.nsUrl, "https://dein-nightscout.example", KeyboardType.Uri) { prefs.nsUrl = it }
                    TextSetting(prefs.nsSecret, stringResource(R.string.ns_secret_hint), KeyboardType.Password, secret = true) { prefs.nsSecret = it }
                    SwitchRow(stringResource(R.string.ns_devicestatus), prefs.nsDeviceStatus) { prefs.nsDeviceStatus = it }
                    SwitchRow(stringResource(R.string.ns_treatments), prefs.nsTreatments) { prefs.nsTreatments = it }
                    if (prefs.nsTreatments) SwitchRow(stringResource(R.string.ns_auto_basal), prefs.nsAutoBasal) { prefs.nsAutoBasal = it }
                    TextButton(enabled = !testing && prefs.nsUrl.isNotEmpty(), onClick = {
                        testing = true
                        scope.launch {
                            testResult = withContext(Dispatchers.IO) { model.uploader.test() }
                            testing = false
                        }
                    }) { Text(stringResource(if (testing) R.string.testing else R.string.test_connection)) }
                    testResult?.let { Caption(it) }
                    LabeledRow(stringResource(R.string.last_upload), nsOk?.let(::fmtTime) ?: "–")
                    nsError?.let { Caption(it, color = AppColors.low) }
                    TextButton(onClick = { model.uploader.syncAsync() }) { Text(stringResource(R.string.upload_now)) }
                    TextButton(onClick = { model.uploader.resetUploadMarker(); model.uploader.syncAsync() }) { Text(stringResource(R.string.reupload_24h)) }
                }
                Caption(stringResource(R.string.ns_footer))
            }

            Collapsible(model, "api", stringResource(R.string.section_api)) {
                LabeledRow(stringResource(R.string.status), when (apiState) {
                    "lan" -> stringResource(R.string.api_running_lan, LocalApiServer.PORT)
                    "local" -> stringResource(R.string.api_running_local, LocalApiServer.PORT)
                    "error" -> stringResource(R.string.api_error)
                    else -> stringResource(R.string.api_stopped)
                })
                UrlRow(stringResource(R.string.api_on_this_phone), "http://127.0.0.1:${LocalApiServer.PORT}/status.html")
                SwitchRow(stringResource(R.string.api_allow_lan), prefs.apiAllowLan) { prefs.apiAllowLan = it; model.restartApi() }
                if (prefs.apiAllowLan) {
                    TextSetting(prefs.apiSecret, stringResource(R.string.api_secret_hint), KeyboardType.Password, secret = true) {
                        prefs.apiSecret = it
                        model.restartApi()
                    }
                    if (prefs.apiSecret.isEmpty()) {
                        Caption(stringResource(R.string.api_no_secret), color = AppColors.warn)
                    } else {
                        val ip = remember(apiState) { wifiIPv4() }
                        if (ip != null) {
                            UrlRow(stringResource(R.string.api_in_lan), "http://$ip:${LocalApiServer.PORT}/status.html")
                            UrlRow(stringResource(R.string.api_clients), "http://$ip:${LocalApiServer.PORT}")
                        } else {
                            Caption(stringResource(R.string.api_no_wifi), color = AppColors.warn)
                        }
                        Caption(stringResource(R.string.api_basic_auth))
                    }
                }
                SwitchRow(stringResource(R.string.pebble_monitor), prefs.pebbleMonitor) { model.setPebbleMonitor(it) }
                if (prefs.pebbleMonitor) {
                    Stepper(stringResource(R.string.pebble_after, prefs.pebbleMinutes), prefs.pebbleMinutes, 10, 60, 5) { prefs.pebbleMinutes = it }
                    Caption(stringResource(R.string.pebble_footer))
                    LabeledRow(stringResource(R.string.pebble_last), model.pebbleLastRequest.takeIf { it > 0 }?.let { fmtTime(Instant.ofEpochMilli(it)) } ?: "–")
                }
                Caption(stringResource(R.string.api_footer))
            }

            Collapsible(model, "alarms", stringResource(R.string.section_alarms)) {
                LinkRow(stringResource(R.string.alarms_and_notifications), stringResource(R.string.alarms_footer)) { open(Screen.ALARMS) }
            }

            Collapsible(model, "appearance", stringResource(R.string.section_appearance)) {
                Caption(stringResource(R.string.theme))
                for ((value, label) in listOf("system" to R.string.like_system, "light" to R.string.light, "dark" to R.string.dark)) {
                    RadioRow(stringResource(label), prefs.theme == value) { prefs.theme = value }
                }
                if (Build.VERSION.SDK_INT >= 33) {
                    LinkRow(stringResource(R.string.language), stringResource(R.string.language_detail)) {
                        context.startActivity(Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.parse("package:${context.packageName}")))
                    }
                }
                Caption(stringResource(R.string.unit))
                RadioRow("mg/dL", !prefs.unitMmol) { prefs.unitMmol = false }
                RadioRow("mmol/L", prefs.unitMmol) { prefs.unitMmol = true }
                Stepper(stringResource(R.string.range_low, Units.format(prefs.low, prefs.unitMmol)), prefs.low, 60, 100, 5) { prefs.low = it }
                Stepper(stringResource(R.string.range_high, Units.format(prefs.high, prefs.unitMmol)), prefs.high, 120, 250, 10) { prefs.high = it }
                Caption(stringResource(R.string.appearance_footer))
            }

            Collapsible(model, "info", stringResource(R.string.section_info)) {
                SwitchRow(stringResource(R.string.demo_mode), prefs.demoMode) { on -> if (on) model.enterDemo() else prefs.demoMode = false }
                if (prefs.demoMode || model.demo) Caption(stringResource(R.string.demo_footer))
                LinkRow(stringResource(R.string.guide)) { open(Screen.GUIDE) }
                LinkRow(stringResource(R.string.terms)) { open(Screen.TERMS) }
                LinkRow(stringResource(R.string.log)) { open(Screen.LOG) }
                LinkRow(stringResource(R.string.about_title)) { open(Screen.ABOUT) }
            }
        }
    }
}

@Composable
private fun Collapsible(model: AppModel, key: String, title: String, initiallyOpen: Boolean = false, content: @Composable () -> Unit) {
    val sp = model.prefs.sp
    var open by remember { mutableStateOf(sp.getBoolean("settings.$key", initiallyOpen)) }
    Row(
        Modifier.fillMaxWidth().clickable { open = !open; sp.edit().putBoolean("settings.$key", open).apply() }.padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null)
    }
    if (open) Column(Modifier.padding(bottom = 8.dp)) { content() }
    HorizontalDivider()
}

@Composable
fun RadioRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        RadioButton(selected = selected, onClick = onClick)
        Text(label)
    }
}

@Composable
fun Stepper(label: String, value: Int, min: Int, max: Int, step: Int, onChange: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        TextButton(enabled = value - step >= min, onClick = { onChange(value - step) }) { Text("−") }
        TextButton(enabled = value + step <= max, onClick = { onChange(value + step) }) { Text("+") }
    }
}

@Composable
private fun TextSetting(value: String, hint: String, type: KeyboardType, secret: Boolean = false, onCommit: (String) -> Unit) {
    var text by remember { mutableStateOf(value) }
    OutlinedTextField(
        value = text,
        onValueChange = { text = it; onCommit(it.trim()) },
        placeholder = { Text(hint) },
        singleLine = true,
        visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = type),
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
    )
}

@Composable
private fun UrlRow(title: String, url: String) {
    val context = LocalContext.current
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Caption(title)
            Text(url, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
        }
        IconButton(onClick = {
            (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("URL", url))
        }) { Icon(Icons.Filled.ContentCopy, stringResource(R.string.copy_url)) }
    }
}

private fun wifiIPv4(): String? = try {
    NetworkInterface.getNetworkInterfaces().toList()
        .filter { it.isUp && !it.isLoopback && (it.name.startsWith("wlan") || it.name.startsWith("eth")) }
        .flatMap { it.inetAddresses.toList() }
        .firstOrNull { it is Inet4Address }?.hostAddress
} catch (_: Exception) {
    null
}
