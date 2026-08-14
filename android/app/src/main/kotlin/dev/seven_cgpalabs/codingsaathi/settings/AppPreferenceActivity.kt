package dev.seven_cgpalabs.codingsaathi.settings

import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.preference.Preference
import androidx.preference.PreferenceFragmentCompat
import androidx.preference.SwitchPreferenceCompat
import dev.seven_cgpalabs.codingsaathi.R
import dev.seven_cgpalabs.codingsaathi.model.ModelAssetManager
import dev.seven_cgpalabs.codingsaathi.service.ServerForegroundService
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * AppPreferenceActivity
 *
 * Native System Settings UI for the Kingdom AI Server.
 * Renders under Settings → Apps → Kingdom AI Server → App Settings
 * using PreferenceFragmentCompat.
 *
 * Surfaces:
 *   - Model Storage Location (read-only path)
 *   - Server IP & Port
 *   - Master Start/Stop Switch
 *   - Model Re-Verify / Redownload trigger
 *   - Process Log Viewer + Export/Share Intent
 */
class AppPreferenceActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        supportFragmentManager
            .beginTransaction()
            .replace(android.R.id.content, ServerPreferenceFragment())
            .commit()
    }

    class ServerPreferenceFragment : PreferenceFragmentCompat() {

        companion object {
            init {
                System.loadLibrary("essential_native")
            }

            @JvmStatic external fun nativeGetRecentLogs(maxLines: Int): String
            @JvmStatic external fun nativeIsServerRunning(): Boolean
            @JvmStatic external fun nativeGetCpuPercent(): Float
            @JvmStatic external fun nativeGetRamUsedMb(): Long
            @JvmStatic external fun nativeGetRamTotalMb(): Long
            @JvmStatic external fun nativeGetGpuPercent(): Float
            @JvmStatic external fun nativeGetVramUsedMb(): Long
            @JvmStatic external fun nativeGetNpuPercent(): Float
            @JvmStatic external fun nativeGetNpuLatencyMs(): Float
        }

        override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
            setPreferencesFromResource(R.xml.preferences, rootKey)

            val ctx = requireContext()
            val modelsDir = File(ctx.filesDir, "models")

            // ── Model path ─────────────────────────────────────────────────
            findPreference<Preference>("pref_model_path")?.summary =
                modelsDir.absolutePath

            // ── Server IP ──────────────────────────────────────────────────
            val ip = getDeviceIpAddress()
            findPreference<Preference>("pref_server_ip")?.summary =
                "http://$ip:8080"

            // ── Master switch ──────────────────────────────────────────────
            findPreference<SwitchPreferenceCompat>("pref_server_toggle")?.apply {
                isChecked = nativeIsServerRunning()
                setOnPreferenceChangeListener { _, newValue ->
                    val start = newValue as Boolean
                    val intent = Intent(ctx, ServerForegroundService::class.java)
                    if (start) {
                        intent.action = ServerForegroundService.ACTION_START
                        ctx.startForegroundService(intent)
                    } else {
                        intent.action = ServerForegroundService.ACTION_STOP
                        ctx.startService(intent)
                    }
                    view?.postDelayed({ refreshTelemetry() }, 500)
                    true
                }
            }

            // ── Live Telemetry ─────────────────────────────────────────────
            refreshTelemetry()

            // ── Re-download models ─────────────────────────────────────────
            findPreference<Preference>("pref_model_redownload")?.setOnPreferenceClickListener {
                ModelAssetManager(ctx).verifyAndDownloadMissing()
                Toast.makeText(ctx, "Model verification started…", Toast.LENGTH_SHORT).show()
                true
            }

            // ── Log viewer ─────────────────────────────────────────────────
            findPreference<Preference>("pref_log_viewer")?.setOnPreferenceClickListener {
                val logs = nativeGetRecentLogs(100)
                androidx.appcompat.app.AlertDialog.Builder(ctx)
                    .setTitle("Recent Server Logs")
                    .setMessage(logs.ifEmpty { "(no log entries)" })
                    .setPositiveButton("OK", null)
                    .show()
                true
            }

            // ── Export logs ────────────────────────────────────────────────
            findPreference<Preference>("pref_log_export")?.setOnPreferenceClickListener {
                val logFile = File(ctx.filesDir, "server.log")
                if (logFile.exists()) {
                    val uri = FileProvider.getUriForFile(
                        ctx,
                        "${ctx.packageName}.fileprovider",
                        logFile
                    )
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(shareIntent, "Share server.log"))
                } else {
                    Toast.makeText(ctx, "No log file found", Toast.LENGTH_SHORT).show()
                }
                true
            }

            // ── ADB command (copy to clipboard) ────────────────────────────
            findPreference<Preference>("pref_adb_command")?.setOnPreferenceClickListener {
                val clipboard = ctx.getSystemService(android.content.ClipboardManager::class.java)
                clipboard?.setPrimaryClip(
                    android.content.ClipData.newPlainText("ADB", "adb forward tcp:8080 tcp:8080")
                )
                Toast.makeText(ctx, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                true
            }
        }

        override fun onResume() {
            super.onResume()
            refreshTelemetry()
        }

        private fun refreshTelemetry() {
            val running = try { nativeIsServerRunning() } catch (_: Exception) { false }
            val cpu = try { nativeGetCpuPercent() } catch (_: Exception) { 0f }
            val ramUsed = try { nativeGetRamUsedMb() } catch (_: Exception) { 0L }
            val ramTotal = try { nativeGetRamTotalMb() } catch (_: Exception) { 0L }
            val gpu = try { nativeGetGpuPercent() } catch (_: Exception) { 0f }
            val vramUsed = try { nativeGetVramUsedMb() } catch (_: Exception) { 0L }
            val npuPercent = try { nativeGetNpuPercent() } catch (_: Exception) { 0f }
            val npuLatency = try { nativeGetNpuLatencyMs() } catch (_: Exception) { 0f }

            findPreference<Preference>("pref_telemetry_status")?.summary =
                if (running) "🟢 Active (Listening on 0.0.0.0:8080)" else "🔴 Stopped (Offline)"
            findPreference<Preference>("pref_telemetry_cpu")?.summary =
                "%.1f%%".format(cpu)
            findPreference<Preference>("pref_telemetry_ram")?.summary =
                "$ramUsed / $ramTotal MB"
            findPreference<Preference>("pref_telemetry_gpu")?.summary =
                "%.1f%% (OpenCL VRAM: $vramUsed MB)".format(gpu)
            findPreference<Preference>("pref_telemetry_vram")?.summary =
                "$vramUsed MB"
            findPreference<Preference>("pref_telemetry_npu")?.summary =
                "%.0f%% (Latency: %.1f ms)".format(npuPercent, npuLatency)
            findPreference<SwitchPreferenceCompat>("pref_server_toggle")?.isChecked = running
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
            } catch (_: Exception) { }
            return "127.0.0.1"
        }
    }
}
