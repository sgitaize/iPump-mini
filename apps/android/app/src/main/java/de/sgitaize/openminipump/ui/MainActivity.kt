// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import de.sgitaize.openminipump.AppModel
import de.sgitaize.openminipump.OpenMinipumpApp
import de.sgitaize.openminipump.PumpService

enum class Screen { MAIN, SETTINGS, PAIRING, KEY_IMPORT, ALARMS, LOG, ABOUT, TERMS, GUIDE }

class MainActivity : ComponentActivity() {
    private val model: AppModel by lazy { OpenMinipumpApp.model(this) }

    /** Bumped after the permission dialog, so Compose re-checks the permission state. */
    private var permissionTick by mutableStateOf(0)

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        permissionTick++
        startServiceIfReady()
    }

    fun requestPermissions() = permissionLauncher.launch(AppModel.requiredPermissions())

    fun startServiceIfReady() {
        if (model.termsAccepted && AppModel.hasBluetoothPermissions(this)) PumpService.start(this)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        startServiceIfReady()
        setContent {
            val version by model.prefs.version.collectAsState()
            AppTheme(theme = version.let { model.prefs.theme }) {
                var onboarding by remember { mutableStateOf(!model.termsAccepted) }
                val stack = remember { mutableStateListOf(Screen.MAIN) }
                fun push(s: Screen) { stack.add(s) }
                fun pop() { if (stack.size > 1) stack.removeAt(stack.lastIndex) }
                BackHandler(enabled = stack.size > 1) { pop() }

                if (onboarding) {
                    OnboardingScreen(model, permissionTick, ::requestPermissions, onOpen = ::push) {
                        onboarding = false
                        startServiceIfReady()
                    }
                    // Screens opened from the onboarding (key import, pairing, guide) overlay it.
                    if (stack.size > 1) ScreenHost(stack.last(), ::push, ::pop)
                } else {
                    ScreenHost(stack.last(), ::push, ::pop)
                }
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun ScreenHost(screen: Screen, push: (Screen) -> Unit, pop: () -> Unit) {
        when (screen) {
            Screen.MAIN -> MainScreen(model, permissionTick, ::requestPermissions, push)
            Screen.SETTINGS -> SettingsScreen(model, push, pop)
            Screen.PAIRING -> PairingScreen(model, pop)
            Screen.KEY_IMPORT -> KeyImportScreen(model, pop)
            Screen.ALARMS -> AlarmSettingsScreen(model, pop)
            Screen.LOG -> LogScreen(model, pop)
            Screen.ABOUT -> AboutScreen(model, pop)
            Screen.TERMS -> TermsScreen(model, pop)
            Screen.GUIDE -> GuideScreen(pop)
        }
    }

    override fun onResume() {
        super.onResume()
        permissionTick++
        startServiceIfReady()
    }
}
