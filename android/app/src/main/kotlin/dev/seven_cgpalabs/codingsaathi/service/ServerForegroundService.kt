package dev.seven_cgpalabs.codingsaathi.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import dev.seven_cgpalabs.codingsaathi.settings.AppPreferenceActivity

/**
 * ServerForegroundService
 *
 * Minimal foreground service managing the C++ Kingdom AI Server lifecycle.
 * Displays an ultra-minimal system notification showing only server status:
 *   🟢 AI Server: Active | 8080
 *   🔴 AI Server: Stopped
 */
class ServerForegroundService : Service() {

    companion object {
        private const val TAG = "ServerFgService"
        private const val CHANNEL_ID = "kingdom_server_channel"
        private const val NOTIFICATION_ID = 1001
        const val ACTION_START = "dev.seven_cgpalabs.codingsaathi.ACTION_START_SERVER"
        const val ACTION_STOP  = "dev.seven_cgpalabs.codingsaathi.ACTION_STOP_SERVER"

        init {
            System.loadLibrary("essential_native")
        }

        @JvmStatic private external fun nativeStartServer(storagePath: String, port: Int)
        @JvmStatic private external fun nativeStopServer()
        @JvmStatic external fun nativeIsServerRunning(): Boolean
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startServer()
            ACTION_STOP  -> stopServer()
            else -> {
                // Default: toggle
                if (nativeIsServerRunning()) stopServer() else startServer()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopServer()
        super.onDestroy()
    }

    // ── Server lifecycle ───────────────────────────────────────────────────

    private fun startServer() {
        Log.i(TAG, "Starting Kingdom AI Server…")
        val storagePath = filesDir.absolutePath
        nativeStartServer(storagePath, 8080)
        startForeground(NOTIFICATION_ID, buildNotification(running = true))
        Log.i(TAG, "Server started on port 8080")
    }

    private fun stopServer() {
        Log.i(TAG, "Stopping Kingdom AI Server…")
        nativeStopServer()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i(TAG, "Server stopped")
    }

    // ── Notification ───────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Kingdom AI Server",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "AI Server status"
            setShowBadge(false)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(running: Boolean): Notification {
        val title = if (running) "🟢 AI Server: Active | 8080" else "🔴 AI Server: Stopped"

        val openIntent = Intent(this, AppPreferenceActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Toggle action
        val toggleIntent = Intent(this, ServerForegroundService::class.java).apply {
            action = if (running) ACTION_STOP else ACTION_START
        }
        val togglePending = PendingIntent.getService(
            this, 1, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val toggleLabel = if (running) "Stop" else "Start"

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setSmallIcon(android.R.drawable.ic_menu_manage)
            .setContentIntent(pendingIntent)
            .addAction(Notification.Action.Builder(
                null, toggleLabel, togglePending
            ).build())
            .setOngoing(running)
            .build()
    }
}
