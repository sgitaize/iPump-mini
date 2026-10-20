// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.sgitaize.minimedkit.GlucoseReading
import de.sgitaize.minimedkit.PumpSnapshot
import de.sgitaize.minimedkit.Treatment
import de.sgitaize.openminipump.AppModel
import de.sgitaize.openminipump.L10n
import de.sgitaize.openminipump.R
import de.sgitaize.openminipump.Units
import de.sgitaize.openminipump.alarms.AlarmEngine
import de.sgitaize.openminipump.ble.PumpLink
import kotlinx.coroutines.delay
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.abs

private val timeFormat: DateTimeFormatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(ZoneId.systemDefault())
fun fmtTime(t: Instant): String = timeFormat.format(t)

/** Recomposes every 30 s so ages ("5 min ago") stay current. */
@Composable
fun rememberNow(): Instant {
    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(30_000)
            now = Instant.now()
        }
    }
    return now
}

@Composable
fun MainScreen(model: AppModel, permissionTick: Int, requestPermissions: () -> Unit, open: (Screen) -> Unit) {
    val readings by model.store.readings.collectAsState()
    val snapshot by model.store.snapshot.collectAsState()
    val treatments by model.store.treatments.collectAsState()
    val version by model.prefs.version.collectAsState()
    val now = rememberNow()
    var glucoseSelection by remember { mutableStateOf<Instant?>(null) }
    var insulinSelection by remember { mutableStateOf<Instant?>(null) }
    val context = LocalContext.current
    val hasPermissions = remember(permissionTick) { AppModel.hasBluetoothPermissions(context) }
    val prefs = model.prefs
    LaunchedEffect(Unit) { Updates.check(context, this) }
    @Suppress("UNUSED_VARIABLE") val v = version // re-read prefs on change

    ScreenScaffold(stringResource(R.string.app_name), onBack = null, actions = {
        IconButton(onClick = { open(Screen.SETTINGS) }) { Icon(Icons.Filled.Settings, stringResource(R.string.settings)) }
    }) { modifier ->
        Column(
            modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            UpdateBanner()
            if (model.demo) {
                CardBox(tint = AppColors.warn.copy(alpha = 0.12f)) {
                    Text(stringResource(R.string.demo_mode), style = MaterialTheme.typography.titleMedium)
                    Caption(stringResource(R.string.demo_banner))
                }
            } else if (!hasPermissions) {
                CardBox(tint = AppColors.warn.copy(alpha = 0.12f)) {
                    Text(stringResource(R.string.permissions_title), style = MaterialTheme.typography.titleMedium)
                    Caption(stringResource(R.string.permissions_text))
                    Button(onClick = requestPermissions) { Text(stringResource(R.string.permissions_grant)) }
                }
            } else {
                StatusBanner(model, now, open)
            }
            SensorAlertBanner(model, snapshot)
            MuteBanner(model)
            SensorTypeCard(model)
            GlucoseHeader(readings, now, prefs.unitMmol, prefs.low, prefs.high)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (h in listOf(3, 6, 12, 24)) {
                    FilterChip(selected = prefs.chartHours == h, onClick = { prefs.chartHours = h }, label = { Text("$h h") })
                }
            }
            GlucoseChart(
                readings, treatments, prefs.chartHours, prefs.unitMmol, prefs.low, prefs.high, now,
                glucoseSelection, insulinSelection,
                onSelectGlucose = { glucoseSelection = it; insulinSelection = null },
                onSelectInsulin = { insulinSelection = it; glucoseSelection = null },
            )
            val selected = glucoseSelection?.let { g -> readings.firstOrNull { it.date == g } }
            val block = insulinSelection?.let { blockFor(it, prefs.chartHours) }
            when {
                selected != null -> GlucosePointDetail(selected, prefs.unitMmol, model.store.iobAt(selected.date), treatments)
                block != null -> InsulinBlockDetail(block.first, block.second, treatments.filter {
                    it.kind.isInsulin && it.date >= block.first && it.date < block.second
                })
                else -> Caption(stringResource(R.string.chart_tap_hint))
            }
            ChartLegend()
            ValueGrid(model, snapshot, now)
            Caption(stringResource(R.string.disclaimer_short))
            TextButton(onClick = { open(Screen.ABOUT) }) { Text(stringResource(R.string.about_title)) }
        }
    }
}

@Composable
private fun StatusBanner(model: AppModel, now: Instant, open: (Screen) -> Unit) {
    val phase by model.link.phase.collectAsState()
    val serial by model.link.pumpSerial.collectAsState()
    val isPaired by model.link.isPaired.collectAsState()
    val waitingSince by model.link.waitingSince.collectAsState()
    val lastData by model.store.lastDataAt.collectAsState()
    val nsOk by model.uploader.lastSuccess.collectAsState()
    val nsError by model.uploader.lastError.collectAsState()
    val color = when (phase) {
        PumpLink.Phase.Connected -> AppColors.ok
        is PumpLink.Phase.Blocked, is PumpLink.Phase.Failed, PumpLink.Phase.BluetoothOff -> AppColors.low
        else -> AppColors.warn
    }
    CardBox {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Dot(color)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(phase.labelRes), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            serial?.let { Caption(it) }
        }
        lastData?.let { Caption(stringResource(R.string.last_data, ageText(it, now))) }
        if (model.prefs.nsEnabled) {
            Caption(nsError ?: nsOk?.let { stringResource(R.string.ns_ok_at, fmtTime(it)) } ?: stringResource(R.string.ns_waiting),
                color = if (nsError != null) AppColors.low else MaterialTheme.colorScheme.onSurfaceVariant)
        }
        (phase as? PumpLink.Phase.Blocked)?.let { Text(it.reason, color = AppColors.low) }
        (phase as? PumpLink.Phase.Failed)?.let { Text(it.reason, color = AppColors.low) }
        if (phase != PumpLink.Phase.Connected) {
            if (isPaired || lastData != null) {
                Caption(stringResource(R.string.paired_waiting))
                val since = waitingSince
                if (since != null && Duration.between(since, now).toMinutes() >= 3) {
                    Caption(stringResource(R.string.no_connection_hint), color = AppColors.warn)
                }
                TextButton(onClick = { open(Screen.PAIRING) }) { Text(stringResource(R.string.repair)) }
            } else {
                Caption(stringResource(R.string.not_paired))
                Button(onClick = { open(Screen.PAIRING) }, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.pair_pump)) }
            }
        }
    }
}

@Composable
fun ageText(t: Instant, now: Instant): String {
    val m = Duration.between(t, now).toMinutes()
    return if (m < 1) stringResource(R.string.just_now) else stringResource(R.string.minutes_ago, m.toInt())
}

@Composable
private fun SensorAlertBanner(model: AppModel, snapshot: PumpSnapshot) {
    val status = snapshot.status ?: return
    if (status.sensorOk || model.demo) return
    CardBox(tint = AppColors.warn.copy(alpha = 0.12f)) {
        Text(stringResource(R.string.sensor_title, L10n.tr(AlarmEngine.sensorText(status))), style = MaterialTheme.typography.titleMedium)
        Caption(stringResource(if (status.sensorMessageState == 0x02) R.string.sensor_updating_body else R.string.sensor_problem_body))
    }
}

@Composable
private fun MuteBanner(model: AppModel) {
    val until by model.alarms.mutedUntil.collectAsState()
    if (until <= System.currentTimeMillis()) return
    CardBox {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.NotificationsOff, null)
            Spacer(Modifier.width(8.dp))
            Text(stringResource(R.string.muted_until, fmtTime(Instant.ofEpochMilli(until))), Modifier.weight(1f))
            TextButton(onClick = { model.alarms.muteAll(null) }) { Text(stringResource(R.string.unmute)) }
        }
    }
}

@Composable
private fun SensorTypeCard(model: AppModel) {
    val isPaired by model.link.isPaired.collectAsState()
    val lastData by model.store.lastDataAt.collectAsState()
    if (model.prefs.sensorType.isNotEmpty() || !(isPaired || lastData != null)) return
    CardBox {
        Text(stringResource(R.string.sensor_question), style = MaterialTheme.typography.titleMedium)
        Caption(stringResource(R.string.sensor_question_detail))
        OutlinedButton(onClick = { model.prefs.sensorType = "simplera" }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.sensor_simplera)) }
        OutlinedButton(onClick = { model.prefs.sensorType = "guardian" }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.sensor_guardian)) }
    }
}

@Composable
private fun GlucoseHeader(readings: List<GlucoseReading>, now: Instant, mmol: Boolean, low: Int, high: Int) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        val r = readings.lastOrNull()
        if (r == null) {
            Text("–", fontSize = 72.sp, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Caption(stringResource(R.string.no_value_yet))
            return
        }
        val stale = Duration.between(r.date, now).toMinutes() > 15
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                Units.format(r.mgdl, mmol), fontSize = 72.sp, fontWeight = FontWeight.Bold,
                color = if (stale) MaterialTheme.colorScheme.onSurfaceVariant else rangeColor(r.mgdl, low, high),
                textDecoration = if (stale) TextDecoration.LineThrough else null,
            )
            Spacer(Modifier.width(8.dp))
            Text(Units.arrow(r.trendMgdlPerMin), fontSize = 40.sp, modifier = Modifier.padding(bottom = 10.dp))
        }
        val delta = if (readings.size >= 2 && Duration.between(readings[readings.size - 2].date, r.date).toMinutes() < 15) {
            r.mgdl - readings[readings.size - 2].mgdl
        } else null
        Caption(listOfNotNull(Units.label(mmol), delta?.let { Units.formatDelta(it, mmol) }, ageText(r.date, now)).joinToString("   "))
    }
}

private fun binMinutes(hours: Int) = if (hours <= 3) 15 else if (hours <= 6) 30 else 60

/** Start and end of the insulin time block containing [t]. */
private fun blockFor(t: Instant, hours: Int): Pair<Instant, Instant> {
    val size = binMinutes(hours) * 60L
    val start = t.epochSecond / size * size
    return Instant.ofEpochSecond(start) to Instant.ofEpochSecond(start + size)
}

@Composable
private fun GlucoseChart(
    readings: List<GlucoseReading>,
    treatments: List<Treatment>,
    hours: Int,
    mmol: Boolean,
    low: Int,
    high: Int,
    now: Instant,
    glucoseSelection: Instant?,
    insulinSelection: Instant?,
    onSelectGlucose: (Instant?) -> Unit,
    onSelectInsulin: (Instant?) -> Unit,
) {
    val from = now.minusSeconds(hours * 3600L)
    val points = readings.filter { it.date >= from }
    val events = treatments.filter { it.date >= from }
    val yMax = maxOf(250, (points.maxOfOrNull { it.mgdl } ?: 0) + 40).toDouble()
    val band = 36.0
    val bandTop = 40.0
    val binSec = binMinutes(hours) * 60L
    // Insulin per time block, stacked by kind, scaled into the band at the bottom.
    val order = listOf(Treatment.Kind.AUTO_BASAL to AppColors.autoBasal, Treatment.Kind.AUTO_CORRECTION to AppColors.autoCorrection,
        Treatment.Kind.BOLUS to AppColors.bolus)
    val sums = mutableMapOf<Long, MutableMap<Treatment.Kind, Double>>()
    for (t in treatments) {
        if (!t.kind.isInsulin || t.date < from.minusSeconds(binSec)) continue
        val bin = t.date.epochSecond / binSec * binSec
        val m = sums.getOrPut(bin) { mutableMapOf() }
        m[t.kind] = (m[t.kind] ?: 0.0) + (t.value ?: 0.0)
    }
    val maxTotal = maxOf(1.0, sums.values.maxOfOrNull { it.values.sum() } ?: 1.0)
    val scale = (band - 4) / maxTotal

    val textMeasurer = rememberTextMeasurer()
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    val onSurface = MaterialTheme.colorScheme.onSurface
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val selectionColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.18f)
    val labelStyle = TextStyle(fontSize = 10.sp, color = labelColor)
    val density = androidx.compose.ui.platform.LocalDensity.current
    val axisWidth = with(density) { 30.dp.toPx() }
    val axisHeight = with(density) { 18.dp.toPx() }
    val dot = with(density) { 1.dp.toPx() }
    val dayFormat = DateTimeFormatter.ofPattern("HH:mm", Locale.getDefault()).withZone(ZoneId.systemDefault())

    fun geometry(size: Size) = Pair(size.width - axisWidth, size.height - axisHeight)
    fun timeAt(x: Float, size: Size): Instant {
        val w = geometry(size).first
        return from.plusMillis(((x / w) * hours * 3600_000L).toLong())
    }
    fun valueAt(y: Float, size: Size): Double = (1 - y / geometry(size).second) * yMax
    fun nearest(t: Instant, any: Boolean): GlucoseReading? {
        val n = points.minByOrNull { abs(Duration.between(it.date, t).seconds) } ?: return null
        return if (any || abs(Duration.between(n.date, t).seconds) < hours * 90) n else null
    }

    Box(Modifier.fillMaxWidth().height(240.dp)) {
        Canvas(
            Modifier.fillMaxSize()
                .pointerInput(points, treatments, hours) {
                    detectTapGestures { pos ->
                        val t = timeAt(pos.x, Size(size.width.toFloat(), size.height.toFloat()))
                        val y = valueAt(pos.y, Size(size.width.toFloat(), size.height.toFloat()))
                        val bin = t.epochSecond / binSec * binSec
                        when {
                            y <= bandTop && sums.containsKey(bin) ->
                                onSelectInsulin(if (insulinSelection != null && blockFor(insulinSelection, hours).first.epochSecond == bin) null else t)
                            y > bandTop -> nearest(t, false).let { n -> onSelectGlucose(if (n == null || n.date == glucoseSelection) null else n.date) }
                            else -> { onSelectGlucose(null); onSelectInsulin(null) }
                        }
                    }
                }
                .pointerInput(points, hours) {
                    // Sliding sideways moves the selection along the values.
                    detectHorizontalDragGestures { change, _ ->
                        val t = timeAt(change.position.x, Size(size.width.toFloat(), size.height.toFloat()))
                        nearest(t, true)?.let { onSelectGlucose(it.date) }
                    }
                },
        ) {
            val (w, h) = geometry(size)
            fun x(t: Instant) = (Duration.between(from, t).toMillis().toFloat() / (hours * 3600_000f)) * w
            fun y(v: Double) = ((1 - v / yMax) * h).toFloat()

            // Target range
            drawRect(AppColors.ok.copy(alpha = 0.12f), Offset(0f, y(high.toDouble())), Size(w, y(low.toDouble()) - y(high.toDouble())))
            // Horizontal grid + labels (every 50 mg/dL, or 3/6/9… mmol/L)
            val lines = if (!mmol) (50..yMax.toInt() step 50).map { it.toDouble() }
            else generateSequence(3.0) { it + 3 }.takeWhile { it * Units.MMOL_FACTOR <= yMax }.map { it * Units.MMOL_FACTOR }.toList()
            for (v in lines) {
                drawLine(gridColor, Offset(0f, y(v)), Offset(w, y(v)), dot / 2)
                val label = if (mmol) "%.0f".format(v / Units.MMOL_FACTOR) else v.toInt().toString()
                val layout = textMeasurer.measure(label, labelStyle)
                drawText(layout, topLeft = Offset(w + 4 * dot, y(v) - layout.size.height / 2f))
            }
            drawLine(gridColor, Offset(0f, y(bandTop)), Offset(w, y(bandTop)), 1f)
            // Hour lines + labels
            val step = (if (hours <= 6) 1 else if (hours <= 12) 2 else 4) * 3600L
            var tick = (from.epochSecond / step + 1) * step
            while (tick < now.epochSecond) {
                val tx = x(Instant.ofEpochSecond(tick))
                drawLine(gridColor, Offset(tx, 0f), Offset(tx, h), 1f)
                val layout = textMeasurer.measure(dayFormat.format(Instant.ofEpochSecond(tick)), labelStyle)
                if (tx + layout.size.width / 2f <= w) drawText(layout, topLeft = Offset(tx - layout.size.width / 2f, h + 2 * dot))
                tick += step
            }
            // Selected insulin block
            insulinSelection?.let { sel ->
                val (s, e) = blockFor(sel, hours)
                drawRect(selectionColor, Offset(x(s), y(bandTop)), Size(x(e) - x(s), h - y(bandTop)))
            }
            // Insulin band
            for ((bin, perKind) in sums) {
                if (bin + binSec <= from.epochSecond) continue
                var base = 0.0
                val x0 = x(Instant.ofEpochSecond(maxOf(bin + binSec / 10, from.epochSecond)))
                val x1 = x(Instant.ofEpochSecond(bin + binSec * 9 / 10))
                for ((kind, color) in order) {
                    val units = perKind[kind] ?: continue
                    if (units <= 0) continue
                    val top = y((base + units) * scale)
                    drawRect(color, Offset(x0, top), Size(maxOf(1f, x1 - x0), y(base * scale) - top))
                    base += units
                }
            }
            // Suspend / resume
            for (t in events.filter { it.kind == Treatment.Kind.SUSPEND || it.kind == Treatment.Kind.RESUME }) {
                drawLine(Color.Gray, Offset(x(t.date), 0f), Offset(x(t.date), h), 1.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
            }
            // Selection line
            glucoseSelection?.let { drawLine(labelColor.copy(alpha = 0.5f), Offset(x(it), 0f), Offset(x(it), h), 1.5f) }
            // Sensor values
            val r = (if (hours > 6) 1.6f else 2.6f) * dot
            for (p in points) {
                val c = if (p.mgdl < low) AppColors.low else if (p.mgdl > high) AppColors.warn else onSurface
                drawCircle(c, if (p.date == glucoseSelection) r * 2 else r, Offset(x(p.date), y(p.mgdl.toDouble())))
            }
            // Carbs (circles), boluses (triangles), BG checks/calibrations (diamonds)
            for (t in events) {
                val tx = x(t.date)
                when (t.kind) {
                    Treatment.Kind.CARBS -> {
                        drawCircle(AppColors.carbs, 5 * dot, Offset(tx, y(yMax - 15)))
                        if (hours <= 6) {
                            val layout = textMeasurer.measure("${(t.value ?: 0.0).toInt()} g", TextStyle(fontSize = 9.sp, color = AppColors.carbs))
                            drawText(layout, topLeft = Offset(tx - layout.size.width / 2f, y(yMax - 15) + 6 * dot))
                        }
                    }
                    Treatment.Kind.BOLUS -> {
                        val cy = y(yMax - 45)
                        val k = 5 * dot
                        drawPath(Path().apply { moveTo(tx, cy - k); lineTo(tx + k, cy + k); lineTo(tx - k, cy + k); close() }, AppColors.bolus)
                        if (hours <= 6) {
                            val layout = textMeasurer.measure("%.1f".format(t.value ?: 0.0), TextStyle(fontSize = 9.sp, color = AppColors.bolus))
                            drawText(layout, topLeft = Offset(tx - layout.size.width / 2f, cy + k + dot))
                        }
                    }
                    Treatment.Kind.BG_CHECK, Treatment.Kind.CALIBRATION -> {
                        val cy = y(t.value ?: 0.0)
                        val k = 5 * dot
                        drawPath(Path().apply { moveTo(tx, cy - k); lineTo(tx + k, cy); lineTo(tx, cy + k); lineTo(tx - k, cy); close() }, AppColors.bg)
                    }
                    else -> {}
                }
            }
        }
        if (points.isEmpty()) {
            Caption(stringResource(R.string.no_values_range), Modifier.align(Alignment.Center))
        }
    }
}

@Composable
private fun Caption(text: String, modifier: Modifier) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier)
}

@Composable
private fun ChartLegend() {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        for ((color, label) in listOf(
            AppColors.bolus to R.string.legend_bolus, AppColors.carbs to R.string.legend_carbs, AppColors.bg to R.string.legend_bg,
            AppColors.autoCorrection to R.string.legend_auto_correction, AppColors.autoBasal to R.string.legend_auto_basal,
        )) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Dot(color, 8)
                Spacer(Modifier.width(3.dp))
                Text(stringResource(label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun kindLabel(k: Treatment.Kind) = stringResource(
    when (k) {
        Treatment.Kind.BOLUS -> R.string.bolus
        Treatment.Kind.AUTO_CORRECTION -> R.string.auto_correction
        else -> R.string.auto_basal
    },
)

private fun kindColor(k: Treatment.Kind) = when (k) {
    Treatment.Kind.BOLUS -> AppColors.bolus
    Treatment.Kind.AUTO_CORRECTION -> AppColors.autoCorrection
    else -> AppColors.autoBasal
}

@Composable
private fun InsulinBlockDetail(start: Instant, end: Instant, items: List<Treatment>) {
    CardBox {
        Row {
            Text("${fmtTime(start)}–${fmtTime(end)}", fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text(Units.insulin(items.sumOf { it.value ?: 0.0 }, 2))
        }
        if (items.isEmpty()) {
            Caption(stringResource(R.string.no_delivery_block))
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (k in listOf(Treatment.Kind.BOLUS, Treatment.Kind.AUTO_CORRECTION, Treatment.Kind.AUTO_BASAL)) {
                    val total = items.filter { it.kind == k }.sumOf { it.value ?: 0.0 }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Dot(kindColor(k), 7)
                        Spacer(Modifier.width(4.dp))
                        Text("${kindLabel(k)} ${"%.2f".format(total)}", style = MaterialTheme.typography.bodySmall,
                            color = if (total > 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            for (t in items.sortedBy { it.date }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Dot(kindColor(t.kind), 6)
                    Spacer(Modifier.width(6.dp))
                    Text(fmtTime(t.date), style = MaterialTheme.typography.bodySmall)
                    Spacer(Modifier.width(8.dp))
                    Text(kindLabel(t.kind), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.weight(1f))
                    Text(Units.insulin(t.value ?: 0.0, 3), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun GlucosePointDetail(r: GlucoseReading, mmol: Boolean, iob: Double?, treatments: List<Treatment>) {
    val window = treatments.filter { it.date > r.date.minusSeconds(300) && it.date <= r.date }
    val insulin = window.filter { it.kind.isInsulin }.sortedBy { it.date }
    val carbs = window.filter { it.kind == Treatment.Kind.CARBS }
    CardBox {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(fmtTime(r.date), fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            Text("${Units.format(r.mgdl, mmol)} ${Units.label(mmol)} ${Units.arrow(r.trendMgdlPerMin)}",
                style = MaterialTheme.typography.titleMedium)
        }
        Caption(listOfNotNull(
            if (mmol) "${r.mgdl} mg/dL" else "%.1f mmol/L".format(r.mgdl / Units.MMOL_FACTOR),
            r.trendMgdlPerMin?.let { "%+.1f/min".format(it) },
            "IOB " + (iob?.let { Units.insulin(it, 2) } ?: "–"),
        ).joinToString("   "))
        if (insulin.isEmpty() && carbs.isEmpty()) {
            Caption(stringResource(R.string.no_delivery_5min))
        } else {
            for (t in insulin) DetailLine(fmtTime(t.date), kindLabel(t.kind), Units.insulin(t.value ?: 0.0, 3))
            for (t in carbs) DetailLine(fmtTime(t.date), stringResource(R.string.carbs), "${(t.value ?: 0.0).toInt()} g")
            if (insulin.size > 1) Text(stringResource(R.string.sum, Units.insulin(insulin.sumOf { it.value ?: 0.0 }, 3)),
                style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun DetailLine(time: String, label: String, value: String) {
    Row {
        Text(time, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun ValueGrid(model: AppModel, s: PumpSnapshot, now: Instant) {
    val firmware by model.link.pumpFirmware.collectAsState()
    val basal = s.basal?.let { b ->
        b.tempBasalUnitsPerHour?.let { Units.insulin(it, 3) + "/h" }
            ?: if (s.algorithm?.isAutoBasal == true) stringResource(R.string.auto) else Units.insulin(b.unitsPerHour, 3) + "/h"
    }
    val basalDetail = when {
        s.basal?.tempBasalUnitsPerHour != null -> stringResource(R.string.temporary)
        s.algorithm?.isAutoBasal == true -> stringResource(R.string.smartguard_controlled)
        else -> null
    }
    val sensorEnd = s.sensorEnd?.let { end ->
        val minutes = Duration.between(now, end).toMinutes().toInt()
        when {
            minutes <= 0 -> stringResource(R.string.expired)
            minutes >= 1440 -> stringResource(R.string.remaining_days, minutes / 1440, minutes % 1440 / 60)
            else -> stringResource(R.string.remaining_hours, minutes / 60, minutes % 60)
        }
    }
    val tiles = buildList<@Composable () -> Unit> {
        add { Tile(stringResource(R.string.tile_iob), s.iob?.let { Units.insulin(it.units, 2) }) }
        add { Tile(stringResource(R.string.tile_reservoir), s.status?.let { Units.insulin(it.reservoirUnits, 0) }) }
        add {
            Tile(stringResource(R.string.tile_mode), s.algorithm?.let { L10n.tr(it.modeDescription) },
                s.status?.let { stringResource(if (it.isSuspended) R.string.delivery_suspended else R.string.delivery_running) })
        }
        add { Tile(stringResource(R.string.tile_basal), basal, basalDetail) }
        add {
            Tile(stringResource(R.string.tile_tir), s.timeInRange?.let { "${it.inRangePercent} %" },
                s.timeInRange?.let { "↑ ${it.abovePercent} %  ↓ ${it.belowPercent} %" })
        }
        add { Tile(stringResource(R.string.tile_pump_battery), s.pumpBatteryPercent?.let { "$it %" }) }
        add {
            Tile(stringResource(R.string.tile_sensor), s.status?.let { if (it.sensorOk) stringResource(R.string.sensor_ok) else L10n.tr(it.sensorMessage) },
                sensorEnd, ok = s.status?.sensorOk)
        }
        if (model.prefs.hasTransmitter) add { Tile(stringResource(R.string.tile_transmitter), s.transmitterBatteryPercent?.let { "$it %" }) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in tiles.chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (t in row) Box(Modifier.weight(1f)) { t() }
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
    if (s.hasData) {
        Caption(stringResource(R.string.pump_status_updated, fmtTime(s.updatedAt)) + (firmware?.let { " · FW $it" } ?: ""))
    }
}

@Composable
private fun Tile(title: String, value: String?, detail: String? = null, ok: Boolean? = null) {
    CardBox {
        Caption(title)
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (ok != null) {
                Icon(if (ok) Icons.Filled.CheckCircle else Icons.Filled.Warning, null,
                    tint = if (ok) AppColors.ok else AppColors.warn, modifier = Modifier.padding(end = 6.dp))
            }
            Text(value ?: "–", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 2)
        }
        if (detail != null) Caption(detail)
    }
}
