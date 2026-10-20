// SPDX-License-Identifier: GPL-3.0-or-later
package de.sgitaize.openminipump

import android.app.Application
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper

class OpenMinipumpApp : Application() {
    val model: AppModel by lazy { AppModel(this) }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        lateinit var instance: OpenMinipumpApp
            private set

        val main = Handler(Looper.getMainLooper())

        fun model(context: Context): AppModel = (context.applicationContext as OpenMinipumpApp).model

        fun string(id: Int, vararg args: Any): String = instance.getString(id, *args)
    }
}

/** Restarts the service after a reboot or an app update, so the pump can reconnect. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val model = OpenMinipumpApp.model(context)
        if (model.termsAccepted && AppModel.hasBluetoothPermissions(context)) PumpService.start(context)
    }
}
