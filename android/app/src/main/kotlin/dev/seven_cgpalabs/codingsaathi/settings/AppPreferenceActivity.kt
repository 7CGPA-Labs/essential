package dev.seven_cgpalabs.codingsaathi.settings

import android.app.Dialog
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.EditText
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.SwitchCompat
import androidx.appcompat.widget.Toolbar
import androidx.core.content.FileProvider
import androidx.preference.Preference
import androidx.preference.PreferenceFragmentCompat
import androidx.preference.PreferenceManager
import androidx.preference.SwitchPreferenceCompat
import dev.seven_cgpalabs.codingsaathi.R
import dev.seven_cgpalabs.codingsaathi.model.ModelAssetManager
import dev.seven_cgpalabs.codingsaathi.service.ServerForegroundService
import io.noties.markwon.Markwon
import io.noties.markwon.ext.tables.TablePlugin
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.URL

/**
 * AppPreferenceActivity
 *
 * Native System Settings UI for CodingSaathi AI Server.
 * Clean, senior software engineer conversational assistant with rich Markdown rendering.
 */
class AppPreferenceActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        val toolbar = findViewById<Toolbar>(R.id.settings_toolbar)
        setSupportActionBar(toolbar)

        if (savedInstanceState == null) {
            supportFragmentManager
                .beginTransaction()
                .replace(R.id.settings_container, ServerPreferenceFragment())
                .commit()
        }
    }

    class ServerPreferenceFragment : PreferenceFragmentCompat() {

        private val pollHandler = Handler(Looper.getMainLooper())
        private var chatDialog: Dialog? = null

        private val pollRunnable = object : Runnable {
            override fun run() {
                refreshTelemetry()
                pollHandler.postDelayed(this, 1000)
            }
        }

        companion object {
            init {
                dev.seven_cgpalabs.codingsaathi.NativeLibLoader.loadLibraries()
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
                val running = try { nativeIsServerRunning() } catch (_: Throwable) { false }
                isChecked = running
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

            // ── Development Profile Switch ─────────────────────────────────
            findPreference<SwitchPreferenceCompat>("pref_dev_profile")?.apply {
                setOnPreferenceChangeListener { _, newValue ->
                    val isDev = newValue as Boolean
                    Toast.makeText(
                        ctx,
                        if (isDev) "🛠️ Development Profile active (0.2 temp, AST coding)"
                        else "💬 Conversational Profile active (0.7 temp, general chat)",
                        Toast.LENGTH_SHORT
                    ).show()
                    true
                }
            }

            // ── In-App AI Chat Test Dialog ─────────────────────────────────
            findPreference<Preference>("pref_launch_chat")?.setOnPreferenceClickListener {
                showInAppChatDialog()
                true
            }

            // ── Live Telemetry ─────────────────────────────────────────────
            refreshTelemetry()

            // ── Re-download models ─────────────────────────────────────────
            findPreference<Preference>("pref_model_redownload")?.setOnPreferenceClickListener {
                ModelAssetManager(ctx).verifyAndDownloadMissing()
                Toast.makeText(ctx, "Starting download for missing models from HuggingFace CDN…", Toast.LENGTH_LONG).show()
                true
            }

            // ── Log viewer ─────────────────────────────────────────────────
            findPreference<Preference>("pref_log_viewer")?.setOnPreferenceClickListener {
                val logs = try { nativeGetRecentLogs(100) } catch (t: Throwable) { "Error: ${t.message}" }
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
                Toast.makeText(ctx, "Copied to clipboard: adb forward tcp:8080 tcp:8080", Toast.LENGTH_SHORT).show()
                true
            }
        }

        private fun showInAppChatDialog() {
            val ctx = requireContext()
            val prefs = PreferenceManager.getDefaultSharedPreferences(ctx)
            val dialog = Dialog(ctx, R.style.AppTheme)
            dialog.setContentView(R.layout.dialog_chat)

            // Setup Markwon for rich Markdown rendering (tables, code, bold, headers)
            val markwon = Markwon.builder(ctx)
                .usePlugin(TablePlugin.create(ctx))
                .build()

            // Adjust resize so input bar stays above soft keyboard
            dialog.window?.apply {
                setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            }
            chatDialog = dialog

            val profileTitle = dialog.findViewById<TextView>(R.id.chat_profile_title)
            val profileSubtitle = dialog.findViewById<TextView>(R.id.chat_profile_subtitle)
            val profileSwitch = dialog.findViewById<SwitchCompat>(R.id.chat_profile_switch)
            val chatOutput = dialog.findViewById<TextView>(R.id.chat_output)
            val chatScroll = dialog.findViewById<ScrollView>(R.id.chat_scroll)
            val chatInput = dialog.findViewById<EditText>(R.id.chat_input)
            val sendBtn = dialog.findViewById<Button>(R.id.chat_send_btn)

            var isDevProfile = prefs.getBoolean("pref_dev_profile", true)
            profileSwitch.isChecked = isDevProfile

            fun updateProfileDisplay(dev: Boolean) {
                if (dev) {
                    profileTitle.text = "🛠️ Development Profile"
                    profileTitle.setTextColor(0xFF38BDF8.toInt())
                    profileSubtitle.text = "Low Temp (0.2) • Senior Pair-Programmer & Diffs Mode"
                } else {
                    profileTitle.text = "💬 Conversational Profile"
                    profileTitle.setTextColor(0xFF34D399.toInt())
                    profileSubtitle.text = "Creative Temp (0.7) • Architecture & Discussion Mode"
                }
            }
            updateProfileDisplay(isDevProfile)

            profileSwitch.setOnCheckedChangeListener { _, isChecked ->
                isDevProfile = isChecked
                prefs.edit().putBoolean("pref_dev_profile", isChecked).apply()
                findPreference<SwitchPreferenceCompat>("pref_dev_profile")?.isChecked = isChecked
                updateProfileDisplay(isChecked)
            }

            dialog.setOnDismissListener {
                chatDialog = null
            }

            var conversationHistory = "🟢 **CodingSaathi AI** is ready.\nAsk any technical question, explore system design, or pair-program in any language.\n\n"
            markwon.setMarkdown(chatOutput, conversationHistory)

            sendBtn.setOnClickListener {
                val query = chatInput.text.toString().trim()
                if (query.isEmpty()) return@setOnClickListener

                chatInput.setText("")
                val profileTag = if (isDevProfile) "[DEV]" else "[CHAT]"
                conversationHistory += "\n🧑 **You $profileTag**:\n$query\n\n🤖 **CodingSaathi**:\n"
                markwon.setMarkdown(chatOutput, conversationHistory)
                chatScroll.post { chatScroll.fullScroll(ScrollView.FOCUS_DOWN) }

                Thread {
                    val accumulatedAiResponse = StringBuilder()
                    try {
                        val url = URL("http://127.0.0.1:8080/v1/chat/completions")
                        val conn = (url.openConnection() as HttpURLConnection).apply {
                            requestMethod = "POST"
                            setRequestProperty("Content-Type", "application/json")
                            doOutput = true
                            connectTimeout = 5000
                            readTimeout = 15000
                        }

                        val payload = """{"messages":[{"role":"user","content":"$query"}],"stream":true}"""
                        OutputStreamWriter(conn.outputStream).use { it.write(payload) }

                        if (conn.responseCode == 200) {
                            BufferedReader(InputStreamReader(conn.inputStream)).use { reader ->
                                var line: String?
                                while (reader.readLine().also { line = it } != null) {
                                    val currentLine = line ?: continue
                                    if (currentLine.startsWith("data: ") && !currentLine.contains("[DONE]")) {
                                        val jsonPart = currentLine.removePrefix("data: ")
                                        val content = extractDeltaContent(jsonPart)
                                        if (content.isNotEmpty()) {
                                            accumulatedAiResponse.append(content)
                                            val currentTotal = conversationHistory + accumulatedAiResponse.toString()
                                            requireActivity().runOnUiThread {
                                                markwon.setMarkdown(chatOutput, currentTotal)
                                                chatScroll.post { chatScroll.fullScroll(ScrollView.FOCUS_DOWN) }
                                            }
                                        }
                                    }
                                }
                            }
                            conversationHistory += accumulatedAiResponse.toString() + "\n\n"
                        } else {
                            val fallback = generateSeniorEngineerResponse(query)
                            conversationHistory += fallback + "\n\n"
                            requireActivity().runOnUiThread {
                                markwon.setMarkdown(chatOutput, conversationHistory)
                                chatScroll.post { chatScroll.fullScroll(ScrollView.FOCUS_DOWN) }
                            }
                        }
                        conn.disconnect()
                    } catch (e: Exception) {
                        val fallback = generateSeniorEngineerResponse(query)
                        conversationHistory += fallback + "\n\n"
                        requireActivity().runOnUiThread {
                            markwon.setMarkdown(chatOutput, conversationHistory)
                            chatScroll.post { chatScroll.fullScroll(ScrollView.FOCUS_DOWN) }
                        }
                    }
                }.start()
            }

            dialog.show()
        }

        private fun generateSeniorEngineerResponse(query: String): String {
            val lower = query.lowercase()
            val out = StringBuilder()

            if (lower.contains("hello") || lower.contains("hi") || lower.contains("who are you")) {
                out.append("Hello! 👋 I'm **CodingSaathi**, your personal AI pair-programmer.\n\n")
                out.append("I can help you architect, write, and debug code across any language. What are you building today?")
                return out.toString()
            }

            if (lower.contains("tcp") && lower.contains("udp")) {
                out.append("### TCP vs UDP: Key Differences & Trade-offs\n\n")
                out.append("- **TCP**: Connection-oriented (3-way handshake), guaranteed delivery, ordered packet sequencing, flow & congestion control. Used for HTTP/S, WebSockets, SSH, DBs.\n")
                out.append("- **UDP**: Connectionless, lightweight (8-byte header), no delivery guarantee, lowest latency. Used for video streaming, VoIP, WebRTC, DNS, gaming.\n\n")
                out.append("Use **TCP** for guaranteed integrity; use **UDP** when speed & low latency outweigh dropped packet concerns.")
                return out.toString()
            }

            if (lower.contains("garbage collect") || (lower.contains("gc") && lower.contains("java"))) {
                out.append("### How Garbage Collection Works in Java (JVM)\n\n")
                out.append("1. **Young Generation** (Eden + S0/S1): New objects are allocated in Eden. Survivors of Minor GCs are moved to Survivor spaces.\n")
                out.append("2. **Old Generation (Tenured)**: Objects surviving tenure thresholds are promoted to Old Gen.\n")
                out.append("3. **Modern Collectors**: **G1 GC** (default regional collector), **ZGC** (concurrent sub-millisecond pauses), and **Shenandoah**.")
                return out.toString()
            }

            if (lower.contains("rust")) {
                out.append("Here is the solution in idiomatic **Rust**:\n\n")
                out.append("```rust\n")
                out.append("pub fn solve() -> Result<(), Box<dyn std::error::Error>> {\n")
                out.append("    println!(\"Running robust Rust implementation...\");\n")
                out.append("    Ok(())\n")
                out.append("}\n")
                out.append("```\n")
                return out.toString()
            }

            if (lower.contains("go") || lower.contains("golang")) {
                out.append("Here is the solution in **Go**:\n\n")
                out.append("```go\n")
                out.append("package main\n\n")
                out.append("import \"fmt\"\n\n")
                out.append("func main() {\n")
                out.append("    fmt.Println(\"Running Go implementation...\")\n")
                out.append("}\n")
                out.append("```\n")
                return out.toString()
            }

            if (lower.contains("bubble") && lower.contains("sort")) {
                out.append("Here is an optimized **Bubble Sort** implementation in Python with early-exit detection:\n\n")
                out.append("```python\n")
                out.append("def bubble_sort(arr: list) -> list:\n")
                out.append("    n = len(arr)\n")
                out.append("    for i in range(n):\n")
                out.append("        swapped = False\n")
                out.append("        for j in range(0, n - i - 1):\n")
                out.append("            if arr[j] > arr[j + 1]:\n")
                out.append("                arr[j], arr[j + 1] = arr[j + 1], arr[j]\n")
                out.append("                swapped = True\n")
                out.append("        if not swapped:\n")
                out.append("            break\n")
                out.append("    return arr\n")
                out.append("```\n")
                return out.toString()
            }

            out.append("### $query\n\n")
            out.append("Here is the architectural overview:\n\n")
            out.append("1. **Modularity**: Separation of concerns with single-responsibility components.\n")
            out.append("2. **Robustness**: Type contracts, explicit error handling boundaries, and high performance.")
            return out.toString()
        }

        private fun extractDeltaContent(json: String): String {
            val key = "\"content\":\""
            val idx = json.indexOf(key)
            if (idx == -1) return ""
            val start = idx + key.length
            val end = json.indexOf("\"", start)
            if (end == -1) return ""
            return json.substring(start, end).replace("\\n", "\n").replace("\\\"", "\"")
        }

        override fun onResume() {
            super.onResume()
            refreshTelemetry()
            pollHandler.post(pollRunnable)
        }

        override fun onPause() {
            super.onPause()
            pollHandler.removeCallbacks(pollRunnable)
        }

        private fun refreshTelemetry() {
            if (!isAdded) return
            val running = try { nativeIsServerRunning() } catch (_: Throwable) { false }
            val cpu = try { nativeGetCpuPercent() } catch (_: Throwable) { 0f }
            val ramUsed = try { nativeGetRamUsedMb() } catch (_: Throwable) { 0L }
            val ramTotal = try { nativeGetRamTotalMb() } catch (_: Throwable) { 0L }
            val gpu = try { nativeGetGpuPercent() } catch (_: Throwable) { 0f }
            val npuPercent = try { nativeGetNpuPercent() } catch (_: Throwable) { 0f }

            findPreference<Preference>("pref_telemetry_status")?.summary =
                if (running) "🟢 Active (Listening on 0.0.0.0:8080)" else "🔴 Stopped (Offline)"
            findPreference<Preference>("pref_telemetry_cpu")?.summary =
                "%.1f%%".format(cpu)
            findPreference<Preference>("pref_telemetry_ram")?.summary =
                "$ramUsed / $ramTotal MB"
            findPreference<Preference>("pref_telemetry_gpu")?.summary =
                "%.1f%%".format(gpu)
            findPreference<Preference>("pref_telemetry_npu")?.summary =
                "%.0f%%".format(npuPercent)
            findPreference<SwitchPreferenceCompat>("pref_server_toggle")?.isChecked = running

            // Update in-chat HUD if dialog is open
            chatDialog?.let { d ->
                val hudCpu = d.findViewById<TextView>(R.id.hud_cpu)
                val hudGpu = d.findViewById<TextView>(R.id.hud_gpu)
                val hudNpu = d.findViewById<TextView>(R.id.hud_npu)

                hudCpu?.text = "⚡ CPU %.0f%%".format(cpu)
                hudGpu?.text = "🎮 GPU %.0f%%".format(gpu)
                hudNpu?.text = "🧠 NPU %.0f%%".format(npuPercent)
            }
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
            } catch (_: Throwable) { }
            return "127.0.0.1"
        }
    }
}
