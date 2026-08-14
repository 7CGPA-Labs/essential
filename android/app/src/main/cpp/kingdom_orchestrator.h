/**
 * kingdom_orchestrator.h
 *
 * Unified C-ABI Facade wrapping the GPU LLM (llama.cpp), NPU ONNX Minister
 * sidecar pipeline, Cognitive Vault (SQLite + sqlite-vec), and the rolling
 * process logger behind a single set of opaque C functions.
 *
 * Consumed by:
 *   - Android Kotlin via JNI
 *   - iOS Swift via C-bridging header
 */
#ifndef KINGDOM_ORCHESTRATOR_H
#define KINGDOM_ORCHESTRATOR_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Opaque handle ──────────────────────────────────────────────────────────── */
typedef void* KingdomEngineHandle;

/* ── SSE streaming callback ─────────────────────────────────────────────────── */
/**
 * Called for every OpenAI-compatible SSE JSON chunk produced during
 * /v1/chat/completions streaming.
 *
 * @param sse_json_chunk  Fully-formed "data: {...}\n\n" string.
 * @param user_data       Opaque pointer forwarded from the caller.
 */
typedef void (*SseStreamCallback)(const char* sse_json_chunk, void* user_data);

/* ── Telemetry snapshot ─────────────────────────────────────────────────────── */
typedef struct KingdomTelemetry {
    float  cpu_percent;
    float  gpu_percent;
    float  npu_percent;
    int64_t ram_used_mb;
    int64_t ram_total_mb;
    int64_t vram_used_mb;
    int64_t vram_total_mb;
    float  npu_latency_ms;
} KingdomTelemetry;

/* ── Server state enum ──────────────────────────────────────────────────────── */
typedef enum {
    KINGDOM_STATE_STOPPED           = 0,
    KINGDOM_STATE_CHECKING_MODELS   = 1,
    KINGDOM_STATE_DOWNLOADING       = 2,
    KINGDOM_STATE_ACTIVE            = 3
} KingdomServerState;

/* ── Lifecycle ──────────────────────────────────────────────────────────────── */

/**
 * Initialise the Kingdom Engine.
 *
 * @param storage_dir  App-private directory (e.g. Context.getFilesDir()).
 * @param llm_path     Absolute path to the Qwen2.5-Coder-1.5B Q4_K_M GGUF.
 * @return Opaque handle (NULL on failure).
 */
KingdomEngineHandle kingdom_engine_init(const char* storage_dir,
                                        const char* llm_path);

/**
 * Destroy the engine and release all GPU / NPU / SQLite resources.
 */
void kingdom_engine_destroy(KingdomEngineHandle handle);

/* ── Inference ──────────────────────────────────────────────────────────────── */

/**
 * Asynchronous chat completion with SSE streaming.
 * Invokes `callback` for every generated token chunk.
 */
void kingdom_engine_process_async(KingdomEngineHandle handle,
                                  const char* prompt,
                                  const char* extra_context,
                                  SseStreamCallback callback,
                                  void* user_data);

/**
 * Synchronous single-line fast autocomplete via Minister 5 (NPU).
 * Returns a heap-allocated JSON string; caller must free().
 */
const char* kingdom_engine_fast_autocomplete(KingdomEngineHandle handle,
                                             const char* code_prefix);

/**
 * Generate dense embeddings via Minister 2 (NPU).
 * Returns a heap-allocated JSON string with the embedding array; caller must free().
 */
const char* kingdom_engine_embed_text(KingdomEngineHandle handle,
                                      const char* text);

/* ── Server daemon ──────────────────────────────────────────────────────────── */

/**
 * Start the cpp-httplib HTTP daemon on the given port.
 * Hosts /v1/chat/completions, /v1/completions, /v1/embeddings.
 */
void kingdom_engine_start_server(KingdomEngineHandle handle, int port);

/**
 * Stop the HTTP daemon.
 */
void kingdom_engine_stop_server(KingdomEngineHandle handle);

/**
 * Returns 1 if the HTTP daemon is accepting requests, 0 otherwise.
 */
int kingdom_engine_is_server_running(KingdomEngineHandle handle);

/* ── Telemetry & logs ───────────────────────────────────────────────────────── */

/**
 * Fill a KingdomTelemetry struct with live system metrics.
 */
void kingdom_engine_get_telemetry(KingdomEngineHandle handle,
                                  KingdomTelemetry* out);

/**
 * Get the current server state.
 */
KingdomServerState kingdom_engine_get_state(KingdomEngineHandle handle);

/**
 * Retrieve the last `max_lines` from the rolling process log.
 * Returns a heap-allocated string; caller must free().
 */
const char* kingdom_engine_get_recent_logs(KingdomEngineHandle handle,
                                           int max_lines);

#ifdef __cplusplus
}
#endif

#endif /* KINGDOM_ORCHESTRATOR_H */
