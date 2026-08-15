package dev.seven_cgpalabs.codingsaathi

import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.FileProvider
import androidx.preference.Preference
import androidx.preference.PreferenceFragmentCompat
import androidx.preference.SwitchPreferenceCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.NetworkInterface

class AppPreferenceFragment : PreferenceFragmentCompat() {
    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        setPreferencesFromResource(R.xml.preferences, rootKey)
        
        findPreference<Preference>("model_storage_path")?.summary = requireContext().getExternalFilesDir(null)?.absolutePath
        
        findPreference<SwitchPreferenceCompat>("master_server_switch")?.setOnPreferenceChangeListener { _, newValue ->
            val isEnabled = newValue as Boolean
            if (isEnabled) {
                requireContext().startForegroundService(ServerForegroundService.startIntent(requireContext()))
            } else {
                requireContext().startService(ServerForegroundService.stopIntent(requireContext()))
            }
            true
        }
        
        findPreference<Preference>("reverify_models")?.setOnPreferenceClickListener {
            triggerModelDownload()
            true
        }
        
        findPreference<Preference>("process_logs")?.setOnPreferenceClickListener {
            val handle = KingdomState.getHandle()
            val logs = if (handle != 0L) KingdomBridge.engineGetRecentLogs(handle, 50) else "Server not running."
            AlertDialog.Builder(requireContext())
                .setTitle("Recent Logs")
                .setMessage(logs)
                .setPositiveButton("OK", null)
                .show()
            true
        }
        
        findPreference<Preference>("export_diagnostics")?.setOnPreferenceClickListener {
            exportLogs()
            true
        }
        
        findPreference<Preference>("adb_command")?.let { pref ->
            val cmd = "adb forward tcp:8080 tcp:8080"
            pref.summary = cmd
            pref.setOnPreferenceClickListener {
                val clipboard = requireContext().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = ClipData.newPlainText("ADB Command", cmd)
                clipboard.setPrimaryClip(clip)
                Toast.makeText(requireContext(), "Copied to clipboard", Toast.LENGTH_SHORT).show()
                true
            }
        }
    }
    
    override fun onResume() {
        super.onResume()
        updateDynamicSummaries()
        findPreference<SwitchPreferenceCompat>("master_server_switch")?.isChecked = KingdomState.isServerRunning
    }
    
    private fun updateDynamicSummaries() {
        var ip = "127.0.0.1"
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            for (intf in interfaces) {
                for (enumIpAddr in intf.inetAddresses) {
                    if (!enumIpAddr.isLoopbackAddress && enumIpAddr.hostAddress.indexOf(':') < 0) {
                        ip = enumIpAddr.hostAddress
                    }
                }
            }
        } catch (ex: Exception) { }
        
        val port = KingdomState.getServerPort(requireContext())
        findPreference<Preference>("server_ip_port")?.summary = "http://$ip:$port\nhttp://127.0.0.1:$port"
    }
    
    private fun exportLogs() {
        val handle = KingdomState.getHandle()
        val logs = if (handle != 0L) KingdomBridge.engineGetRecentLogs(handle, 500) else "Server not running."
        val file = File(requireContext().cacheDir, "diagnostics.log")
        file.writeText(logs)
        
        val uri = FileProvider.getUriForFile(requireContext(), "${requireContext().packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, "Export Diagnostics"))
    }
    
    private fun triggerModelDownload() {
        Toast.makeText(requireContext(), "Checking models...", Toast.LENGTH_SHORT).show()
        val assetManager = ModelAssetManager(requireContext())
        CoroutineScope(Dispatchers.Main).launch {
            val missing = withContext(Dispatchers.IO) {
                assetManager.checkAllModels().filterValues { it == ModelAssetManager.DownloadStatus.MISSING }
            }
            if (missing.isEmpty()) {
                Toast.makeText(requireContext(), "All models verified!", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(requireContext(), "Downloading missing models...", Toast.LENGTH_SHORT).show()
                assetManager.downloadMissingModels { filename, downloaded, total ->
                    // Here we could update UI or notifications
                }
            }
        }
    }
}
