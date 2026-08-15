package dev.seven_cgpalabs.codingsaathi

import android.content.Context
import android.util.Log
import java.io.File

object NativeLibLoader {
    private const val TAG = "NativeLibLoader"
    private var isLoaded = false

    @Synchronized
    fun loadLibraries(context: Context? = null) {
        if (isLoaded) return

        // Stage vendor OpenCL drivers to app private storage to satisfy Android namespace isolation
        if (context != null) {
            try {
                val clDir = File(context.filesDir, "cl").apply { mkdirs() }
                val vendorFiles = listOf("libCB.so", "libOpenCL_adreno.so", "libOpenCL.so")
                for (name in vendorFiles) {
                    val src = File("/vendor/lib64", name)
                    val dst = File(clDir, name)
                    if (src.exists() && (!dst.exists() || dst.length() != src.length())) {
                        src.inputStream().use { input ->
                            dst.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        dst.setExecutable(true, false)
                        dst.setReadable(true, false)
                        Log.i(TAG, "Staged $name to ${dst.absolutePath}")
                    }
                }
            } catch (t: Throwable) {
                Log.w(TAG, "OpenCL staging: ${t.message}")
            }
        }

        val libs = listOf(
            "omp",
            "OpenCL",
            "ggml-base",
            "ggml-cpu",
            "ggml-opencl",
            "ggml",
            "llama",
            "onnxruntime",
            "essential_native"
        )

        for (lib in libs) {
            try {
                System.loadLibrary(lib)
                Log.i(TAG, "Successfully loaded native library: lib$lib.so")
            } catch (t: Throwable) {
                Log.w(TAG, "Could not load lib$lib.so directly: ${t.message}")
            }
        }

        isLoaded = true
    }
}
