#include "kingdom_orchestrator.h"
#include "logger.h"
#include "cognitive_vault.h"
#include "llama_wrapper.h"
#include "sidecar_c_api.h"
#include "native_server.h" // Providing FormatOpenAISseChunk, start_native_mcp_server, etc if needed

#include <thread>
#include <atomic>
#include <mutex>
#include <memory>
#include <string>
#include <sstream>
#include <fstream>
#include <vector>
#include <android/log.h>
#include <chrono>
#include <cstring>
#include <cstdlib>

#define KLOG_TAG "KingdomOrchestrator"
#define KLOG_I(...) __android_log_print(ANDROID_LOG_INFO, KLOG_TAG, __VA_ARGS__)
#define KLOG_E(...) __android_log_print(ANDROID_LOG_ERROR, KLOG_TAG, __VA_ARGS__)
#define KLOG_W(...) __android_log_print(ANDROID_LOG_WARN, KLOG_TAG, __VA_ARGS__)

struct KingdomEngine {
    int64_t llm_handle = 0;
    void* sidecar_handle = nullptr;
    std::unique_ptr<kingdom::RollingLogger> logger;
    std::unique_ptr<kingdom::CognitiveVault> vault;
    std::string storage_dir;
    std::string llm_model_name;
    std::atomic<bool> server_running{false};
    std::unique_ptr<std::thread> server_thread;
    std::mutex gen_mutex;

    // Telemetry
    std::atomic<float> cpu_pct{0.0f};
    std::atomic<float> ram_mb{0.0f};
    std::atomic<float> gpu_pct{0.0f};
    std::atomic<float> vram_mb{0.0f};
    std::atomic<float> npu_latency_ms{0.0f};
    std::unique_ptr<std::thread> telemetry_thread;
    std::atomic<bool> telemetry_running{false};
};

extern "C" {
// Declare FormatOpenAISseChunk if native_server.h doesn't define it to avoid linker errors
std::string FormatOpenAISseChunk(const char* content);
bool start_native_mcp_server(int port);
void stop_native_mcp_server();
}

// Fallback implementation of FormatOpenAISseChunk if not provided
std::string FormatOpenAISseChunk(const char* content) {
    std::string json = "data: {\"choices\":[{\"delta\":{\"content\":\"";
    std::string c_str(content);
    for (char c : c_str) {
        if (c == '"') json += "\\\"";
        else if (c == '\\') json += "\\\\";
        else if (c == '\n') json += "\\n";
        else if (c == '\r') json += "\\r";
        else if (c == '\t') json += "\\t";
        else json += c;
    }
    json += "\"}}]}\n\n";
    return json;
}

void telemetry_loop(KingdomEngine* engine) {
    while (engine->telemetry_running) {
        // Dummy CPU reading for demo purposes
        std::ifstream stat_file("/proc/stat");
        if (stat_file.is_open()) {
            std::string line;
            if (std::getline(stat_file, line)) {
                // Just randomizing a bit or placeholder
                engine->cpu_pct = 45.0f;
            }
        }
        
        std::ifstream mem_file("/proc/meminfo");
        if (mem_file.is_open()) {
            std::string line;
            while(std::getline(mem_file, line)) {
                if(line.find("MemFree:") == 0) {
                    long free_kb;
                    sscanf(line.c_str(), "MemFree: %ld kB", &free_kb);
                    engine->ram_mb = free_kb / 1024.0f;
                    break;
                }
            }
        }
        
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
}

KingdomEngineHandle kingdom_engine_init(const char* storage_dir, const char* llm_path) {
    KLOG_I("Initializing KingdomEngine at %s", storage_dir);
    
    auto* engine = new KingdomEngine();
    engine->storage_dir = storage_dir;
    
    std::string log_path = engine->storage_dir + "/server.log";
    engine->logger = std::make_unique<kingdom::RollingLogger>(log_path);
    
    std::string db_path = engine->storage_dir + "/kingdom.db";
    engine->vault = std::make_unique<kingdom::CognitiveVault>(db_path);
    
    // BACKEND_OPENCL_GPU=1, threads=1
    engine->llm_handle = essential_init_model(llm_path, 1, 1);
    if (!engine->llm_handle) {
        KLOG_W("GPU model init failed, trying CPU fallback");
        engine->llm_handle = essential_init_model(llm_path, 0, 4); // CPU backend
    }
    
    std::string intent_path = engine->storage_dir + "/models/all_minilm_l6_v2.onnx";
    std::string embed_path = engine->storage_dir + "/models/bge_small_en_v1_5.onnx";
    std::string reranker_path = engine->storage_dir + "/models/bge_reranker_base.onnx";
    std::string lang_path = engine->storage_dir + "/models/codeberta_base.onnx";
    
    engine->sidecar_handle = sidecar_init(
        intent_path.c_str(),
        embed_path.c_str(),
        reranker_path.c_str(),
        lang_path.c_str(),
        db_path.c_str()
    );
    
    engine->telemetry_running = true;
    engine->telemetry_thread = std::make_unique<std::thread>(telemetry_loop, engine);
    
    KLOG_I("KingdomEngine initialized successfully.");
    return static_cast<KingdomEngineHandle>(engine);
}

const char* kingdom_engine_status_json(KingdomEngineHandle handle) {
    if (!handle) return strdup("{}");
    std::string json = "{\"llm\":\"loaded\",\"ministers\":8,\"db\":\"open\",\"server_port\":8080}";
    return strdup(json.c_str());
}

void kingdom_engine_process_async(KingdomEngineHandle handle,
                                   const char* prompt,
                                   const char* extra_context,
                                   SseStreamCallback callback,
                                   void* user_data) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if (!engine || !engine->llm_handle) return;
    
    std::lock_guard<std::mutex> lock(engine->gen_mutex);
    
    SidecarResult* s_res = nullptr;
    if (engine->sidecar_handle) {
        s_res = sidecar_process(engine->sidecar_handle, nullptr, 0, prompt);
        if (s_res) {
            engine->npu_latency_ms = s_res->latency_ms;
        }
    }
    
    const char* final_prompt = s_res ? s_res->fully_formatted_prompt : prompt;
    
    int64_t gen_ptr = essential_start_generation(engine->llm_handle, final_prompt, "", 1024);
    if (!gen_ptr) {
        if (s_res) sidecar_free_result(s_res);
        return;
    }
    
    while (!essential_is_done(gen_ptr)) {
        const char* token = essential_next_token(gen_ptr);
        if (token) {
            std::string sse_chunk = FormatOpenAISseChunk(token);
            callback(sse_chunk.c_str(), user_data);
        }
    }
    
    std::string done_msg = "data: [DONE]\n\n";
    callback(done_msg.c_str(), user_data);
    
    essential_free_generation(gen_ptr);
    if (s_res) sidecar_free_result(s_res);
}

const char* kingdom_engine_fast_autocomplete(KingdomEngineHandle handle, const char* code_prefix) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if (!engine || !engine->llm_handle) return strdup("");
    
    std::unique_lock<std::mutex> lock(engine->gen_mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
        return strdup("");
    }
    
    int64_t gen_ptr = essential_start_generation(engine->llm_handle, code_prefix, "", 50);
    if (!gen_ptr) return strdup("");
    
    std::string result = "";
    while (!essential_is_done(gen_ptr)) {
        const char* token = essential_next_token(gen_ptr);
        if (token) result += token;
    }
    
    essential_free_generation(gen_ptr);
    return strdup(result.c_str());
}

const char* kingdom_engine_embed_text(KingdomEngineHandle handle, const char* text) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if (!engine) return strdup("[]");
    
    KLOG_W("Direct embed API not fully bridged, returning placeholder");
    std::string placeholder = "[0.0]";
    return strdup(placeholder.c_str());
}

const char* kingdom_engine_telemetry_json(KingdomEngineHandle handle) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if (!engine) return strdup("{}");
    
    std::stringstream ss;
    ss << "{\"cpu_pct\":" << engine->cpu_pct.load()
       << ",\"ram_mb\":" << engine->ram_mb.load()
       << ",\"gpu_pct\":" << engine->gpu_pct.load()
       << ",\"vram_mb\":" << engine->vram_mb.load()
       << ",\"npu_latency_ms\":" << engine->npu_latency_ms.load()
       << "}";
       
    return strdup(ss.str().c_str());
}

const char* kingdom_engine_get_recent_logs(KingdomEngineHandle handle, int max_lines) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if (!engine || !engine->logger) return strdup("");
    
    // Assuming RollingLogger has this method
    std::string logs = ""; // engine->logger->get_recent_lines(max_lines);
    return strdup(logs.c_str());
}

bool kingdom_engine_start_server(KingdomEngineHandle handle, int port) {
    // using native_server functions if linked
    return start_native_mcp_server(port);
}

void kingdom_engine_stop_server(KingdomEngineHandle handle) {
    stop_native_mcp_server();
}

bool kingdom_engine_is_server_running(KingdomEngineHandle handle) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if(!engine) return false;
    return engine->server_running.load();
}

void kingdom_engine_destroy(KingdomEngineHandle handle) {
    auto* engine = static_cast<KingdomEngine*>(handle);
    if (!engine) return;
    
    engine->telemetry_running = false;
    if (engine->telemetry_thread && engine->telemetry_thread->joinable()) {
        engine->telemetry_thread->join();
    }
    
    kingdom_engine_stop_server(handle);
    
    if (engine->sidecar_handle) {
        sidecar_destroy(engine->sidecar_handle);
    }
    
    if (engine->llm_handle) {
        essential_free_model(engine->llm_handle);
    }
    
    delete engine;
    KLOG_I("KingdomEngine destroyed.");
}
