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
} SidecarResult;

/**
 * Initializes the ONNX Runtime Sidecar Engine & Vector Store.
 * @param lang_path Path to CodeBERTa classifier (.onnx) or empty string
 * @param embed_path Path to bge-small-en-v1.5 (.onnx) or empty string
 * @param db_path Path to local vector database / storage
 * @return Opaque pointer handle to SidecarPipelineCoordinator
 */
void* sidecar_init(const char* lang_path, const char* embed_path, const char* db_path);

/**
 * Processes image input, query, and context vector search concurrently.
 * @param handle Opaque handle from sidecar_init
 * @param img_bytes Pointer to raw image buffer (JPEG/PNG/NV21)
 * @param img_len Length of image buffer in bytes
 * @param user_query User prompt query string
 * @return Allocated SidecarResult pointer (must be freed via sidecar_free_result)
 */
SidecarResult* sidecar_process(void* handle, const uint8_t* img_bytes, int32_t img_len, const char* user_query);

/**
 * Frees memory allocated for a SidecarResult struct.
 */
void sidecar_free_result(SidecarResult* result);

/**
 * Destroys the Sidecar Engine instance and releases ONNX sessions.
 */
void sidecar_destroy(void* handle);

#ifdef __cplusplus
}
#endif

#endif // SIDECAR_C_API_H
