#include "sidecar_c_api.h"
#include "sidecar_engine.h"
#include <cstdlib>
#include <cstring>

using namespace essential;

extern "C" {

void* sidecar_init(const char* lang_path, const char* embed_path, const char* db_path) {
    std::string lang = lang_path ? lang_path : "";
    std::string embed = embed_path ? embed_path : "";
    std::string db = db_path ? db_path : "";

    auto* coordinator = new SidecarPipelineCoordinator(lang, embed, db);
    return static_cast<void*>(coordinator);
}

SidecarResult* sidecar_process(void* handle, const uint8_t* img_bytes, int32_t img_len, const char* user_query) {
    if (!handle) return nullptr;
    auto* coordinator = static_cast<SidecarPipelineCoordinator*>(handle);
    std::string query = user_query ? user_query : "";

    return coordinator->Process(img_bytes, img_len, query);
}

void sidecar_free_result(SidecarResult* result) {
    if (!result) return;
    if (result->extracted_code) free(const_cast<char*>(result->extracted_code));
    if (result->detected_language) free(const_cast<char*>(result->detected_language));
    if (result->retrieved_context) free(const_cast<char*>(result->retrieved_context));
    if (result->fully_formatted_prompt) free(const_cast<char*>(result->fully_formatted_prompt));
    delete result;
}

void sidecar_destroy(void* handle) {
    if (!handle) return;
    auto* coordinator = static_cast<SidecarPipelineCoordinator*>(handle);
    delete coordinator;
}

}
