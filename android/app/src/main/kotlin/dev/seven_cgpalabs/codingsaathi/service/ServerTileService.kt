package dev.seven_cgpalabs.codingsaathi.service

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.content.Intent
import android.util.Log

/**
 * ServerTileService
 *
 * Quick Settings tile for instant global toggling of the AI server.
 * Appears in the status bar pull-down panel as a toggle button.
 */
class ServerTileService : TileService() {

    companion object {
        private const val TAG = "ServerTileService"
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        val running = ServerForegroundService.nativeIsServerRunning()
        Log.i(TAG, "Tile clicked – server currently ${if (running) "running" else "stopped"}")

        val intent = Intent(this, ServerForegroundService::class.java).apply {
            action = if (running) {
                ServerForegroundService.ACTION_STOP
            } else {
                ServerForegroundService.ACTION_START
            }
        }

        if (!running) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }

        // Refresh tile after a brief delay for state propagation
        qsTile?.let { tile ->
            tile.state = if (!running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = if (!running) "AI Server: ON" else "AI Server: OFF"
            tile.updateTile()
        }
    }

    private fun updateTileState() {
        val running = try {
            ServerForegroundService.nativeIsServerRunning()
        } catch (_: UnsatisfiedLinkError) {
            false
        }

        qsTile?.let { tile ->
            tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            tile.label = if (running) "AI Server: ON" else "AI Server: OFF"
            tile.updateTile()
        }
    }
}
