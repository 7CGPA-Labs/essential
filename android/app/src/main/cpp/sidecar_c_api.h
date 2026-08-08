#ifndef SIDECAR_C_API_H
#define SIDECAR_C_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SidecarResult {
    const char* extracted_code;
    const char* detected_language;
    const char* retrieved_context;
    const char* fully_formatted_prompt;
    int32_t latency_ms;
    int32_t active_ministers;
} SidecarResult;

/**
 * Initializes the ONNX Runtime Sidecar Pipeline with all 4 NPU models.
 */
void* sidecar_init(const char* intent_path,
                   const char* embed_path,
                   const char* reranker_path,
                   const char* lang_path,
                   const char* db_path);

/**
 * Runs the full NPU pipeline: intent → embed → rerank → lang-detect.
 */
SidecarResult* sidecar_process(void* handle,
                               const uint8_t* img_bytes,
                               int32_t img_len,
                               const char* user_query);

/**
 * Frees a SidecarResult struct returned by sidecar_process.
 */
void sidecar_free_result(SidecarResult* result);

/**
 * Destroys the engine instance and releases all ONNX sessions + memory.
 */
void sidecar_destroy(void* handle);

#ifdef __cplusplus
}
#endif

#endif // SIDECAR_C_API_H
