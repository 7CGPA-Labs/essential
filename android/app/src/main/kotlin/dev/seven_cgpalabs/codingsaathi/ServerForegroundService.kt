package dev.seven_cgpalabs.codingsaathi

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.File

class ServerForegroundService : Service() {
    companion object {
        const val ACTION_START = "dev.seven_cgpalabs.codingsaathi.START_SERVER"
        const val ACTION_STOP = "dev.seven_cgpalabs.codingsaathi.STOP_SERVER"
        const val ACTION_SERVER_STATE_CHANGED = "dev.seven_cgpalabs.codingsaathi.SERVER_STATE_CHANGED"
        const val NOTIFICATION_ID = 1001
        const val CHANNEL_ID = "kingdom_server_channel"
        
        fun startIntent(context: Context) = Intent(context, ServerForegroundService::class.java).apply { action = ACTION_START }
        fun stopIntent(context: Context) = Intent(context, ServerForegroundService::class.java).apply { action = ACTION_STOP }
    }
    
    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground()
                coroutineScope.launch {
                    initializeEngine()
                }
            }
            ACTION_STOP -> {
                shutdownEngine()
                stopSelf()
            }
        }
        return START_STICKY
    }
    
    override fun onDestroy() {
        shutdownEngine()
        coroutineScope.cancel()
        super.onDestroy()
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    private fun startForeground() {
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification(false))
    }
    
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Kingdom AI Server",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Runs the on-device AI server"
        }
        val notificationManager: NotificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }
    
    private fun buildNotification(isRunning: Boolean): Notification {
        val port = KingdomState.getServerPort(this)
        val contentText = if (isRunning) "🟢 AI Server: Active | $port" else "🔴 AI Server: Stopped"
        
        val stopIntent = PendingIntent.getService(
            this, 0, stopIntent(this),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Kingdom AI Server")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopIntent)
            .setOngoing(true)
            .build()
    }
    
    private fun initializeEngine() {
        val storageDir = getExternalFilesDir(null)?.absolutePath ?: filesDir.absolutePath
        val llmPath = File(storageDir, "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf").absolutePath
        val port = KingdomState.getServerPort(this)

        val handle = KingdomBridge.engineInit(storageDir, llmPath)
        KingdomState.setHandle(handle)
        
        val running = KingdomBridge.engineStartServer(handle, port)
        KingdomState.isServerRunning = running
        
        updateNotification(running)
        sendBroadcast(Intent(ACTION_SERVER_STATE_CHANGED))
    }
    
    private fun shutdownEngine() {
        val handle = KingdomState.getHandle()
        if (handle != 0L) {
            KingdomBridge.engineStopServer(handle)
            KingdomBridge.engineDestroy(handle)
            KingdomState.setHandle(0L)
            KingdomState.isServerRunning = false
            updateNotification(false)
            sendBroadcast(Intent(ACTION_SERVER_STATE_CHANGED))
        }
    }
    
    private fun updateNotification(running: Boolean) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, buildNotification(running))
    }
}
