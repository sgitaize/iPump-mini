// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import de.sgitaize.openminipump.BuildConfig
import de.sgitaize.openminipump.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import java.net.HttpURLConnection
import java.net.URL

/**
 * The APK from GitHub does not update itself. At most every 12 hours the app asks GitHub for the newest
 * release that contains `ipump-mini.apk` (one request, no tracking) and shows a hint when it is newer.
 * Dismissing applies to exactly that version. Only in the public APK from GitHub (not in Play builds), never talks to the pump.
 */
object Updates {
    const val DOWNLOAD = "https://github.com/sgitaize/iPump-mini/releases/latest/download/ipump-mini.apk"
    private const val RELEASES = "https://api.github.com/repos/sgitaize/iPump-mini/releases?per_page=10"
    private const val APK = "ipump-mini.apk"
    private const val EVERY_MS = 12 * 3600_000L

    var available by mutableStateOf<String?>(null)
        private set

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("updates", Context.MODE_PRIVATE)

    fun check(ctx: Context, scope: CoroutineScope) {
        if (!BuildConfig.PUBLIC_BUILD || !BuildConfig.GITHUB_APK) return
        val p = prefs(ctx)
        if (System.currentTimeMillis() - p.getLong("checkedAt", 0) < EVERY_MS) { show(ctx, p.getString("latest", null)); return }
        scope.launch {
            val latest = withContext(Dispatchers.IO) { runCatching { fetchLatest() }.getOrNull() } ?: return@launch
            p.edit().putLong("checkedAt", System.currentTimeMillis()).putString("latest", latest).apply()
            show(ctx, latest)
        }
    }

    fun dismiss(ctx: Context) {
        available?.let { prefs(ctx).edit().putString("dismissed", it).apply() }
        available = null
    }

    private fun show(ctx: Context, latest: String?) {
        if (latest != null && newer(latest, BuildConfig.VERSION_NAME) && prefs(ctx).getString("dismissed", null) != latest) available = latest
    }

    private fun fetchLatest(): String? {
        val c = URL(RELEASES).openConnection() as HttpURLConnection
        c.connectTimeout = 8000; c.readTimeout = 8000
        c.setRequestProperty("Accept", "application/vnd.github+json")
        c.setRequestProperty("User-Agent", "ipump-mini-android/${BuildConfig.VERSION_NAME}")
        try {
            if (c.responseCode != 200) return null
            val list = JSONArray(c.inputStream.bufferedReader().readText())
            for (i in 0 until list.length()) {
                val r = list.getJSONObject(i)
                if (r.optBoolean("draft")) continue
                val assets = r.optJSONArray("assets") ?: continue
                if ((0 until assets.length()).any { assets.getJSONObject(it).optString("name") == APK }) {
                    return r.optString("tag_name").removePrefix("android-").removePrefix("v").takeIf { it.isNotEmpty() }
                }
            }
            return null
        } finally { c.disconnect() }
    }

    /** "1.0.1" > "1.0.0", "1.0.0" > "1.0.0-beta", "1.0.0-beta.2" > "1.0.0-beta" */
    internal fun newer(a: String, b: String): Boolean {
        fun split(v: String): Pair<List<Int>, String?> {
            val main = v.substringBefore('-'); val pre = v.substringAfter('-', "").ifEmpty { null }
            return main.split('.').map { it.toIntOrNull() ?: 0 } to pre
        }
        val (na, pa) = split(a); val (nb, pb) = split(b)
        for (i in 0 until maxOf(na.size, nb.size)) {
            val x = na.getOrElse(i) { 0 }; val y = nb.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return when {
            pa == null && pb != null -> true
            pa != null && pb == null -> false
            pa != null && pb != null -> pa > pb
            else -> false
        }
    }
}

@Composable
fun UpdateBanner() {
    val version = Updates.available ?: return
    val ctx = LocalContext.current
    CardBox(tint = AppColors.ok.copy(alpha = 0.12f)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.update_available, version), style = MaterialTheme.typography.titleSmall)
                Caption(stringResource(R.string.update_play_pending))
            }
            TextButton({
                ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Updates.DOWNLOAD)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                Updates.dismiss(ctx)
            }) { Text(stringResource(R.string.update_download)) }
            IconButton({ Updates.dismiss(ctx) }) { Icon(Icons.Filled.Close, stringResource(R.string.update_dismiss)) }
        }
    }
}
