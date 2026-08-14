package dev.seven_cgpalabs.codingsaathi

import android.app.Application
import android.util.Log
import dev.seven_cgpalabs.codingsaathi.model.ModelAssetManager

/**
 * KingdomApplication
 *
 * Application entry point for UI-less on-device AI server.
 * Ensures models are verified and background-downloaded whenever any OS surface
 * (Widget, Tile, Foreground Service, or System Settings) initializes the app process.
 */
class KingdomApplication : Application() {

    companion object {
        private const val TAG = "KingdomApp"
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Kingdom AI Server process initializing...")
        // Maintain and download missing model assets on startup
        ModelAssetManager(this).verifyAndDownloadMissing()
    }
}
