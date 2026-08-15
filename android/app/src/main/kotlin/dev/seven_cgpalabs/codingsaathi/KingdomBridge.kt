package dev.seven_cgpalabs.codingsaathi

import android.content.Context
import android.content.SharedPreferences

object KingdomBridge {
    init {
        System.loadLibrary("essential_native")
    }
    
    // Lifecycle
    external fun engineInit(storageDir: String, llmPath: String): Long
    external fun engineStatusJson(handle: Long): String
    external fun engineDestroy(handle: Long)
    
    // Inference  
    external fun engineFastAutocomplete(handle: Long, codePrefix: String): String
    external fun engineEmbedText(handle: Long, text: String): String
    
    // Telemetry
    external fun engineTelemetryJson(handle: Long): String
    
    // Logs
    external fun engineGetRecentLogs(handle: Long, maxLines: Int): String
    
    // Server control
    external fun engineStartServer(handle: Long, port: Int): Boolean
    external fun engineStopServer(handle: Long)
    external fun engineIsServerRunning(handle: Long): Boolean
}

object KingdomState {
    var engineHandle: Long = 0
    var isServerRunning: Boolean = false

    @Synchronized
    fun getHandle(): Long = engineHandle

    @Synchronized
    fun setHandle(handle: Long) {
        engineHandle = handle
    }

    fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences("kingdom_prefs", Context.MODE_PRIVATE)
    }

    fun getServerPort(context: Context): Int {
        return getPrefs(context).getInt("server_port", 8080)
    }
}
