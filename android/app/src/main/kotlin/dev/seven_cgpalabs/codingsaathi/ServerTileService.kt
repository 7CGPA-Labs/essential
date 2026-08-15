package dev.seven_cgpalabs.codingsaathi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class ServerTileService : TileService() {
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            updateTile()
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        updateTile()
    }

    override fun onStartListening() {
        super.onStartListening()
        registerReceiver(
            receiver,
            IntentFilter(ServerForegroundService.ACTION_SERVER_STATE_CHANGED),
            Context.RECEIVER_EXPORTED
        )
        updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
        unregisterReceiver(receiver)
    }

    override fun onClick() {
        toggleServer()
    }

    private fun updateTile() {
        val tile = qsTile ?: return
        val isRunning = KingdomState.isServerRunning
        val port = KingdomState.getServerPort(this)

        tile.state = if (isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "AI Server"
        tile.subtitle = if (isRunning) "Port $port" else "Stopped"
        tile.updateTile()
    }

    private fun toggleServer() {
        if (KingdomState.isServerRunning) {
            startService(ServerForegroundService.stopIntent(this))
        } else {
            startForegroundService(ServerForegroundService.startIntent(this))
        }
    }
}
