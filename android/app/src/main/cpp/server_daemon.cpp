#include "server_daemon.h"
#include "kingdom_orchestrator.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <cstring>
#include <sstream>
#include <android/log.h>
#include <poll.h>

#define SLOG_TAG "ServerDaemon"
#define SLOG_I(...) __android_log_print(ANDROID_LOG_INFO, SLOG_TAG, __VA_ARGS__)
#define SLOG_E(...) __android_log_print(ANDROID_LOG_ERROR, SLOG_TAG, __VA_ARGS__)

namespace kingdom {

ServerDaemon::ServerDaemon(void* engine_handle, int port)
    : m_engine(engine_handle), m_port(port) {}

ServerDaemon::~ServerDaemon() {
    stop();
}

bool ServerDaemon::start() {
    if (m_running) return true;

    m_server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (m_server_fd < 0) {
        SLOG_E("Failed to create socket");
        return false;
    }

    int opt = 1;
    setsockopt(m_server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(m_port);

    if (bind(m_server_fd, (struct sockaddr*)&address, sizeof(address)) < 0) {
        SLOG_E("Failed to bind to port %d", m_port);
        close(m_server_fd);
        m_server_fd = -1;
        return false;
    }

    if (listen(m_server_fd, 10) < 0) {
        SLOG_E("Failed to listen");
        close(m_server_fd);
        m_server_fd = -1;
        return false;
    }

    // Set non-blocking
    int flags = fcntl(m_server_fd, F_GETFL, 0);
    fcntl(m_server_fd, F_SETFL, flags | O_NONBLOCK);

    m_running = true;
    m_thread = std::make_unique<std::thread>(&ServerDaemon::run_server_loop, this);
    SLOG_I("Server started on port %d", m_port);
    return true;
}

void ServerDaemon::stop() {
    m_running = false;
    if (m_thread && m_thread->joinable()) {
        m_thread->join();
    }
    if (m_server_fd >= 0) {
        close(m_server_fd);
        m_server_fd = -1;
    }
    SLOG_I("Server stopped");
}

bool ServerDaemon::is_running() const {
    return m_running.load();
}

int ServerDaemon::port() const {
    return m_port;
}

void ServerDaemon::run_server_loop() {
    while (m_running) {
        struct pollfd pfd;
        pfd.fd = m_server_fd;
        pfd.events = POLLIN;
        
        int ret = poll(&pfd, 1, 100); // 100ms timeout
        if (ret > 0 && (pfd.revents & POLLIN)) {
            struct sockaddr_in client_addr;
            socklen_t addrlen = sizeof(client_addr);
            int client_fd = accept(m_server_fd, (struct sockaddr*)&client_addr, &addrlen);
            
            if (client_fd >= 0) {
                std::thread([this, client_fd]() {
                    char buffer[4096];
                    memset(buffer, 0, sizeof(buffer));
                    int bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
                    
                    if (bytes_read > 0) {
                        std::string req(buffer);
                        size_t body_start = req.find("\r\n\r\n");
                        std::string body = "";
                        if (body_start != std::string::npos) {
                            body = req.substr(body_start + 4);
                        }

                        std::string response;
                        
                        if (req.find("POST /v1/chat/completions") == 0) {
                            std::string headers = 
                                "HTTP/1.1 200 OK\r\n"
                                "Content-Type: text/event-stream\r\n"
                                "Cache-Control: no-cache\r\n"
                                "Connection: keep-alive\r\n"
                                "Access-Control-Allow-Origin: *\r\n\r\n";
                            write(client_fd, headers.c_str(), headers.length());
                            
                            handle_chat_completion(body, [client_fd](const std::string& chunk) {
                                write(client_fd, chunk.c_str(), chunk.length());
                            });
                            
                            close(client_fd);
                            return;
                        } else if (req.find("POST /v1/completions") == 0) {
                            std::string res_body = handle_completion(body);
                            response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(res_body.length()) + "\r\n\r\n" + res_body;
                        } else if (req.find("POST /v1/embeddings") == 0) {
                            std::string res_body = handle_embeddings(body);
                            response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(res_body.length()) + "\r\n\r\n" + res_body;
                        } else if (req.find("GET /v1/models") == 0) {
                            std::string res_body = handle_models();
                            response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(res_body.length()) + "\r\n\r\n" + res_body;
                        } else if (req.find("GET /health") == 0) {
                            std::string res_body = "{\"status\":\"ok\"}";
                            response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(res_body.length()) + "\r\n\r\n" + res_body;
                        } else {
                            response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n";
                        }
                        
                        write(client_fd, response.c_str(), response.length());
                    }
                    close(client_fd);
                }).detach();
            }
        }
    }
}

std::string ServerDaemon::handle_chat_completion(const std::string& body, std::function<void(const std::string&)> chunk_writer) {
    // Basic extraction
    auto msgs = parse_messages(body);
    std::string prompt = "";
    for(const auto& m : msgs) {
        prompt += "<|im_start|>" + m.role + "\n" + m.content + "<|im_end|>\n";
    }
    prompt += "<|im_start|>assistant\n";

    // Create lambda that matches SseStreamCallback signature
    struct CallbackCtx {
        std::function<void(const std::string&)> writer;
    };
    CallbackCtx ctx{chunk_writer};
    
    auto c_cb = [](const char* chunk, void* user_data) {
        auto* cctx = static_cast<CallbackCtx*>(user_data);
        cctx->writer(std::string(chunk));
    };

    kingdom_engine_process_async(m_engine, prompt.c_str(), "", c_cb, &ctx);
    return ""; // Streamed directly
}

std::string ServerDaemon::handle_completion(const std::string& body) {
    std::string prompt = parse_json_string(body, "prompt");
    const char* c_res = kingdom_engine_fast_autocomplete(m_engine, prompt.c_str());
    std::string res_text = c_res ? std::string(c_res) : "";
    if (c_res) free((void*)c_res);

    std::string escaped = res_text;
    // basic escape quotes and newlines
    size_t pos = 0;
    while((pos = escaped.find("\"", pos)) != std::string::npos) { escaped.replace(pos, 1, "\\\""); pos += 2; }
    pos = 0;
    while((pos = escaped.find("\n", pos)) != std::string::npos) { escaped.replace(pos, 1, "\\n"); pos += 2; }

    return "{\"id\":\"cmpl-ondevice\",\"object\":\"text_completion\",\"choices\":[{\"text\":\"" + escaped + "\",\"finish_reason\":\"stop\"}]}";
}

std::string ServerDaemon::handle_embeddings(const std::string& body) {
    std::string input = parse_json_string(body, "input");
    const char* c_res = kingdom_engine_embed_text(m_engine, input.c_str());
    std::string arr = c_res ? std::string(c_res) : "[]";
    if (c_res) free((void*)c_res);

    return "{\"object\":\"list\",\"data\":[{\"object\":\"embedding\",\"index\":0,\"embedding\":" + arr + "}],\"model\":\"bge-small-en-v1.5\"}";
}

std::string ServerDaemon::handle_models() {
    return "{\"object\":\"list\",\"data\":[{\"id\":\"qwen2.5-coder-1.5b\",\"object\":\"model\"},{\"id\":\"bge-small-en-v1.5\",\"object\":\"model\"},{\"id\":\"granite-code-128m\",\"object\":\"model\"}]}";
}

std::string ServerDaemon::parse_json_string(const std::string& json, const std::string& key) const {
    std::string search = "\"" + key + "\":\"";
    size_t start = json.find(search);
    if (start == std::string::npos) {
        search = "\"" + key + "\": \"";
        start = json.find(search);
    }
    if (start != std::string::npos) {
        start += search.length();
        size_t end = json.find("\"", start);
        if (end != std::string::npos) {
            return json.substr(start, end - start);
        }
    }
    return "";
}

std::vector<ChatMessage> ServerDaemon::parse_messages(const std::string& json) const {
    std::vector<ChatMessage> msgs;
    // VERY naive parsing for demo
    size_t pos = 0;
    while ((pos = json.find("\"role\"", pos)) != std::string::npos) {
        size_t role_start = json.find("\"", pos + 6);
        if (role_start == std::string::npos) break;
        while(json[role_start] == ' ' || json[role_start] == ':') role_start++;
        if (json[role_start] == '"') role_start++;
        size_t role_end = json.find("\"", role_start);
        std::string role = json.substr(role_start, role_end - role_start);

        size_t content_key = json.find("\"content\"", role_end);
        if (content_key == std::string::npos) break;
        size_t content_start = json.find("\"", content_key + 9);
        while(json[content_start] == ' ' || json[content_start] == ':') content_start++;
        if (json[content_start] == '"') content_start++;
        size_t content_end = json.find("\"", content_start);
        std::string content = json.substr(content_start, content_end - content_start);

        msgs.push_back({role, content});
        pos = content_end;
    }
    if(msgs.empty()) {
        msgs.push_back({"user", "Hello"});
    }
    return msgs;
}

} // namespace kingdom
