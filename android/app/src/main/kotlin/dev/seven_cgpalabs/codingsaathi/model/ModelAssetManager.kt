package dev.seven_cgpalabs.codingsaathi.model

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * ModelAssetManager
 *
 * Checks local storage for all 9 model files and downloads missing assets
 * via resilient background HTTPS downloader with redirect tracking and live progress.
 */
class ModelAssetManager(private val context: Context) {

    companion object {
        private const val TAG = "ModelAssetManager"
        private const val MODELS_DIR = "models"
        private const val DOWNLOAD_CHANNEL_ID = "model_download_channel"
        private const val DOWNLOAD_NOTIF_ID = 2002

        data class ModelSpec(
            val filename: String,
            val url: String,
            val minSizeBytes: Long
        )

<<<<<<< HEAD
        val MODEL_REGISTRY = listOf(
            ModelSpec("qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                500_000_000L),
            ModelSpec("all_minilm_l6_v2.onnx",
                "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx",
                10_000_000L),
            ModelSpec("bge_small_en_v1_5.onnx",
                "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/onnx/model.onnx",
                30_000_000L),
            ModelSpec("bge_reranker_base.onnx",
                "https://huggingface.co/BAAI/bge-reranker-base/resolve/main/onnx/model.onnx",
                50_000_000L),
            ModelSpec("codeberta.onnx",
                "https://huggingface.co/huggingface/CodeBERTa-small-v1/resolve/main/onnx/model.onnx",
                60_000_000L),
            ModelSpec("granite_code_128m.onnx",
                "https://huggingface.co/ibm-granite/granite-3.3-2b-instruct/resolve/main/onnx/model.onnx",
                60_000_000L),
            ModelSpec("nli_deberta_v3_small.onnx",
                "https://huggingface.co/cross-encoder/nli-deberta-v3-small/resolve/main/onnx/model.onnx",
                40_000_000L),
            ModelSpec("codebert_vulnerability.onnx",
                "https://huggingface.co/microsoft/codebert-base/resolve/main/onnx/model.onnx",
                60_000_000L),
            ModelSpec("mobile_diffusion_lcm.onnx",
                "https://huggingface.co/nicjac/lcm-sdxl-onnx/resolve/main/unet/model.onnx",
                100_000_000L)
        )

        /** Model manifest: filename → expected minimum size in bytes. */
        val MODEL_MANIFEST = MODEL_REGISTRY.associate { it.filename to it.minSizeBytes }
=======
        /** Direct CDN/HuggingFace download URLs for all 9 models. */
        val MODEL_URL_MAP = mapOf(
            "qwen2.5-coder-1.5b-q4_k_m.gguf" to "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
            "all_minilm_l6_v2.onnx"           to "https://huggingface.co/optimum/all-MiniLM-L6-v2/resolve/main/model.onnx",
            "bge_small_en_v1_5.onnx"          to "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/onnx/model.onnx",
            "bge_reranker_base.onnx"          to "https://huggingface.co/BAAI/bge-reranker-base/resolve/main/onnx/model.onnx",
            "codeberta.onnx"                  to "https://huggingface.co/huggingface/CodeBERTa-small-v1/resolve/main/onnx/model.onnx",
            "granite_code_128m.onnx"          to "https://huggingface.co/ibm-granite/granite-3b-code-base/resolve/main/onnx/model.onnx",
            "nli_deberta_v3_small.onnx"       to "https://huggingface.co/cross-encoder/nli-deberta-v3-small/resolve/main/onnx/model.onnx",
            "codebert_vulnerability.onnx"     to "https://huggingface.co/mrm8488/codebert-base-finetuned-detect-insecure-code/resolve/main/onnx/model.onnx",
            "mobile_diffusion_lcm.onnx"       to "https://huggingface.co/google/mobilediffusion/resolve/main/model.onnx",
        )

        val downloadProgress = ConcurrentHashMap<String, Int>()
        var isDownloading = false
            private set
>>>>>>> 997efa4 (feat(widget): Revamp ServerTelemetryWidget with enhanced UI and functionality)
    }

    data class ModelStatus(
        val filename: String,
        val present: Boolean,
        val sizeBytes: Long,
        val progressPercent: Int
    )

    private val modelsDir: File
        get() = File(context.filesDir, MODELS_DIR).also { it.mkdirs() }

    private val executor = Executors.newFixedThreadPool(2)

    init {
        createNotificationChannel()
    }

    fun checkAllModels(): List<ModelStatus> {
        return MODEL_MANIFEST.map { (filename, minSize) ->
            val file = File(modelsDir, filename)
            val isPresent = file.exists() && file.length() >= minSize
            val prog = if (isPresent) 100 else (downloadProgress[filename] ?: 0)
            ModelStatus(
                filename = filename,
                present = isPresent,
                sizeBytes = if (file.exists()) file.length() else 0L,
                progressPercent = prog
            )
        }
    }

    fun missingModels(): List<String> {
        return checkAllModels().filter { !it.present }.map { it.filename }
    }

    fun allModelsReady(): Boolean = missingModels().isEmpty()

    fun verifyAndDownloadMissing() {
        val missing = missingModels()
        if (missing.isEmpty()) {
            Log.i(TAG, "All ${MODEL_MANIFEST.size} models present and verified")
            return
        }

        Log.i(TAG, "Starting download for ${missing.size} missing model(s): $missing")
        isDownloading = true

        for (filename in missing) {
            val url = MODEL_URL_MAP[filename] ?: continue
            executor.submit {
                downloadModel(filename, url)
            }
        }
    }

    fun modelsDirectoryPath(): String = modelsDir.absolutePath
    fun modelPath(filename: String): String = File(modelsDir, filename).absolutePath

    private fun downloadModel(filename: String, urlString: String) {
        val dest = File(modelsDir, filename)
        val tempDest = File(modelsDir, "$filename.tmp")

<<<<<<< HEAD
    private fun downloadModel(filename: String) {
        val spec = MODEL_REGISTRY.find { it.filename == filename }
        if (spec != null) {
            Log.i(TAG, "Starting download for ${spec.filename} from ${spec.url}")
            downloadFile(spec.url, File(modelsDir, spec.filename))
        } else {
            Log.w(TAG, "No registry entry found for: $filename")
        }
    }

    @Suppress("unused")
    private fun downloadFile(urlString: String, dest: File) {
=======
>>>>>>> 997efa4 (feat(widget): Revamp ServerTelemetryWidget with enhanced UI and functionality)
        try {
            Log.i(TAG, "Downloading $filename from $urlString")
            updateNotification("Downloading $filename...", 0)

            var currentUrl = urlString
            var connection: HttpURLConnection? = null
            var redirects = 0
            val maxRedirects = 6

            while (redirects < maxRedirects) {
                val url = URL(currentUrl)
                connection = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 30_000
                    readTimeout = 60_000
                    instanceFollowRedirects = true
                    setRequestProperty("User-Agent", "CodingSaathi-AI/1.0 (Android; POCO F6)")
                }

                val status = connection.responseCode
                if (status == HttpURLConnection.HTTP_MOVED_TEMP ||
                    status == HttpURLConnection.HTTP_MOVED_PERM ||
                    status == HttpURLConnection.HTTP_SEE_OTHER ||
                    status == 307 || status == 308) {
                    val newUrl = connection.getHeaderField("Location")
                    connection.disconnect()
                    if (newUrl != null) {
                        currentUrl = newUrl
                        redirects++
                        continue
                    }
                }
                break
            }

            if (connection == null || connection.responseCode != HttpURLConnection.HTTP_OK) {
                Log.e(TAG, "Failed downloading $filename (HTTP ${connection?.responseCode})")
                return
            }

            val totalBytes = connection.contentLengthLong
            var downloadedBytes = 0L

            connection.inputStream.use { input ->
                FileOutputStream(tempDest).use { output ->
                    val buffer = ByteArray(65536)
                    var read: Int
                    var lastNotifTime = 0L

                    while (input.read(buffer).also { read = it } != -1) {
                        output.write(buffer, 0, read)
                        downloadedBytes += read

                        if (totalBytes > 0) {
                            val percent = ((downloadedBytes * 100) / totalBytes).toInt()
                            downloadProgress[filename] = percent

                            val now = System.currentTimeMillis()
                            if (now - lastNotifTime > 1500) {
                                lastNotifTime = now
                                updateNotification("Downloading $filename ($percent%)", percent)
                            }
                        }
                    }
                }
            }

            if (tempDest.renameTo(dest)) {
                downloadProgress[filename] = 100
                Log.i(TAG, "Successfully downloaded $filename (${dest.length()} bytes)")
                updateNotification("Downloaded $filename", 100)
            } else {
                Log.e(TAG, "Failed renaming $tempDest to $dest")
            }

            connection.disconnect()

        } catch (e: Exception) {
            Log.e(TAG, "Error downloading $filename: ${e.message}", e)
            if (tempDest.exists()) tempDest.delete()
        } finally {
            if (missingModels().isEmpty()) {
                isDownloading = false
                cancelNotification()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                DOWNLOAD_CHANNEL_ID,
                "Model Downloads",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows model asset download progress"
                setShowBadge(false)
            }
            val nm = context.getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun updateNotification(title: String, progress: Int) {
        try {
            val notif = NotificationCompat.Builder(context, DOWNLOAD_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("CodingSaathi AI Model Downloader")
                .setContentText(title)
                .setProgress(100, progress, progress <= 0)
                .setOngoing(true)
                .build()

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(DOWNLOAD_NOTIF_ID, notif)
        } catch (_: Exception) {}
    }

    private fun cancelNotification() {
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(DOWNLOAD_NOTIF_ID)
        } catch (_: Exception) {}
    }
}
