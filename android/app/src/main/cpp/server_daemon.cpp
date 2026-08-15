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
#include <vector>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>

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
    int                 port = 8080;
    int                 server_fd = -1;
    std::unique_ptr<std::thread> thread;

    void handle_client(int client_fd) {
        char buffer[4096];
        memset(buffer, 0, sizeof(buffer));
        int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
        if (bytes_read <= 0) {
            close(client_fd);
            return;
        }

        std::string req(buffer);
        size_t body_start = req.find("\r\n\r\n");
        std::string body = (body_start != std::string::npos) ? req.substr(body_start + 4) : "";

        if (req.find("POST /v1/chat/completions") == 0) {
            std::string headers =
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: text/event-stream\r\n"
                "Cache-Control: no-cache\r\n"
                "Connection: keep-alive\r\n"
                "Access-Control-Allow-Origin: *\r\n\r\n";
            write(client_fd, headers.c_str(), headers.length());

            std::string prompt = extractLastUserMessage(body);
            if (prompt.empty()) prompt = "Hello";
            std::string formatted_prompt = "<|im_start|>user\n" + prompt + "<|im_end|>\n<|im_start|>assistant\n";

            struct CallbackCtx { int fd; };
            CallbackCtx ctx{client_fd};

            auto cb = [](const char* chunk, void* data) {
                auto* c = static_cast<CallbackCtx*>(data);
                if (c && c->fd >= 0 && chunk) {
                    write(c->fd, chunk, strlen(chunk));
                }
            };

            if (engine) {
                kingdom_engine_process_async(engine, formatted_prompt.c_str(), nullptr, cb, &ctx);
            }
            close(client_fd);
            return;
        } else if (req.find("POST /v1/completions") == 0) {
            std::string prompt = jsonGetString(body, "prompt");
            const char* res = engine ? kingdom_engine_fast_autocomplete(engine, prompt.c_str()) : nullptr;
            std::string res_json = res ? std::string(res) : "{\"choices\":[{\"text\":\"\"}]}";
            if (res) free((void*)res);

            std::string resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: " +
                               std::to_string(res_json.length()) + "\r\n\r\n" + res_json;
            write(client_fd, resp.c_str(), resp.length());
        } else if (req.find("POST /v1/embeddings") == 0) {
            std::string input = jsonGetString(body, "input");
            const char* res = engine ? kingdom_engine_embed_text(engine, input.c_str()) : nullptr;
            std::string res_json = res ? std::string(res) : "{\"data\":[]}";
            if (res) free((void*)res);

            std::string resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: " +
                               std::to_string(res_json.length()) + "\r\n\r\n" + res_json;
            write(client_fd, resp.c_str(), resp.length());
        } else if (req.find("GET /v1/models") == 0) {
            std::string res_json = "{\"object\":\"list\",\"data\":[{\"id\":\"qwen2.5-coder-1.5b\",\"object\":\"model\"},{\"id\":\"bge-small-en-v1.5\",\"object\":\"model\"},{\"id\":\"granite-code-128m\",\"object\":\"model\"}]}";
            std::string resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: " +
                               std::to_string(res_json.length()) + "\r\n\r\n" + res_json;
            write(client_fd, resp.c_str(), resp.length());
        } else if (req.find("GET /health") == 0) {
            std::string res_json = "{\"status\":\"ok\",\"engine\":\"kingdom-native\"}";
            std::string resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: " +
                               std::to_string(res_json.length()) + "\r\n\r\n" + res_json;
            write(client_fd, resp.c_str(), resp.length());
        } else if (req.find("OPTIONS ") == 0) {
            std::string resp = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Authorization\r\n\r\n";
            write(client_fd, resp.c_str(), resp.length());
        } else {
            std::string resp = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
            write(client_fd, resp.c_str(), resp.length());
        }
        close(client_fd);
    }

    void run_loop() {
        server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) return;

        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in addr{};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = INADDR_ANY;
        addr.sin_port = htons(port);

        if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            close(server_fd);
            server_fd = -1;
            return;
        }

        if (listen(server_fd, 16) < 0) {
            close(server_fd);
            server_fd = -1;
            return;
        }

        int flags = fcntl(server_fd, F_GETFL, 0);
        fcntl(server_fd, F_SETFL, flags | O_NONBLOCK);

        while (running.load()) {
            struct pollfd pfd{};
            pfd.fd = server_fd;
            pfd.events = POLLIN;

            int ret = poll(&pfd, 1, 100);
            if (ret > 0 && (pfd.revents & POLLIN)) {
                struct sockaddr_in client_addr{};
                socklen_t client_len = sizeof(client_addr);
                int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
                if (client_fd >= 0) {
                    std::thread([this, client_fd]() {
                        handle_client(client_fd);
                    }).detach();
                }
            }
        }

        if (server_fd >= 0) {
            close(server_fd);
            server_fd = -1;
        }
    }
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
    g_daemon->thread = std::make_unique<std::thread>(&ServerDaemonImpl::run_loop, g_daemon);

    KLOG(DAEMON_TAG, "HTTP daemon started on 0.0.0.0:%d", port);
}

void ServerDaemon::stop() {
    std::lock_guard<std::mutex> lock(g_daemon_mutex);
    if (!g_daemon) return;

    g_daemon->running.store(false);
    if (g_daemon->thread && g_daemon->thread->joinable()) {
        g_daemon->thread->join();
    }
    g_daemon->thread = nullptr;

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
