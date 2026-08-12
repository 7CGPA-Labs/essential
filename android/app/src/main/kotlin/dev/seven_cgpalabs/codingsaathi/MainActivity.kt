package dev.seven_cgpalabs.codingsaathi

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import dev.seven_cgpalabs.codingsaathi.model.ModelAssetManager
import dev.seven_cgpalabs.codingsaathi.service.ServerForegroundService
import dev.seven_cgpalabs.codingsaathi.settings.AppPreferenceActivity

/**
 * MainActivity
 *
 * Thin launcher activity: verifies model assets, starts the AI server
 * foreground service, then hands off to the Settings UI.
 */
class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Ensure model assets are present
        ModelAssetManager(this).verifyAndDownloadMissing()

        // Auto-start the server foreground service
        val serverIntent = Intent(this, ServerForegroundService::class.java).apply {
            action = ServerForegroundService.ACTION_START
        }
        startForegroundService(serverIntent)

        // Open the native Settings UI
        startActivity(Intent(this, AppPreferenceActivity::class.java))
        finish()
    }
}
