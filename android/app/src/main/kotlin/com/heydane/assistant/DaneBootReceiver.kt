package com.heydane.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DaneBootReceiver : BroadcastReceiver() {
    companion object {
        const val PREFS_NAME = "hey_dane_boot_prefs"
        const val KEY_LAST_BOOT_MS = "last_boot_timestamp_ms"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        // Records boot restoration readiness without silently starting microphone recording.
        // Android 14+ prohibits background FGS microphone activation on BOOT_COMPLETED.
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_BOOT_MS, System.currentTimeMillis())
            .apply()
    }
}
