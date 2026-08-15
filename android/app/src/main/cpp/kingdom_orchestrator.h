#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// SSE streaming callback: called once per token chunk
typedef void (*SseStreamCallback)(const char* sse_json_chunk, void* user_data);

// Opaque engine handle
typedef void* KingdomEngineHandle;

// --- Lifecycle ---
// Initialize the entire engine: load LLM, init all ONNX ministers, open DB
// storage_dir: absolute path to models directory
// llm_path: absolute path to .gguf file
// Returns NULL on failure
KingdomEngineHandle kingdom_engine_init(const char* storage_dir, const char* llm_path);

// Returns JSON string: {"llm":"loaded","ministers":8,"db":"open","server_port":8080}
const char* kingdom_engine_status_json(KingdomEngineHandle handle);

// --- Inference ---
// Chat completion with SSE streaming (blocks until generation complete)
void kingdom_engine_process_async(KingdomEngineHandle handle,
                                   const char* prompt,
                                   const char* extra_context,
                                   SseStreamCallback callback,
                                   void* user_data);

// Fast autocomplete via Minister 5 (Granite-Code, sub-30ms)
const char* kingdom_engine_fast_autocomplete(KingdomEngineHandle handle, const char* code_prefix);

// Text embedding via Minister 2 (bge-small-en-v1.5, returns 384-dim JSON array)
const char* kingdom_engine_embed_text(KingdomEngineHandle handle, const char* text);

// --- Telemetry ---
// Returns JSON: {"cpu_pct":45.2,"ram_mb":2048,"gpu_pct":82.1,"vram_mb":512,"npu_latency_ms":7}
const char* kingdom_engine_telemetry_json(KingdomEngineHandle handle);

// --- Logs ---
const char* kingdom_engine_get_recent_logs(KingdomEngineHandle handle, int max_lines);

// --- Server Control ---
bool kingdom_engine_start_server(KingdomEngineHandle handle, int port);
void kingdom_engine_stop_server(KingdomEngineHandle handle);
bool kingdom_engine_is_server_running(KingdomEngineHandle handle);

// --- Cleanup ---
void kingdom_engine_destroy(KingdomEngineHandle handle);

#ifdef __cplusplus
}
#endif
