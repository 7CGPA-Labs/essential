package dev.seven_cgpalabs.codingsaathi

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

class ModelAssetManager(private val context: Context) {
    
    data class ModelSpec(
        val filename: String,
        val url: String,
        val sizeBytes: Long,
        val subdirectory: String = "models"
    )
    
    companion object {
        val MODEL_REGISTRY = listOf(
            ModelSpec("qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                1100_000_000L, ""),
            ModelSpec("all_minilm_l6_v2.onnx",
                "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx",
                25_000_000L),
            ModelSpec("bge_small_en_v1_5.onnx",
                "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/onnx/model.onnx",
                60_000_000L),
            ModelSpec("bge_reranker_base.onnx",
                "https://huggingface.co/BAAI/bge-reranker-base/resolve/main/onnx/model.onnx",
                110_000_000L),
            ModelSpec("codeberta_base.onnx",
                "https://huggingface.co/huggingface/CodeBERTa-small-v1/resolve/main/onnx/model.onnx",
                125_000_000L),
            ModelSpec("nli_deberta_v3_small.onnx",
                "https://huggingface.co/cross-encoder/nli-deberta-v3-small/resolve/main/onnx/model.onnx",
                90_000_000L),
            ModelSpec("granite_code_128m.onnx",
                "https://huggingface.co/ibm-granite/granite-3.3-2b-instruct/resolve/main/onnx/model.onnx",
                130_000_000L),
            ModelSpec("codebert_base.onnx",
                "https://huggingface.co/microsoft/codebert-base/resolve/main/onnx/model.onnx",
                125_000_000L),
            ModelSpec("mobile_diffusion_lcm.onnx",
                "https://huggingface.co/nicjac/lcm-sdxl-onnx/resolve/main/unet/model.onnx",
                280_000_000L)
        )
    }
    
    enum class DownloadStatus { PRESENT, MISSING, DOWNLOADING, FAILED }
    
    fun checkAllModels(): Map<String, DownloadStatus> {
        val result = mutableMapOf<String, DownloadStatus>()
        for (spec in MODEL_REGISTRY) {
            result[spec.filename] = if (verifyModel(spec)) DownloadStatus.PRESENT else DownloadStatus.MISSING
        }
        return result
    }
    
    suspend fun downloadMissingModels(progressCallback: (filename: String, bytesDownloaded: Long, totalBytes: Long) -> Unit) {
        withContext(Dispatchers.IO) {
            for (spec in MODEL_REGISTRY) {
                if (!verifyModel(spec)) {
                    downloadModel(spec, progressCallback)
                }
            }
        }
    }
    
    fun getModelsDirectory(): File {
        return File(context.getExternalFilesDir(null) ?: context.filesDir, "models").apply {
            if (!exists()) mkdirs()
        }
    }
    
    fun getLlmPath(): String {
        return File(context.getExternalFilesDir(null) ?: context.filesDir, "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf").absolutePath
    }
    
    fun verifyModel(spec: ModelSpec): Boolean {
        val dir = if (spec.subdirectory.isEmpty()) {
            context.getExternalFilesDir(null) ?: context.filesDir
        } else {
            File(context.getExternalFilesDir(null) ?: context.filesDir, spec.subdirectory)
        }
        val file = File(dir, spec.filename)
        return file.exists() && file.length() >= (spec.sizeBytes * 0.8).toLong()
    }
    
    private suspend fun downloadModel(spec: ModelSpec, progressCallback: (String, Long, Long) -> Unit) {
        withContext(Dispatchers.IO) {
            val dir = if (spec.subdirectory.isEmpty()) {
                context.getExternalFilesDir(null) ?: context.filesDir
            } else {
                File(context.getExternalFilesDir(null) ?: context.filesDir, spec.subdirectory).apply { if (!exists()) mkdirs() }
            }
            val targetFile = File(dir, spec.filename)
            val tempFile = File(dir, "${spec.filename}.tmp")
            
            try {
                var urlConnection = URL(spec.url).openConnection() as HttpURLConnection
                urlConnection.instanceFollowRedirects = true
                var redirect = false

                val status = urlConnection.responseCode
                if (status != HttpURLConnection.HTTP_OK) {
                    if (status == HttpURLConnection.HTTP_MOVED_TEMP
                        || status == HttpURLConnection.HTTP_MOVED_PERM
                        || status == HttpURLConnection.HTTP_SEE_OTHER) {
                        redirect = true
                    }
                }

                if (redirect) {
                    val newUrl = urlConnection.getHeaderField("Location")
                    urlConnection = URL(newUrl).openConnection() as HttpURLConnection
                }
                
                val totalBytes = urlConnection.contentLengthLong.takeIf { it > 0 } ?: spec.sizeBytes
                var downloadedBytes = 0L
                
                urlConnection.inputStream.use { input ->
                    FileOutputStream(tempFile).use { output ->
                        val buffer = ByteArray(8192)
                        var bytesRead: Int
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            downloadedBytes += bytesRead
                            progressCallback(spec.filename, downloadedBytes, totalBytes)
                        }
                    }
                }
                
                tempFile.renameTo(targetFile)
            } catch (e: Exception) {
                tempFile.delete()
                e.printStackTrace()
            }
        }
    }
}
