// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Router
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Snooze
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import de.sgitaize.minimedkit.KeyDatabase
import de.sgitaize.minimedkit.PumpAlarmCategory
import de.sgitaize.openminipump.AppConfig
import de.sgitaize.openminipump.AppModel
import de.sgitaize.openminipump.EventLog
import de.sgitaize.openminipump.KeyImport
import de.sgitaize.openminipump.R
import de.sgitaize.openminipump.alarms.AlarmConfig
import de.sgitaize.openminipump.alarms.GlucoseAlarmKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Date
import java.util.Locale

private fun openUrl(context: android.content.Context, url: String) {
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    } catch (_: Exception) {
    }
}

// MARK: Pairing

@Composable
fun PairingScreen(model: AppModel, back: () -> Unit) {
    val pairing by model.link.pairingMode.collectAsState()
    val phase by model.link.phase.collectAsState()
    DisposableEffect(Unit) {
        model.link.setPairingMode(true)
        onDispose { if (model.link.pairingMode.value) model.link.setPairingMode(false) }
    }
    val name = "Mobile ${model.link.advertisedName}"
    ScreenScaffold(stringResource(R.string.pairing_title), back) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CardBox {
                Caption(stringResource(R.string.pairing_appears_as))
                Text(name, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 24.sp)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Dot(if (pairing) AppColors.ok else MaterialTheme.colorScheme.outline, 8)
                    Spacer(Modifier.width(6.dp))
                    Text(if (pairing) stringResource(R.string.pairing_active) else stringResource(phase.labelRes))
                }
            }
            SectionHeader(stringResource(R.string.pairing_how))
            val steps = listOf(
                stringResource(R.string.pairing_step1),
                stringResource(R.string.pairing_step2),
                stringResource(R.string.pairing_step3),
                stringResource(R.string.pairing_step4, name),
                stringResource(R.string.pairing_step5),
                stringResource(R.string.pairing_step6),
            )
            steps.forEachIndexed { i, text ->
                Row {
                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), modifier = Modifier.size(26.dp)) {
                        Text("${i + 1}", textAlign = TextAlign.Center, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 3.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Text(text)
                }
            }
            Caption(stringResource(R.string.read_only_note))
        }
    }
}

// MARK: Key database

@Composable
fun KeyImportScreen(model: AppModel, back: () -> Unit) {
    val db by model.link.keyDatabase.collectAsState()
    var hex by remember { mutableStateOf("") }
    var customUrl by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var ok by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val resources = LocalResources.current

    fun done(result: KeyDatabase) {
        model.link.setKeyDatabase(result)
        ok = true
        message = resources.getString(R.string.keydb_saved)
    }
    fun fail(e: Throwable) {
        ok = false
        message = resources.getString(R.string.keydb_invalid, e.message)
    }
    fun load(url: String) {
        loading = true
        message = null
        scope.launch {
            try {
                done(withContext(Dispatchers.IO) { KeyImport.load(model.prefs, url) })
            } catch (e: Exception) {
                fail(e)
            }
            loading = false
        }
    }

    ScreenScaffold(stringResource(R.string.key_database), back) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val status = when {
                db == null -> stringResource(R.string.keydb_status_missing)
                model.config.keyDatabaseSource == AppConfig.KeySource.BUNDLE -> stringResource(R.string.keydb_status_bundle)
                else -> stringResource(R.string.keydb_status_present)
            }
            LabeledRow(stringResource(R.string.status), status)
            Caption(stringResource(R.string.keydb_footer))
            if (model.config.keyDatabaseSource != AppConfig.KeySource.BUNDLE) {
                SectionHeader(stringResource(R.string.keydb_load))
                Button(enabled = !loading, onClick = { load(KeyImport.OPEN_MINIMED_URL) }) {
                    Text(stringResource(if (loading) R.string.loading else R.string.keydb_from_openminimed))
                }
                TextButton(onClick = { openUrl(context, KeyImport.OPEN_MINIMED_PAGE) }) { Text(stringResource(R.string.keydb_view_source)) }
                message?.let { Text(it, color = if (ok) AppColors.ok else AppColors.low, style = MaterialTheme.typography.bodySmall) }
                Caption(stringResource(R.string.keydb_load_footer))

                SectionHeader(stringResource(R.string.keydb_other_url))
                OutlinedTextField(customUrl, { customUrl = it }, placeholder = { Text("https://…") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                TextButton(enabled = !loading && customUrl.trim().startsWith("http"), onClick = { load(customUrl.trim()) }) {
                    Text(stringResource(R.string.keydb_load_url))
                }

                SectionHeader(stringResource(R.string.keydb_paste))
                OutlinedTextField(hex, { hex = it }, modifier = Modifier.fillMaxWidth().heightIn(min = 100.dp),
                    textStyle = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace))
                TextButton(enabled = hex.isNotBlank(), onClick = {
                    try {
                        done(KeyImport.save(model.prefs, KeyImport.extract(hex) ?: hex))
                        hex = ""
                    } catch (e: Exception) {
                        fail(e)
                    }
                }) { Text(stringResource(R.string.keydb_check_save)) }

                if (model.prefs.importedKeyDatabase.isNotEmpty()) {
                    TextButton(onClick = {
                        model.prefs.importedKeyDatabase = ""
                        ok = true
                        message = resources.getString(R.string.keydb_removed)
                    }) { Text(stringResource(R.string.keydb_remove), color = AppColors.low) }
                }
            }
        }
    }
}

// MARK: Alarms

@Composable
fun AlarmSettingsScreen(model: AppModel, back: () -> Unit) {
    val engine = model.alarms
    val config by engine.config.collectAsState()
    val mutedUntil by engine.mutedUntil.collectAsState()
    val context = LocalContext.current
    var refresh by remember { mutableIntStateOf(0) }
    ScreenScaffold(stringResource(R.string.section_alarms), back) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            SectionHeader(stringResource(R.string.preset))
            for (p in AlarmConfig.Preset.entries) {
                Row(Modifier.fillMaxWidth().clickable { engine.applyPreset(p) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(p.titleRes))
                        Caption(stringResource(p.detailRes))
                    }
                    if (config == AlarmConfig.preset(p)) Text("✓", color = MaterialTheme.colorScheme.primary)
                }
            }
            Caption(stringResource(R.string.preset_footer))

            SectionHeader(stringResource(R.string.mute_all))
            if (mutedUntil > System.currentTimeMillis()) {
                LabeledRow(stringResource(R.string.muted_until_label), fmtTime(Instant.ofEpochMilli(mutedUntil)))
                TextButton(onClick = { engine.muteAll(null) }) { Text(stringResource(R.string.unmute_all)) }
            } else {
                TextButton(onClick = { engine.muteAll(60) }) { Text(stringResource(R.string.mute_1h)) }
                TextButton(onClick = { engine.muteAll(120) }) { Text(stringResource(R.string.mute_2h)) }
            }
            Caption(stringResource(R.string.mute_footer))

            SectionHeader(stringResource(R.string.glucose))
            for (kind in GlucoseAlarmKind.entries) {
                val rule = config.glucose.getValue(kind)
                fun set(r: de.sgitaize.openminipump.alarms.AlarmRule) = engine.setConfig(config.copy(glucose = config.glucose + (kind to r)))
                SwitchRow(stringResource(kind.titleRes), rule.enabled) { set(rule.copy(enabled = it)) }
                if (rule.enabled) {
                    if (kind.isRate) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.rate_threshold, "%.1f".format(rule.threshold)), Modifier.weight(1f))
                            TextButton(enabled = rule.threshold > 1.0, onClick = { set(rule.copy(threshold = rule.threshold - 0.5)) }) { Text("−") }
                            TextButton(enabled = rule.threshold < 4.0, onClick = { set(rule.copy(threshold = rule.threshold + 0.5)) }) { Text("+") }
                        }
                    } else {
                        val (min, max) = when (kind) {
                            GlucoseAlarmKind.URGENT_LOW -> 40 to 60
                            GlucoseAlarmKind.LOW -> 60 to 100
                            else -> 150 to 350
                        }
                        val mmol = "%.1f".format(rule.threshold / 18.0182)
                        Stepper(
                            stringResource(if (kind == GlucoseAlarmKind.HIGH) R.string.threshold_above else R.string.threshold_below, rule.threshold.toInt(), mmol),
                            rule.threshold.toInt(), min, max, 5,
                        ) { set(rule.copy(threshold = it.toDouble())) }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Caption(stringResource(R.string.repeat_alarm))
                        for (m in listOf(5, 10, 15, 30, 60)) {
                            TextButton(onClick = { set(rule.copy(repeatMinutes = m)) }) {
                                Text("$m", fontWeight = if (rule.repeatMinutes == m) FontWeight.Bold else FontWeight.Normal,
                                    color = if (rule.repeatMinutes == m) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                HorizontalDivider()
            }

            SwitchRow(stringResource(R.string.no_data), config.noDataEnabled) { engine.setConfig(config.copy(noDataEnabled = it)) }
            if (config.noDataEnabled) {
                Stepper(stringResource(R.string.after_minutes, config.noDataMinutes), config.noDataMinutes, 10, 60, 5) {
                    engine.setConfig(config.copy(noDataMinutes = it))
                }
            }
            Caption(stringResource(R.string.no_data_footer))

            SectionHeader(stringResource(R.string.pump_alerts))
            for (c in PumpAlarmCategory.entries) {
                SwitchRow(stringResource(categoryTitle(c)), config.pump[c] == true) { engine.setConfig(config.copy(pump = config.pump + (c to it))) }
            }
            Caption(stringResource(R.string.pump_alerts_footer))

            SectionHeader(stringResource(R.string.delivery))
            TextButton(onClick = { engine.sendTest() }) { Text(stringResource(R.string.send_test_alarm)) }
            LabeledRow(stringResource(R.string.notifications), stringResource(if (remember(refresh) { engine.notificationsAllowed }) R.string.on else R.string.off))
            TextButton(onClick = {
                refresh++
                context.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
            }) { Text(stringResource(R.string.open_notification_settings)) }
            Caption(stringResource(R.string.delivery_footer))

            SectionHeader(stringResource(R.string.setup_how))
            GuideItem(Icons.Filled.NotificationsActive, stringResource(R.string.alarm_guide1_title), stringResource(R.string.alarm_guide1_text))
            GuideItem(Icons.Filled.Bedtime, stringResource(R.string.alarm_guide2_title), stringResource(R.string.alarm_guide2_text))
            GuideItem(Icons.Filled.Snooze, stringResource(R.string.alarm_guide3_title), stringResource(R.string.alarm_guide3_text))
        }
    }
}

fun categoryTitle(c: PumpAlarmCategory): Int = when (c) {
    PumpAlarmCategory.DELIVERY -> R.string.cat_delivery
    PumpAlarmCategory.SUPPLIES -> R.string.cat_supplies
    PumpAlarmCategory.SENSOR -> R.string.cat_sensor
    PumpAlarmCategory.CALIBRATION -> R.string.cat_calibration
    PumpAlarmCategory.GLUCOSE -> R.string.cat_glucose
    PumpAlarmCategory.SMART_GUARD -> R.string.cat_smartguard
    PumpAlarmCategory.REMINDERS -> R.string.cat_reminders
    PumpAlarmCategory.OTHER -> R.string.cat_other
}

// MARK: Log

@Composable
fun LogScreen(model: AppModel, back: () -> Unit) {
    val entries by model.log.entries.collectAsState()
    val context = LocalContext.current
    val time = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }
    ScreenScaffold(stringResource(R.string.log), back, actions = {
        IconButton(onClick = {
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", model.log.file)
            val share = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            context.startActivity(Intent.createChooser(share, null))
        }) { Icon(Icons.Filled.Share, stringResource(R.string.share_log)) }
    }) { modifier ->
        LazyColumn(modifier.fillMaxSize().padding(horizontal = 12.dp)) {
            items(entries.reversed(), key = { it.id }) { e ->
                Column(Modifier.padding(vertical = 4.dp)) {
                    Caption(time.format(Date(e.date)))
                    Text(e.text, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
                        color = when (e.level) {
                            EventLog.Level.ERROR, EventLog.Level.BLOCKED -> AppColors.low
                            EventLog.Level.WARNING -> AppColors.warn
                            else -> MaterialTheme.colorScheme.onSurface
                        })
                }
                HorizontalDivider()
            }
        }
    }
}

// MARK: About

private object Publisher {
    const val NAME = "Simon Gutjahr"
    const val ADDRESS = "Sachsenstr. 1\n76137 Karlsruhe\nDeutschland"
    const val EMAIL = "kontakt@simongutjahr.de"
    const val PHONE = "0157 81640322"
    const val WEBSITE = "https://simongutjahr.de/dev/"
    const val IMPRINT = "https://simongutjahr.de/impressum/"
    const val PRIVACY = "https://simongutjahr.de/impressum/#ipump-mini"
    const val REPOSITORY = "https://github.com/sgitaize/iPump-mini"
}

@Composable
fun AboutScreen(model: AppModel, back: () -> Unit) {
    val context = LocalContext.current
    ScreenScaffold(stringResource(R.string.about_title), back) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            LabeledRow("App", stringResource(R.string.app_name))
            LabeledRow("Version", model.version)
            LabeledRow(stringResource(R.string.license), "GPL-3.0")
            LinkRow(stringResource(R.string.source_code)) { openUrl(context, Publisher.REPOSITORY) }

            SectionHeader(stringResource(R.string.imprint))
            Text(Publisher.NAME, fontWeight = FontWeight.SemiBold)
            Caption(Publisher.ADDRESS)
            LinkRow(Publisher.EMAIL) { openUrl(context, "mailto:${Publisher.EMAIL}") }
            LinkRow(Publisher.PHONE) { openUrl(context, "tel:" + Publisher.PHONE.filter { it.isDigit() }) }
            LinkRow("simongutjahr.de") { openUrl(context, Publisher.WEBSITE) }
            LinkRow(stringResource(R.string.imprint)) { openUrl(context, Publisher.IMPRINT) }
            LinkRow(stringResource(R.string.privacy_policy)) { openUrl(context, Publisher.PRIVACY) }
            Caption(stringResource(R.string.private_project))

            SectionHeader(stringResource(R.string.important_note))
            Text(stringResource(R.string.about_disclaimer), style = MaterialTheme.typography.bodySmall)

            SectionHeader(stringResource(R.string.sources))
            for ((title, detail, url) in listOf(
                Triple("OpenMinimed", R.string.source_openminimed, "https://github.com/OpenMinimed"),
                Triple("Bluetooth SIG", R.string.source_bluetooth, "https://www.bluetooth.com/specifications/specs/"),
                Triple("Nightscout", R.string.source_nightscout, "https://github.com/nightscout/cgm-remote-monitor"),
                Triple("xDrip+", R.string.source_xdrip, "https://github.com/NightscoutFoundation/xDrip"),
            )) {
                LinkRow(title, stringResource(detail)) { openUrl(context, url) }
            }

            SectionHeader(stringResource(R.string.trademarks))
            Text(stringResource(R.string.trademarks_text), style = MaterialTheme.typography.bodySmall)
            SectionHeader(stringResource(R.string.privacy))
            Text(stringResource(R.string.privacy_text), style = MaterialTheme.typography.bodySmall)
            Spacer(Modifier.size(24.dp))
        }
    }
}

// MARK: Terms

@Composable
fun TermsText() {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        for ((title, text) in listOf(
            R.string.terms1_title to R.string.terms1_text, R.string.terms2_title to R.string.terms2_text,
            R.string.terms3_title to R.string.terms3_text, R.string.terms4_title to R.string.terms4_text,
            R.string.terms5_title to R.string.terms5_text, R.string.terms6_title to R.string.terms6_text,
            R.string.terms7_title to R.string.terms7_text, R.string.terms8_title to R.string.terms8_text,
            R.string.terms9_title to R.string.terms9_text,
        )) {
            Column {
                Text(stringResource(title), fontWeight = FontWeight.SemiBold)
                Text(stringResource(text))
            }
        }
    }
}

@Composable
fun TermsScreen(model: AppModel, back: () -> Unit) {
    ScreenScaffold(stringResource(R.string.terms), back) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            TermsText()
            val at = model.prefs.termsAcceptedAt
            if (at > 0) {
                val f = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.LONG, FormatStyle.SHORT).withZone(ZoneId.systemDefault())
                Caption(stringResource(R.string.terms_accepted_at, f.format(Instant.ofEpochMilli(at)), de.sgitaize.openminipump.Terms.VERSION))
            }
        }
    }
}

// MARK: Guide

@Composable
fun GuideScreen(back: () -> Unit) {
    ScreenScaffold(stringResource(R.string.guide), back) { modifier ->
        Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            SectionHeader(stringResource(R.string.guide_setup))
            GuideItem(Icons.Filled.Key, stringResource(R.string.key_database), stringResource(R.string.guide_keydb))
            GuideItem(Icons.Filled.Link, stringResource(R.string.pair_pump), stringResource(R.string.guide_pair))
            GuideItem(Icons.Filled.Sensors, stringResource(R.string.guide_sensor_title), stringResource(R.string.guide_sensor))
            SectionHeader(stringResource(R.string.guide_background))
            GuideItem(Icons.Filled.PhoneAndroid, stringResource(R.string.guide_service_title), stringResource(R.string.guide_service))
            GuideItem(Icons.Filled.Bluetooth, stringResource(R.string.guide_bt_title), stringResource(R.string.guide_bt))
            GuideItem(Icons.Filled.Refresh, stringResource(R.string.guide_noconn_title), stringResource(R.string.guide_noconn))
            SectionHeader(stringResource(R.string.guide_alarms))
            GuideItem(Icons.Filled.Warning, stringResource(R.string.guide_pump_title), stringResource(R.string.guide_pump), AppColors.warn)
            GuideItem(Icons.Filled.NotificationsActive, stringResource(R.string.alarm_guide1_title), stringResource(R.string.alarm_guide1_text))
            GuideItem(Icons.Filled.Bedtime, stringResource(R.string.alarm_guide2_title), stringResource(R.string.alarm_guide2_text))
            GuideItem(Icons.Filled.AccessTime, stringResource(R.string.alarm_guide3_title), stringResource(R.string.alarm_guide3_text))
            SectionHeader(stringResource(R.string.guide_share))
            GuideItem(Icons.Filled.CloudUpload, "Nightscout", stringResource(R.string.guide_ns))
            GuideItem(Icons.Filled.Router, stringResource(R.string.section_api), stringResource(R.string.guide_api))
            Spacer(Modifier.size(24.dp))
        }
    }
}

// MARK: Onboarding

@Composable
fun OnboardingScreen(model: AppModel, permissionTick: Int, requestPermissions: () -> Unit, onOpen: (Screen) -> Unit, onFinish: () -> Unit) {
    var page by remember { mutableIntStateOf(if (model.termsAccepted) 2 else 0) }
    var demoRequested by remember { mutableStateOf(false) }
    var readTerms by remember { mutableStateOf(false) }
    var understood by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val db by model.link.keyDatabase.collectAsState()
    val isPaired by model.link.isPaired.collectAsState()
    val version by model.prefs.version.collectAsState()
    @Suppress("UNUSED_VARIABLE") val v = version

    when (page) {
        0 -> androidx.compose.material3.Scaffold { padding ->
            Column(
                Modifier.fillMaxSize().padding(padding).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
            ) {
                Icon(painterResource(R.drawable.ic_stat_drop), null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(96.dp))
                Text(stringResource(R.string.app_name), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.welcome_text), textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Button(onClick = { page = 1 }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.next)) }
                TextButton(onClick = { demoRequested = true; page = 1 }) { Text(stringResource(R.string.try_demo)) }
            }
        }
        1 -> ScreenScaffold(stringResource(R.string.terms), onBack = { page = 0 }) { modifier ->
            Column(modifier.fillMaxSize()) {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Caption(stringResource(R.string.terms_intro))
                    TermsText()
                }
                Surface(tonalElevation = 3.dp) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        CheckRow(stringResource(R.string.terms_check1), readTerms) { readTerms = it }
                        CheckRow(stringResource(R.string.terms_check2), understood) { understood = it }
                        Button(enabled = readTerms && understood, modifier = Modifier.fillMaxWidth(), onClick = {
                            model.acceptTerms()
                            if (demoRequested) {
                                model.enterDemo()
                                onFinish()
                            } else {
                                page = 2
                            }
                        }) { Text(stringResource(R.string.agree)) }
                    }
                }
            }
        }
        else -> ScreenScaffold(stringResource(R.string.setup), onBack = null) { modifier ->
            val permissions = remember(permissionTick) { AppModel.hasBluetoothPermissions(context) }
            val notifications = remember(permissionTick) { model.alarms.notificationsAllowed }
            Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
                Caption(stringResource(R.string.setup_later))
                SectionHeader(stringResource(R.string.setup))
                SetupRow(permissions && notifications, stringResource(R.string.permissions_title),
                    stringResource(if (permissions && notifications) R.string.granted else R.string.permissions_needed)) { requestPermissions() }
                SetupRow(db != null, stringResource(R.string.key_database),
                    stringResource(if (db != null) R.string.keydb_status_present else R.string.keydb_load_now)) { onOpen(Screen.KEY_IMPORT) }
                Text(stringResource(R.string.section_sensor), modifier = Modifier.padding(top = 8.dp))
                for ((value, label) in listOf("simplera" to R.string.sensor_simplera, "guardian" to R.string.sensor_guardian)) {
                    RadioRow(stringResource(label), model.prefs.sensorType == value) { model.prefs.sensorType = value }
                }
                SetupRow(isPaired, stringResource(R.string.pair_pump), stringResource(if (isPaired) R.string.paired else R.string.open_guide),
                    enabled = db != null && permissions && !isPaired) { onOpen(Screen.PAIRING) }
                SectionHeader(stringResource(R.string.important))
                GuideItem(Icons.Filled.PhoneAndroid, stringResource(R.string.guide_service_title), stringResource(R.string.guide_service))
                GuideItem(Icons.Filled.Bedtime, stringResource(R.string.alarm_guide2_title), stringResource(R.string.alarm_guide2_text))
                TextButton(onClick = { onOpen(Screen.GUIDE) }) { Text(stringResource(R.string.full_guide)) }
                Button(onClick = onFinish, modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp)) { Text(stringResource(R.string.done)) }
            }
        }
    }
}

@Composable
private fun CheckRow(text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!checked) }, verticalAlignment = Alignment.Top) {
        Checkbox(checked = checked, onCheckedChange = onChange)
        Text(text, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 12.dp))
    }
}
