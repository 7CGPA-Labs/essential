package dev.seven_cgpalabs.codingsaathi.model

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * ModelAssetManager
 *
 * Checks local storage for all 9 model files and downloads missing assets
 * via background HTTPS downloader.
 *
 * Expected models (inside Context.getFilesDir()/models/):
 *   1. qwen2.5-coder-1.5b-q4_k_m.gguf   (~900 MB) – GPU LLM
 *   2. all_minilm_l6_v2.onnx              (~25 MB)  – Minister 1 Intent Router
 *   3. bge_small_en_v1_5.onnx             (~60 MB)  – Minister 2 Embedder
 *   4. bge_reranker_base.onnx             (~110 MB) – Minister 3 Re-Ranker
 *   5. codeberta.onnx                     (~125 MB) – Minister 4 Code Parser
 *   6. granite_code_128m.onnx             (~130 MB) – Minister 5 Autocomplete
 *   7. nli_deberta_v3_small.onnx          (~90 MB)  – Minister 6 Fact Checker
 *   8. codebert_vulnerability.onnx        (~125 MB) – Minister 7 Security
 *   9. mobile_diffusion_lcm.onnx          (~280 MB) – Minister 8 Diagram Gen
 */
class ModelAssetManager(private val context: Context) {

    companion object {
        private const val TAG = "ModelAssetManager"
        private const val MODELS_DIR = "models"

        /** Model manifest: filename → expected minimum size in bytes. */
        val MODEL_MANIFEST = linkedMapOf(
            "qwen2.5-coder-1.5b-q4_k_m.gguf" to 500_000_000L,
            "all_minilm_l6_v2.onnx"           to 10_000_000L,
            "bge_small_en_v1_5.onnx"          to 30_000_000L,
            "bge_reranker_base.onnx"          to 50_000_000L,
            "codeberta.onnx"                  to 60_000_000L,
            "granite_code_128m.onnx"          to 60_000_000L,
            "nli_deberta_v3_small.onnx"       to 40_000_000L,
            "codebert_vulnerability.onnx"     to 60_000_000L,
            "mobile_diffusion_lcm.onnx"       to 100_000_000L,
        )
    }

    data class ModelStatus(
        val filename: String,
        val present: Boolean,
        val sizeBytes: Long
    )

    private val modelsDir: File
        get() = File(context.filesDir, MODELS_DIR).also { it.mkdirs() }

    private val executor = Executors.newSingleThreadExecutor()

    /**
     * Returns the status of every expected model file.
     */
    fun checkAllModels(): List<ModelStatus> {
        return MODEL_MANIFEST.map { (filename, minSize) ->
            val file = File(modelsDir, filename)
            ModelStatus(
                filename = filename,
                present = file.exists() && file.length() >= minSize,
                sizeBytes = if (file.exists()) file.length() else 0L
            )
        }
    }

    /**
     * Returns the list of model filenames that are missing or corrupt.
     */
    fun missingModels(): List<String> {
        return checkAllModels().filter { !it.present }.map { it.filename }
    }

    /**
     * Returns true if all 9 models are present and valid.
     */
    fun allModelsReady(): Boolean = missingModels().isEmpty()

    /**
     * Verify all models and trigger background download for any missing ones.
     * Downloads are no-ops if a download URL registry is not configured;
     * in production this would read from a manifest JSON hosted on your CDN.
     */
    fun verifyAndDownloadMissing() {
        val missing = missingModels()
        if (missing.isEmpty()) {
            Log.i(TAG, "All ${MODEL_MANIFEST.size} models present and verified")
            return
        }

        Log.i(TAG, "${missing.size} model(s) missing: $missing")
        for (filename in missing) {
            executor.submit {
                downloadModel(filename)
            }
        }
    }

    /**
     * Get the absolute path to the models directory.
     */
    fun modelsDirectoryPath(): String = modelsDir.absolutePath

    /**
     * Get the absolute path to a specific model file.
     */
    fun modelPath(filename: String): String = File(modelsDir, filename).absolutePath

    // ── Private download helper ────────────────────────────────────────────

    private fun downloadModel(filename: String) {
        // In production, resolve the download URL from a manifest JSON.
        // For now, log the missing model as a placeholder.
        Log.w(TAG, "Model download requested for: $filename " +
                   "(configure CDN URL in model_manifest.json)")

        // Example download implementation (commented out until CDN is configured):
        // val url = "https://your-cdn.example.com/models/$filename"
        // downloadFile(url, File(modelsDir, filename))
    }

    @Suppress("unused")
    private fun downloadFile(urlString: String, dest: File) {
        try {
            Log.i(TAG, "Downloading $urlString → ${dest.absolutePath}")
            val url = URL(urlString)
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 30_000
            conn.readTimeout = 60_000
            conn.requestMethod = "GET"

            if (conn.responseCode == HttpURLConnection.HTTP_OK) {
                conn.inputStream.use { input ->
                    FileOutputStream(dest).use { output ->
                        val buffer = ByteArray(8192)
                        var read: Int
                        while (input.read(buffer).also { read = it } != -1) {
                            output.write(buffer, 0, read)
                        }
                    }
                }
                Log.i(TAG, "Downloaded: ${dest.name} (${dest.length()} bytes)")
            } else {
                Log.e(TAG, "HTTP ${conn.responseCode} for $urlString")
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "Download failed: ${e.message}", e)
            if (dest.exists()) dest.delete()
        }
    }
}
