#pragma once
#include <string>
#include <functional>
#include <cstdint>
#include <vector>
#include <atomic>
#include <thread>
#include <memory>

namespace kingdom {

struct ChatMessage {
    std::string role;    // "system", "user", "assistant"
    std::string content;
};

struct ChatCompletionRequest {
    std::string model;
    std::vector<ChatMessage> messages;
    bool stream = true;
    int max_tokens = 1024;
    float temperature = 0.75f;
};

struct EmbeddingRequest {
    std::string model;
    std::string input; // text to embed
};

class ServerDaemon {
public:
    explicit ServerDaemon(void* engine_handle, int port = 8080);
    ~ServerDaemon();
    
    bool start(); // starts listening thread, returns immediately
    void stop();
    bool is_running() const;
    int port() const;

private:
    void run_server_loop();
    std::string handle_chat_completion(const std::string& body, std::function<void(const std::string&)> chunk_writer);
    std::string handle_completion(const std::string& body);
    std::string handle_embeddings(const std::string& body);
    std::string handle_models();
    
    std::string parse_json_string(const std::string& json, const std::string& key) const;
    std::vector<ChatMessage> parse_messages(const std::string& json) const;
    
    void* m_engine;
    int m_port;
    std::atomic<bool> m_running{false};
    std::unique_ptr<std::thread> m_thread;
    int m_server_fd = -1;
};

} // namespace kingdom
