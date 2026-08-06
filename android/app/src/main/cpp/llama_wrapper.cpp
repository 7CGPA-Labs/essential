#include "llama_wrapper.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vector>
#include <android/log.h>
#include "llama.h"

#define LOG_TAG "LlamaWrapper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Internal structs ─────────────────────────────────────────────────────────

typedef struct {
    llama_model*   model;
    llama_context* ctx;
    int32_t        n_threads;
} ModelContext;

typedef struct {
    ModelContext*  mc;
    llama_sampler* sampler;
    int32_t        max_new_tokens;
    int32_t        tokens_generated;
    bool           done;
    char           token_buf[256];
} GenerationState;

// ── Model lifecycle ──────────────────────────────────────────────────────────

extern "C" {

static char g_gpu_info_buffer[256] = "ARM64 NEON CPU";

const char* essential_get_gpu_info() {
    return g_gpu_info_buffer;
}

int64_t essential_init_model(const char* model_path, int32_t backend_type, int32_t threads) {
    LOGI("essential_init_model: path=%s backend=%d threads=%d", model_path, backend_type, threads);
    llama_backend_init();

    llama_model_params mparams = llama_model_default_params();

    if (backend_type == BACKEND_OPENCL_GPU) {
        // 100% Full Layer Offload to OpenCL GPU.
        mparams.n_gpu_layers = 999;
        snprintf(g_gpu_info_buffer, sizeof(g_gpu_info_buffer), "OpenCL GPU Acceleration");
        LOGI("OpenCL GPU Mode: 100%% Layer Offload to GPU (0 SLM load on CPU)");
    } else {
        mparams.n_gpu_layers = 0;
        snprintf(g_gpu_info_buffer, sizeof(g_gpu_info_buffer), "ARM64 NEON CPU");
        LOGI("CPU Mode: Running on ARM64 NEON");
    }

    llama_model* model = llama_model_load_from_file(model_path, mparams);
    if (!model) {
        LOGE("Failed to load model from path: %s", model_path);
        return 0;
    }

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx     = 4096;
    cparams.n_batch   = 4096;
    cparams.n_ubatch  = 512;
    cparams.n_threads = 1; // 1 thread minimum for FFI dispatch; 100% tensor compute on GPU

    llama_context* ctx = llama_init_from_model(model, cparams);
    if (!ctx) {
        LOGE("Failed to create llama context from model");
        llama_model_free(model);
        return 0;
    }

    ModelContext* mc = (ModelContext*)malloc(sizeof(ModelContext));
    mc->model     = model;
    mc->ctx       = ctx;
    mc->n_threads = cparams.n_threads;

    LOGI("Llama model initialized: backend=%s", g_gpu_info_buffer);
    return (int64_t)mc;
}

void essential_free_model(int64_t context_ptr) {
    ModelContext* mc = (ModelContext*)context_ptr;
    if (mc) {
        LOGI("Freeing Llama model context");
        if (mc->ctx)   llama_free(mc->ctx);
        if (mc->model) llama_model_free(mc->model);
        free(mc);
    }
    llama_backend_free();
}

// ── Per-token streaming API with GBNF Grammar Support ────────────────────────

int64_t essential_start_generation(int64_t context_ptr, const char* prompt, const char* grammar_str, int32_t max_new_tokens) {
    ModelContext* mc = (ModelContext*)context_ptr;
    if (!mc || !mc->ctx || !mc->model) {
        LOGE("essential_start_generation: invalid context pointer");
        return 0;
    }

    const llama_vocab* vocab = llama_model_get_vocab(mc->model);
    if (!vocab) {
        LOGE("Failed to retrieve model vocabulary");
        return 0;
    }

    // Tokenize prompt
    std::vector<llama_token> tokens(2048);
    int n_tokens = llama_tokenize(vocab, prompt, (int)strlen(prompt),
                                  tokens.data(), (int)tokens.size(),
                                  /*add_special=*/true, /*parse_special=*/false);
    if (n_tokens < 0) {
        LOGE("Tokenization failed for prompt length %zu", strlen(prompt));
        return 0;
    }
    tokens.resize(n_tokens);
    LOGI("Prompt tokenized into %d tokens", n_tokens);

    // Run prompt evaluation on OpenCL GPU
    llama_batch batch = llama_batch_get_one(tokens.data(), n_tokens);
    if (llama_decode(mc->ctx, batch) != 0) {
        LOGE("llama_decode failed during prompt evaluation");
        return 0;
    }

    // Build sampler chain: GBNF grammar constraint (if provided) -> Penalties -> Top-P -> Low Temp for Code Precision
    llama_sampler* sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());

    if (grammar_str && strlen(grammar_str) > 0) {
        LOGI("Initializing GBNF Grammar constraint sampler...");
        llama_sampler* g_sampler = llama_sampler_init_grammar(vocab, grammar_str, "root");
        if (g_sampler) {
            llama_sampler_chain_add(sampler, g_sampler);
            LOGI("GBNF Grammar sampler successfully attached to chain!");
        } else {
            LOGE("Failed to parse GBNF grammar string!");
        }
    }

    // Software Engineer Sampler Config: repetition penalty = 1.1, top_p = 0.95, low temp = 0.2 (precise code logic)
    int n_vocab = llama_vocab_n_tokens(vocab);
    llama_sampler_chain_add(sampler, llama_sampler_init_penalties(n_vocab, 16, 1.10f, 0.0f, 0.0f));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.20f));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    GenerationState* gs = (GenerationState*)malloc(sizeof(GenerationState));
    gs->mc              = mc;
    gs->sampler         = sampler;
    gs->max_new_tokens  = (max_new_tokens > 0) ? max_new_tokens : 1024;
    gs->tokens_generated = 0;
    gs->done            = false;
    gs->token_buf[0]    = '\0';

    LOGI("Coding Assistant Engineer sampler initialized (temp=0.2, top_p=0.95, penalty=1.1). max_new_tokens=%d", gs->max_new_tokens);
    return (int64_t)gs;
}

const char* essential_next_token(int64_t gen_ptr) {
    GenerationState* gs = (GenerationState*)gen_ptr;
    if (!gs || gs->done) return nullptr;

    const llama_vocab* vocab = llama_model_get_vocab(gs->mc->model);

    // Sample one token (constrained by GBNF grammar if active)
    llama_token token = llama_sampler_sample(gs->sampler, gs->mc->ctx, -1);
    gs->tokens_generated++;

    // Check for end-of-generation token or length limit
    if (llama_vocab_is_eog(vocab, token) || gs->tokens_generated >= gs->max_new_tokens) {
        gs->done = true;
        return nullptr;
    }

    // Decode token ID → piece string
    int len = llama_token_to_piece(vocab, token, gs->token_buf, sizeof(gs->token_buf) - 1, 0, true);
    if (len < 0) len = 0;
    gs->token_buf[len] = '\0';

    // Stop immediately if special chat stop tags appear in decoded string piece
    if (strstr(gs->token_buf, "<|im_end|>") != NULL ||
        strstr(gs->token_buf, "|im_end|>") != NULL ||
        strstr(gs->token_buf, "im_end") != NULL ||
        strstr(gs->token_buf, "<|endoftext|>") != NULL ||
        strstr(gs->token_buf, "<|im_start|>") != NULL) {
        gs->done = true;
        return nullptr;
    }

    // Feed token back for next decode step on OpenCL GPU
    llama_batch next = llama_batch_get_one(&token, 1);
    if (llama_decode(gs->mc->ctx, next) != 0) {
        LOGE("llama_decode step failed at token %d", gs->tokens_generated);
        gs->done = true;
        return nullptr;
    }

    return gs->token_buf;
}

bool essential_is_done(int64_t gen_ptr) {
    GenerationState* gs = (GenerationState*)gen_ptr;
    return (!gs || gs->done);
}

void essential_free_generation(int64_t gen_ptr) {
    GenerationState* gs = (GenerationState*)gen_ptr;
    if (gs) {
        if (gs->sampler) llama_sampler_free(gs->sampler);
        free(gs);
    }
}

} // extern "C"
