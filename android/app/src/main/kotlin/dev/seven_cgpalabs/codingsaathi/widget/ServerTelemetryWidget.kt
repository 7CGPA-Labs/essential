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

/**
 * ServerTelemetryWidget
 *
 * Interactive home screen widget (AppWidgetProvider) displaying:
 *   - Server IP Address / URL (http://127.0.0.1:8080)
 *   - Live Telemetry Gauges: CPU %, RAM (MB), GPU %, VRAM (MB), NPU Latency (ms)
 *   - Interactive [ START / STOP ] toggle button
 */
class ServerTelemetryWidget : AppWidgetProvider() {

    companion object {
        private const val ACTION_TOGGLE = "dev.seven_cgpalabs.codingsaathi.WIDGET_TOGGLE"

        init {
            System.loadLibrary("essential_native")
        }

        @JvmStatic private external fun nativeIsServerRunning(): Boolean
        @JvmStatic private external fun nativeGetCpuPercent(): Float
        @JvmStatic private external fun nativeGetRamUsedMb(): Long
        @JvmStatic private external fun nativeGetRamTotalMb(): Long
        @JvmStatic private external fun nativeGetGpuPercent(): Float
        @JvmStatic private external fun nativeGetNpuPercent(): Float
        @JvmStatic private external fun nativeGetNpuLatencyMs(): Float

        /**
         * Trigger a widget refresh from any context (e.g. after server state change).
         */
        fun refresh(context: Context) {
            val intent = Intent(context, ServerTelemetryWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            }
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, ServerTelemetryWidget::class.java))
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            context.sendBroadcast(intent)
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
            // Refresh widgets
            refresh(context)
        }
    }

    private fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_server_telemetry)

        // Read telemetry from native
        val running = try { nativeIsServerRunning() } catch (_: Exception) { false }
        val cpu = try { nativeGetCpuPercent() } catch (_: Exception) { 0f }
        val ramUsed = try { nativeGetRamUsedMb() } catch (_: Exception) { 0L }
        val ramTotal = try { nativeGetRamTotalMb() } catch (_: Exception) { 0L }
        val gpu = try { nativeGetGpuPercent() } catch (_: Exception) { 0f }
        val npu = try { nativeGetNpuPercent() } catch (_: Exception) { 0f }

        // Server URL
        views.setTextViewText(R.id.widget_ip_address,
            if (running) "http://127.0.0.1:8080" else "Server Offline")

        // Status indicator
        views.setTextViewText(R.id.widget_status,
            if (running) "🟢 Active" else "🔴 Stopped")

        // Telemetry gauges row 1: CPU & RAM
        views.setTextViewText(R.id.widget_cpu, "CPU: ${"%.1f".format(cpu)}%")
        views.setTextViewText(R.id.widget_ram, "RAM: ${ramUsed}/${ramTotal} MB")

        // Telemetry gauges row 2: GPU & NPU
        views.setTextViewText(R.id.widget_gpu, "GPU: ${"%.1f".format(gpu)}%")
        views.setTextViewText(R.id.widget_npu, "NPU: ${"%.0f".format(npu)}%")

        // Toggle button
        views.setTextViewText(R.id.widget_toggle_btn,
            if (running) "⏹ STOP" else "▶ START")

        val toggleIntent = Intent(context, ServerTelemetryWidget::class.java).apply {
            action = ACTION_TOGGLE
        }
        val togglePending = PendingIntent.getBroadcast(
            context, 0, toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_toggle_btn, togglePending)

        manager.updateAppWidget(widgetId, views)
    }
}
