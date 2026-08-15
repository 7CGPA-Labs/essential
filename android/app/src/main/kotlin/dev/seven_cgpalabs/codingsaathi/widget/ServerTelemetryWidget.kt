package dev.seven_cgpalabs.codingsaathi.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import dev.seven_cgpalabs.codingsaathi.R
import dev.seven_cgpalabs.codingsaathi.service.ServerForegroundService
import dev.seven_cgpalabs.codingsaathi.settings.AppPreferenceActivity
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * ServerTelemetryWidget
 *
 * Interactive, high-density glassmorphism home screen widget displaying:
 *   - Live Wi-Fi IP Address (e.g. http://192.168.150.101:8080)
 *   - 2x2 Telemetry Grid: CPU %, GPU %, NPU %, System RAM (GB)
 *   - Interactive [ START / STOP ] toggle button
 *   - Interactive [ Chat / Settings ] launcher button
 */
class ServerTelemetryWidget : AppWidgetProvider() {

    companion object {
        const val ACTION_TOGGLE = "dev.seven_cgpalabs.codingsaathi.WIDGET_TOGGLE"

        init {
            dev.seven_cgpalabs.codingsaathi.NativeLibLoader.loadLibraries()
        }

        @JvmStatic private external fun nativeIsServerRunning(): Boolean
        @JvmStatic private external fun nativeGetCpuPercent(): Float
        @JvmStatic private external fun nativeGetRamUsedMb(): Long
        @JvmStatic private external fun nativeGetRamTotalMb(): Long
        @JvmStatic private external fun nativeGetGpuPercent(): Float
        @JvmStatic private external fun nativeGetNpuPercent(): Float

        /**
         * Trigger an immediate widget refresh from any service or activity.
         */
        fun refresh(context: Context) {
            try {
                val intent = Intent(context, ServerTelemetryWidget::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                }
                val manager = AppWidgetManager.getInstance(context) ?: return
                val ids = manager.getAppWidgetIds(ComponentName(context, ServerTelemetryWidget::class.java))
                if (ids != null && ids.isNotEmpty()) {
                    intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    context.sendBroadcast(intent)
                }
            } catch (_: Throwable) {}
        }

        private fun getDeviceIpAddress(): String {
            try {
                val interfaces = NetworkInterface.getNetworkInterfaces()
                while (interfaces.hasMoreElements()) {
                    val iface = interfaces.nextElement()
                    if (iface.isLoopback || !iface.isUp) continue
                    val addrs = iface.inetAddresses
                    while (addrs.hasMoreElements()) {
                        val addr = addrs.nextElement()
                        if (addr is Inet4Address && !addr.isLoopbackAddress) {
                            return addr.hostAddress ?: "127.0.0.1"
                        }
                    }
                }
            } catch (_: Throwable) {}
            return "127.0.0.1"
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            updateWidget(context, manager, id)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TOGGLE) {
            val running = try { nativeIsServerRunning() } catch (_: Exception) { false }
            val serviceIntent = Intent(context, ServerForegroundService::class.java).apply {
                action = if (running) {
                    ServerForegroundService.ACTION_STOP
                } else {
                    ServerForegroundService.ACTION_START
                }
            }
            if (!running) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
            refresh(context)
        }
    }

    private fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_server_telemetry)

        // Read real-time telemetry from native orchestrator
        val running = try { nativeIsServerRunning() } catch (_: Exception) { false }
        val cpu = try { nativeGetCpuPercent() } catch (_: Exception) { 0f }
        val ramUsed = try { nativeGetRamUsedMb() } catch (_: Exception) { 0L }
        val ramTotal = try { nativeGetRamTotalMb() } catch (_: Exception) { 0L }
        val gpu = try { nativeGetGpuPercent() } catch (_: Exception) { 0f }
        val npu = try { nativeGetNpuPercent() } catch (_: Exception) { 0f }
        val ip = getDeviceIpAddress()

        // ── 1. Status & IP Banner ──────────────────────────────────────────
        views.setTextViewText(
            R.id.widget_status,
            if (running) "🟢 Active (8080)" else "🔴 Stopped"
        )
        views.setTextColor(
            R.id.widget_status,
            if (running) 0xFF34D399.toInt() else 0xFFF87171.toInt()
        )
        views.setTextViewText(
            R.id.widget_ip_address,
            if (running) "📡 http://$ip:8080" else "📡 Server Offline"
        )

        // ── 2. 2x2 Telemetry Cards ─────────────────────────────────────────
        views.setTextViewText(R.id.widget_cpu, "%.1f%%".format(cpu))
        views.setTextViewText(R.id.widget_gpu, "%.1f%%".format(gpu))
        views.setTextViewText(R.id.widget_npu, "%.0f%%".format(npu))
        val ramUsedGb = ramUsed / 1024.0
        val ramTotalGb = ramTotal / 1024.0
        views.setTextViewText(R.id.widget_ram, "%.1f/%.1f GB".format(ramUsedGb, ramTotalGb))

        // ── 3. Interactive Buttons ─────────────────────────────────────────
        views.setTextViewText(
            R.id.widget_toggle_btn,
            if (running) "⏹ STOP" else "▶ START"
        )

        // Start/Stop toggle PendingIntent
        val toggleIntent = Intent(context, ServerTelemetryWidget::class.java).apply {
            action = ACTION_TOGGLE
        }
        val togglePending = PendingIntent.getBroadcast(
            context, widgetId * 10 + 1, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_toggle_btn, togglePending)

        // Open Chat / Settings Activity PendingIntent
        val chatIntent = Intent(context, AppPreferenceActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val chatPending = PendingIntent.getActivity(
            context, widgetId * 10 + 2, chatIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_open_chat_btn, chatPending)

        manager.updateAppWidget(widgetId, views)
    }
}
