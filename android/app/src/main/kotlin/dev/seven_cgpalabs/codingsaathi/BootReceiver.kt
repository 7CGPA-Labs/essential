package dev.seven_cgpalabs.codingsaathi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val prefs = context.getSharedPreferences("kingdom_prefs", Context.MODE_PRIVATE)
            val wasRunning = prefs.getBoolean("server_was_running", false)
            if (wasRunning) {
                // startForegroundService will throw exception if called from background in modern Android versions,
                // but for native it may be allowed under specific conditions (like BootCompleted).
                // Ensure ServerForegroundService defines startIntent companion method or replace this with appropriate intent.
                try {
                    val startIntent = Intent(context, ServerForegroundService::class.java)
                    context.startForegroundService(startIntent)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
}
