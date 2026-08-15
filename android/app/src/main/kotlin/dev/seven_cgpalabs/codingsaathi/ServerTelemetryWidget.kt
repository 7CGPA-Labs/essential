package dev.seven_cgpalabs.codingsaathi

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.widget.RemoteViews

class ServerTelemetryWidget : AppWidgetProvider() {
    companion object {
        const val ACTION_TOGGLE_SERVER = "dev.seven_cgpalabs.codingsaathi.WIDGET_TOGGLE"
        private const val ALARM_ACTION = "dev.seven_cgpalabs.codingsaathi.WIDGET_UPDATE_ALARM"
        
        fun updateAllWidgets(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
            for (appWidgetId in appWidgetIds) {
                val views = buildRemoteViews(context)
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
        
        fun buildRemoteViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_telemetry)
            
            val prefs = context.getSharedPreferences("kingdom_prefs", Context.MODE_PRIVATE)
            val isRunning = prefs.getBoolean("server_was_running", false)
            
            // Top row: status dot
            views.setTextViewText(R.id.tv_status_dot, if (isRunning) "🟢" else "🔴")
            
            // Telemetry grid (mocked/random for now, assuming KingdomState would provide this in reality)
            views.setTextViewText(R.id.tv_cpu_val, "${(10..35).random()}%")
            views.setTextViewText(R.id.tv_ram_val, "${(300..900).random()} MB")
            views.setTextViewText(R.id.tv_gpu_val, "${(5..25).random()}%")
            views.setTextViewText(R.id.tv_npu_val, "${(1..10).random()}ms")
            
            // IP
            val ip = prefs.getString("server_ip", "http://127.0.0.1:8080")
            views.setTextViewText(R.id.tv_ip, ip)
            
            // Toggle Button
            views.setTextViewText(R.id.btn_toggle, if (isRunning) "STOP SERVER" else "START SERVER")
            
            val intent = Intent(context, ServerTelemetryWidget::class.java).apply {
                action = ACTION_TOGGLE_SERVER
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_toggle, pendingIntent)
            
            return views
        }
        
        fun scheduleUpdate(context: Context) {
            val intent = Intent(context, ServerTelemetryWidget::class.java).apply {
                action = ALARM_ACTION
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.setRepeating(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + 10000,
                10000,
                pendingIntent
            )
        }
        
        private fun cancelUpdate(context: Context) {
            val intent = Intent(context, ServerTelemetryWidget::class.java).apply {
                action = ALARM_ACTION
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(pendingIntent)
        }
    }
    
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        updateAllWidgets(context, appWidgetManager, appWidgetIds)
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_TOGGLE_SERVER) {
            val prefs = context.getSharedPreferences("kingdom_prefs", Context.MODE_PRIVATE)
            val wasRunning = prefs.getBoolean("server_was_running", false)
            
            if (wasRunning) {
                // Simulate stopping the server service
                val stopIntent = Intent(context, ServerForegroundService::class.java).apply {
                    action = "STOP_SERVER_ACTION"
                }
                context.startService(stopIntent)
                prefs.edit().putBoolean("server_was_running", false).apply()
            } else {
                // Simulate starting the server service
                val startIntent = Intent(context, ServerForegroundService::class.java)
                context.startForegroundService(startIntent)
                prefs.edit().putBoolean("server_was_running", true).apply()
            }
            
            // Update widget immediately
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, ServerTelemetryWidget::class.java)
            updateAllWidgets(context, appWidgetManager, appWidgetManager.getAppWidgetIds(componentName))
        } else if (intent.action == ALARM_ACTION) {
            // Periodic update
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, ServerTelemetryWidget::class.java)
            updateAllWidgets(context, appWidgetManager, appWidgetManager.getAppWidgetIds(componentName))
        }
    }
    
    override fun onEnabled(context: Context) {
        scheduleUpdate(context)
    }
    
    override fun onDisabled(context: Context) {
        cancelUpdate(context)
    }
}
