#include "native_server.h"
#include "llama_wrapper.h"
#include "sidecar_c_api.h"
#include <iostream>
#include <sstream>
#include <chrono>
#include <thread>
#include <atomic>
#include <vector>
#include <memory>

// Helper to escape string characters for valid JSON
std::string FormatOpenAISseChunk(const std::string& token_piece, const std::string& model_name) {
    auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();

    std::string escaped_piece = "";
    for (char c : token_piece) {
        if (c == '"') escaped_piece += "\\\"";
        else if (c == '\\') escaped_piece += "\\\\";
        else if (c == '\n') escaped_piece += "\\n";
        else if (c == '\r') escaped_piece += "\\r";
        else if (c == '\t') escaped_piece += "\\t";
        else escaped_piece += c;
    }

    std::ostringstream ss;
    ss << "data: {"
       << "\"id\":\"chatcmpl-ondevice\","
       << "\"object\":\"chat.completion.chunk\","
       << "\"created\":" << now << ","
       << "\"model\":\"" << model_name << "\","
       << "\"choices\":[{"
       << "\"index\":0,"
       << "\"delta\":{\"content\":\"" << escaped_piece << "\"},"
       << "\"finish_reason\":null"
       << "}]}\n\n";

    return ss.str();
}

namespace {
    std::atomic<bool> g_server_running{false};
    std::unique_ptr<std::thread> g_server_thread = nullptr;
}

extern "C" {

void start_native_mcp_server(const char* gguf_path, const char* onnx_path, int port) {
    if (g_server_running.load()) return;

    g_server_running.store(true);
    std::string gguf = gguf_path ? gguf_path : "";
    std::string onnx = onnx_path ? onnx_path : "";

    g_server_thread = std::make_unique<std::thread>([gguf, onnx, port]() {
        // Native background thread running C++ server loop
        while (g_server_running.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
    });
}

void stop_native_mcp_server() {
    g_server_running.store(false);
    if (g_server_thread && g_server_thread->joinable()) {
        g_server_thread->join();
    }
    g_server_thread = nullptr;
}

}
