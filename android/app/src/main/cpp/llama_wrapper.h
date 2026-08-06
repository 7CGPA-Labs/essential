#ifndef LLAMA_WRAPPER_H
#define LLAMA_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

// Hardware Backend options (OpenCL Adreno GPU / CPU Fallback)
typedef enum {
    BACKEND_CPU_NEON = 0,
    BACKEND_OPENCL_GPU = 1
} InferenceBackend;

// ── Model lifecycle ──────────────────────────────────────────────────────────

// Load a GGUF model. Returns opaque context pointer (0 on failure).
int64_t essential_init_model(const char* model_path, int32_t backend_type, int32_t threads);
const char* essential_get_gpu_info();
void essential_free_model(int64_t context_ptr);

// ── Per-token streaming API with GBNF Grammar Support ────────────────────────

// Begin generation with optional GBNF grammar constraint string.
// If grammar_str is non-null & non-empty, token sampling will strictly adhere to the GBNF specification.
int64_t essential_start_generation(int64_t context_ptr, const char* prompt, const char* grammar_str, int32_t max_new_tokens);

// Sample and decode exactly one token. Returns the token string.
// Returns NULL when generation is complete (EOS or max tokens reached).
const char* essential_next_token(int64_t gen_ptr);

// Returns true when generation has finished (EOS or max tokens).
bool essential_is_done(int64_t gen_ptr);

// Free the generation state (does NOT free the model context).
void essential_free_generation(int64_t gen_ptr);

#ifdef __cplusplus
}
#endif

#endif // LLAMA_WRAPPER_H
