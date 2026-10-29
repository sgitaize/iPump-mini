// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.content.Context
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import androidx.test.core.app.ApplicationProvider
import com.github.takahirom.roborazzi.captureRoboImage
import de.sgitaize.openminipump.ui.AlarmSettingsScreen
import de.sgitaize.openminipump.ui.AppTheme
import de.sgitaize.openminipump.ui.GuideScreen
import de.sgitaize.openminipump.ui.MainScreen
import de.sgitaize.openminipump.ui.PairingScreen
import de.sgitaize.openminipump.ui.SettingsScreen
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import kotlin.test.assertTrue

/**
 * Renders the main screens with demo data on the JVM (no device needed). Fails if a screen
 * crashes while composing; with -Pscreenshots=<dir> the PNGs are written there.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class ScreensTest {
    @get:Rule val compose = createComposeRule()

    private val model: AppModel by lazy {
        val app = ApplicationProvider.getApplicationContext<OpenMinipumpApp>()
        app.getSharedPreferences("openminipump", Context.MODE_PRIVATE).edit()
            .putBoolean("demoMode", true).putInt("termsAcceptedVersion", Terms.VERSION).putString("sensorType", "simplera").commit()
        app.model.also { assertTrue(it.demo) }
    }

    private fun capture(name: String) {
        val dir = System.getProperty("omp.screenshots") ?: return
        compose.onRoot().captureRoboImage(File(dir, "$name.png").path)
    }

    @Test
    fun main() {
        compose.setContent { AppTheme("light") { MainScreen(model, 0, {}, {}) } }
        compose.waitForIdle()
        capture("android-main")
    }

    @Test
    fun mainDark() {
        compose.setContent { AppTheme("dark") { MainScreen(model, 0, {}, {}) } }
        compose.waitForIdle()
        capture("android-main-dark")
    }

    @Test
    fun settings() {
        compose.setContent { AppTheme("light") { SettingsScreen(model, {}, {}) } }
        compose.waitForIdle()
        capture("android-settings")
    }

    @Test
    fun guide() {
        compose.setContent { AppTheme("light") { GuideScreen {} } }
        compose.waitForIdle()
        capture("android-guide")
    }

    @Test
    fun widget() {
        val app = ApplicationProvider.getApplicationContext<OpenMinipumpApp>()
        val latest = model.store.latest!!
        val view = GlucoseWidget.views(app).apply(app, android.widget.FrameLayout(app))
        val value = view.findViewById<android.widget.TextView>(R.id.widget_value).text.toString()
        val detail = view.findViewById<android.widget.TextView>(R.id.widget_detail).text.toString()
        kotlin.test.assertEquals(latest.mgdl.toString(), value)
        assertTrue(detail.startsWith("mg/dL"), detail)
    }

    @Test
    fun pairing() {
        compose.setContent { AppTheme("light") { PairingScreen(model) {} } }
        compose.waitForIdle()
        capture("android-pairing")
    }

    @Test
    fun alarms() {
        compose.setContent { AppTheme("light") { AlarmSettingsScreen(model) {} } }
        compose.waitForIdle()
        capture("android-alarms")
    }
}
