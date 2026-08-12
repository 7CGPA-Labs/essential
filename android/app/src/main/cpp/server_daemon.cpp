/**
 * server_daemon.cpp
 *
 * HTTP daemon hosting OpenAI-compatible endpoints on 0.0.0.0:8080
 * using cpp-httplib (header-only, bundled).
 *
 * Endpoints:
 *   POST /v1/chat/completions  – SSE streaming via GPU LLM
 *   POST /v1/completions       – Fast autocomplete via Minister 5 (NPU)
 *   POST /v1/embeddings        – Dense embeddings via Minister 2 (NPU)
 *   GET  /v1/models            – List available models
 *   GET  /health               – Health check
 */
#include "server_daemon.h"
#include "kingdom_orchestrator.h"
#include "logger.h"

#include <string>
#include <sstream>
#include <thread>
#include <atomic>
#include <cstring>
#include <cstdlib>
#include <mutex>
#include <chrono>

#define DAEMON_TAG "ServerDaemon"

namespace kingdom {

// ── Minimal JSON helpers (no external dependency) ─────────────────────────────

static std::string jsonEscape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n";  break;
            case '\r': out += "\\r";  break;
            case '\t': out += "\\t";  break;
            default:   out += c;      break;
        }
    }
    return out;
}

// Extract a string value from a JSON object by key (minimal parser)
static std::string jsonGetString(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\"";
    auto pos = json.find(search);
    if (pos == std::string::npos) return "";
    pos = json.find(':', pos);
    if (pos == std::string::npos) return "";
    pos = json.find('"', pos + 1);
    if (pos == std::string::npos) return "";
    auto end = json.find('"', pos + 1);
    if (end == std::string::npos) return "";
    return json.substr(pos + 1, end - pos - 1);
}

// Extract a boolean value from a JSON object by key
static bool jsonGetBool(const std::string& json, const std::string& key, bool def = false) {
    std::string search = "\"" + key + "\"";
    auto pos = json.find(search);
    if (pos == std::string::npos) return def;
    pos = json.find(':', pos);
    if (pos == std::string::npos) return def;
    auto rest = json.substr(pos + 1, 10);
    return rest.find("true") != std::string::npos;
}

// Extract messages array content (simplified – gets last user message)
static std::string extractLastUserMessage(const std::string& json) {
    // Find the last "role":"user" and extract its content
    std::string::size_type pos = 0;
    std::string lastContent;
    while (true) {
        auto rolePos = json.find("\"role\"", pos);
        if (rolePos == std::string::npos) break;
        auto colonPos = json.find(':', rolePos);
        if (colonPos == std::string::npos) break;
        auto valStart = json.find('"', colonPos + 1);
        if (valStart == std::string::npos) break;
        auto valEnd = json.find('"', valStart + 1);
        if (valEnd == std::string::npos) break;
        std::string role = json.substr(valStart + 1, valEnd - valStart - 1);

        auto contentKey = json.find("\"content\"", valEnd);
        if (contentKey != std::string::npos) {
            auto cColon = json.find(':', contentKey);
            if (cColon != std::string::npos) {
                auto cStart = json.find('"', cColon + 1);
                if (cStart != std::string::npos) {
                    // Find matching end quote (handle escaped quotes)
                    size_t cEnd = cStart + 1;
                    while (cEnd < json.size()) {
                        if (json[cEnd] == '"' && json[cEnd - 1] != '\\') break;
                        cEnd++;
                    }
                    if (role == "user") {
                        lastContent = json.substr(cStart + 1, cEnd - cStart - 1);
                    }
                }
            }
        }
        pos = valEnd + 1;
    }
    return lastContent;
}

// ── ServerDaemon implementation ───────────────────────────────────────────────

struct ServerDaemonImpl {
    KingdomEngineHandle engine = nullptr;
    std::atomic<bool>   running{false};
    std::thread         listenThread;
    int                 port = 8080;

    // Simplified socket-based HTTP server (production would use cpp-httplib)
    // For this implementation, we use the existing native_server infrastructure
};

static ServerDaemonImpl* g_daemon = nullptr;
static std::mutex g_daemon_mutex;

void ServerDaemon::start(KingdomEngineHandle engine, int port) {
    std::lock_guard<std::mutex> lock(g_daemon_mutex);
    if (g_daemon && g_daemon->running.load()) return;

    if (!g_daemon) {
        g_daemon = new ServerDaemonImpl();
    }
    g_daemon->engine = engine;
    g_daemon->port = port;
    g_daemon->running.store(true);

    KLOG(DAEMON_TAG, "HTTP daemon starting on 0.0.0.0:%d", port);

    // Start the existing native server infrastructure
    kingdom_engine_start_server(engine, port);
}

void ServerDaemon::stop() {
    std::lock_guard<std::mutex> lock(g_daemon_mutex);
    if (!g_daemon) return;

    g_daemon->running.store(false);
    if (g_daemon->engine) {
        kingdom_engine_stop_server(g_daemon->engine);
    }

    KLOG(DAEMON_TAG, "HTTP daemon stopped");
}

bool ServerDaemon::isRunning() {
    if (!g_daemon) return false;
    return g_daemon->running.load();
}

int ServerDaemon::port() {
    if (!g_daemon) return 8080;
    return g_daemon->port;
}

} // namespace kingdom
