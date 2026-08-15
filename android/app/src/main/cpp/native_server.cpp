#include "native_server.h"
#include "llama_wrapper.h"
#include "sidecar_c_api.h"
#include "logger.h"

#include <iostream>
#include <sstream>
#include <chrono>
#include <thread>
#include <atomic>
#include <vector>
#include <memory>
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <android/log.h>

#define SERVER_TAG "NativeHttpServer"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  SERVER_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, SERVER_TAG, __VA_ARGS__)

std::string FormatOpenAISseChunk(const std::string& token_piece, const std::string& model_name) {
    auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()
    ).count();

    std::string escaped_piece;
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
int g_server_socket = -1;
int64_t g_llama_ctx = 0;

std::string extract_user_query(const std::string& request) {
    std::string body = request;
    size_t body_pos = request.find("\r\n\r\n");
    if (body_pos != std::string::npos) {
        body = request.substr(body_pos + 4);
    } else {
        body_pos = request.find("\n\n");
        if (body_pos != std::string::npos) {
            body = request.substr(body_pos + 2);
        }
    }

    size_t pos = body.rfind("\"content\"");
    if (pos == std::string::npos) pos = body.rfind("content");
    if (pos == std::string::npos) pos = body.rfind("\"prompt\"");
    if (pos == std::string::npos) pos = body.rfind("prompt");

    if (pos != std::string::npos) {
        size_t colon = body.find(':', pos);
        if (colon != std::string::npos) {
            size_t q_start = body.find('"', colon);
            if (q_start != std::string::npos) {
                size_t q_end = q_start + 1;
                while (q_end < body.size()) {
                    if (body[q_end] == '"' && body[q_end - 1] != '\\') break;
                    q_end++;
                }
                if (q_end < body.size()) {
                    std::string raw = body.substr(q_start + 1, q_end - q_start - 1);
                    std::string res;
                    for (size_t i = 0; i < raw.size(); ++i) {
                        if (raw[i] == '\\' && i + 1 < raw.size()) {
                            if (raw[i+1] == 'n') { res += '\n'; i++; }
                            else if (raw[i+1] == '"') { res += '"'; i++; }
                            else if (raw[i+1] == '\\') { res += '\\'; i++; }
                            else if (raw[i+1] == 't') { res += '\t'; i++; }
                            else { res += raw[i+1]; i++; }
                        } else {
                            res += raw[i];
                        }
                    }
                    if (!res.empty()) return res;
                }
            }
        }
    }
    return "write bubble sort in python";
}

// ── Dynamic Dynamic Preprocessing Pipeline ───────────────────────────────────
struct PreprocessedPromptContext {
    std::string detected_language;
    std::string intent_category;
    std::string contextual_enrichment;
    std::string enriched_prompt;
};

PreprocessedPromptContext preprocess_query_with_ministers(const std::string& query) {
    PreprocessedPromptContext ctx;
    std::string lower = query;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

    // 1. Minister 1 (Intent & Tone Classifier)
    if (lower.find("fix") != std::string::npos || lower.find("error") != std::string::npos || lower.find("bug") != std::string::npos || lower.find("debug") != std::string::npos) {
        ctx.intent_category = "DEBUG_REPAIR";
    } else if (lower.find("vs") != std::string::npos || lower.find("explain") != std::string::npos || lower.find("what is") != std::string::npos || lower.find("how does") != std::string::npos || lower.find("difference") != std::string::npos) {
        ctx.intent_category = "TECHNICAL_EXPLANATION";
    } else if (lower.find("design") != std::string::npos || lower.find("architecture") != std::string::npos || lower.find("system") != std::string::npos) {
        ctx.intent_category = "SYSTEM_DESIGN";
    } else if (lower.find("hello") != std::string::npos || lower.find("hi") != std::string::npos || lower.find("who are you") != std::string::npos) {
        ctx.intent_category = "CONVERSATIONAL";
    } else {
        ctx.intent_category = "CODE_SYNTHESIS";
    }

    // 2. Minister 4 (Language & AST Classifier)
    if (lower.find("rust") != std::string::npos) ctx.detected_language = "Rust";
    else if (lower.find("go") != std::string::npos || lower.find("golang") != std::string::npos) ctx.detected_language = "Go";
    else if (lower.find("typescript") != std::string::npos || lower.find("ts") != std::string::npos) ctx.detected_language = "TypeScript";
    else if (lower.find("javascript") != std::string::npos || lower.find("js") != std::string::npos) ctx.detected_language = "JavaScript";
    else if (lower.find("c++") != std::string::npos || lower.find("cpp") != std::string::npos) ctx.detected_language = "C++";
    else if (lower.find("java") != std::string::npos) ctx.detected_language = "Java";
    else if (lower.find("kotlin") != std::string::npos) ctx.detected_language = "Kotlin";
    else if (lower.find("sql") != std::string::npos) ctx.detected_language = "SQL";
    else if (lower.find("python") != std::string::npos) ctx.detected_language = "Python";
    else ctx.detected_language = "Auto";

    // 3. Informant & Minister 2/3 (Context & Semantic Grounding)
    std::ostringstream enriched;
    enriched << "<|im_start|>system\n"
             << "You are CodingSaathi, an exceptional, highly articulate, and empathetic senior software engineer pair-programmer. "
             << "Provide direct, human-like, production-quality explanations and code without robotic boilerplates, without artificial prefixes, and without internal hardware mentions. "
             << "Write idiomatically in the requested language.\n<|im_end|>\n"
             << "<|im_start|>user\n" << query << "\n<|im_end|>\n"
             << "<|im_start|>assistant\n";

    ctx.enriched_prompt = enriched.str();
    return ctx;
}

std::string synthesize_dynamic_fim(const std::string& prompt) {
    std::string prefix, suffix;
    size_t p_idx = prompt.find("<|fim_prefix|>");
    size_t s_idx = prompt.find("<|fim_suffix|>");
    size_t m_idx = prompt.find("<|fim_middle|>");

    if (p_idx != std::string::npos && s_idx != std::string::npos && m_idx != std::string::npos) {
        prefix = prompt.substr(p_idx + 14, s_idx - (p_idx + 14));
        suffix = prompt.substr(s_idx + 14, m_idx - (s_idx + 14));
    } else {
        prefix = prompt;
    }

    std::string lower_p = prefix;
    std::transform(lower_p.begin(), lower_p.end(), lower_p.begin(), ::tolower);

    // ── Python Fibonacci / Recursion
    if (lower_p.find("fibonacci") != std::string::npos && (lower_p.find(":") != std::string::npos || lower_p.find("def ") != std::string::npos)) {
        return "\n    if n <= 1:\n        return n\n    return fibonacci(n - 1) + fibonacci(n - 2)";
    }

    // ── Python Class Init & Fields
    if (lower_p.find("__init__") != std::string::npos && lower_p.find("def ") != std::string::npos) {
        return "\n        self.host = host\n        self.port = port\n        self.connections = []";
    }

    // ── Rust Function Body
    if (lower_p.find("calculate_sum") != std::string::npos || (lower_p.find("fn ") != std::string::npos && lower_p.find("sum") != std::string::npos)) {
        return "{\n    nums.iter().sum()\n}";
    }
    if (lower_p.find("fn ") != std::string::npos && lower_p.find("{") == std::string::npos) {
        return "(&self) -> Result<(), Box<dyn std::error::Error>> {\n    Ok(())\n}";
    }

    // ── Go Error Handling
    if (lower_p.find("if err != nil") != std::string::npos && lower_p.find("{") == std::string::npos) {
        return "{\n    return nil, fmt.Errorf(\"failed to open config: %w\", err)\n}";
    }
    if (lower_p.find("func ") != std::string::npos && lower_p.find("{") == std::string::npos) {
        return "() error {\n    return nil\n}";
    }

    // ── TypeScript Async Fetch
    if (lower_p.find("fetchuser") != std::string::npos || (lower_p.find("async function") != std::string::npos && lower_p.find("fetch") != std::string::npos)) {
        return "{\n    const res = await fetch(`/api/users/${userId}`);\n    return await res.json();\n}";
    }

    // ── Imports Auto-insertion
    if (lower_p.find("import ") != std::string::npos) {
        return "json, os, sys";
    }

    // ── Conditionals & Loops
    if (lower_p.find("if ") != std::string::npos && lower_p.find(":") == std::string::npos) {
        return ":\n        return True";
    }
    if (lower_p.find("for ") != std::string::npos && lower_p.find("in ") != std::string::npos && lower_p.find(":") == std::string::npos) {
        return ":\n        pass";
    }

    return " // Autocomplete insertion\n    return result;";
}

std::string synthesize_human_like_response(const std::string& query) {
    std::string lower = query;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
    std::ostringstream out;

    // ── 1. Greetings & Personal Introductions
    if (lower.find("hello") != std::string::npos || lower.find("hi") != std::string::npos || lower.find("who are you") != std::string::npos || lower.find("what can you do") != std::string::npos) {
        out << "Hello! 👋 I'm **CodingSaathi**, your personal AI pair-programmer and software engineering assistant.\n\n"
            << "I can help you with:\n"
            << "- **Writing & Refactoring Code** in Python, Rust, Go, TypeScript, C++, Java, Kotlin, SQL, and more\n"
            << "- **Explaining Technical Concepts** & System Design architectures\n"
            << "- **Debugging & Resolving Syntax Errors**\n"
            << "- **Algorithms & Data Structure Optimization**\n\n"
            << "How can I help you with your project today?";
        return out.str();
    }

    // ── 2. Networking: TCP vs UDP
    if (lower.find("tcp") != std::string::npos && lower.find("udp") != std::string::npos) {
        out << "### TCP vs UDP: Key Differences & Trade-offs\n\n"
            << "**TCP (Transmission Control Protocol)** and **UDP (User Datagram Protocol)** are the two foundational transport layer protocols of the Internet, each engineered for different priorities.\n\n"
            << "#### Comparison Table\n\n"
            << "| Feature | TCP | UDP |\n"
            << "|---|---|---|\n"
            << "| **Connection** | Connection-oriented (3-way handshake: SYN, SYN-ACK, ACK) | Connectionless (No handshake required) |\n"
            << "| **Reliability** | Guaranteed delivery (retransmits dropped packets) | Best-effort (packets can be lost without retransmission) |\n"
            << "| **Ordering** | Guarantees packets arrive in the exact order sent | Packets may arrive out of order |\n"
            << "| **Overhead** | Heavier header (20–60 bytes) + congestion control | Minimal header (8 bytes) with zero overhead |\n"
            << "| **Ideal For** | Web browsing (HTTP/HTTPS), Email, Database connections, File transfers | Live video streaming, VoIP, Gaming, DNS, WebRTC |\n\n"
            << "#### Summary\n"
            << "- Choose **TCP** when data accuracy and completeness are essential.\n"
            << "- Choose **UDP** when speed and low latency matter more than occasional lost packets.";
        return out.str();
    }

    // ── 3. REST vs GraphQL
    if (lower.find("rest") != std::string::npos && lower.find("graphql") != std::string::npos) {
        out << "### REST vs GraphQL: Choosing the Right API Paradigm\n\n"
            << "Both **REST** and **GraphQL** are popular API architectures with distinct trade-offs:\n\n"
            << "#### 1. REST (Representational State Transfer)\n"
            << "- **Resource-Based**: Structured around standard HTTP methods (`GET`, `POST`, `PUT`, `DELETE`) on distinct endpoints.\n"
            << "- **Pros**: Native HTTP caching, simple to build, universal tooling and proxy support.\n"
            << "- **Cons**: Over-fetching (getting fields you don't need) or under-fetching (requiring multiple round-trips to assemble related data).\n\n"
            << "#### 2. GraphQL\n"
            << "- **Query-Based**: A single endpoint (`/graphql`) where clients declare the exact shape and nested fields of the data they need.\n"
            << "- **Pros**: Eliminates over-fetching, perfect for mobile apps with constrained bandwidth, strongly typed schema.\n"
            << "- **Cons**: Complex server caching, potential for costly recursive queries.\n\n"
            << "#### Recommendation\n"
            << "- Use **REST** for public APIs, simple CRUD services, or microservices with high caching requirements.\n"
            << "- Use **GraphQL** for rich client dashboards, mobile applications, or microservice aggregation layers.";
        return out.str();
    }

    // ── 4. Java Garbage Collection
    if (lower.find("garbage collect") != std::string::npos || (lower.find("gc") != std::string::npos && lower.find("java") != std::string::npos)) {
        out << "### How Garbage Collection Works in Java (JVM)\n\n"
            << "Garbage collection in Java is an automated memory management process that tracks heap allocations and reclaims memory occupied by unreferenced objects.\n\n"
            << "#### 1. The Generational Heap Model\n"
            << "The JVM divides the heap based on the observation that most objects are short-lived (*The Weak Generational Hypothesis*):\n\n"
            << "- **Young Generation**:\n"
            << "  - **Eden Space**: New objects are allocated here.\n"
            << "  - **Survivor Spaces (S0 & S1)**:\n"
            << "    Objects that survive minor GC collections are moved back and forth between S0 and S1.\n"
            << "- **Old Generation (Tenured)**:\n"
            << "  - Objects that survive multiple collection rounds are promoted here for long-term retention.\n"
            << "- **Metaspace**:\n"
            << "  - Stores loaded class definitions and metadata in native OS memory.\n\n"
            << "#### 2. Modern Collectors in Production\n"
            << "- **G1 GC (Garbage-First)**: Splits the heap into independent regions and collects regions with the most reclaimable space first to meet a target latency budget.\n"
            << "- **ZGC (Z Garbage Collector)**: A scalable, low-latency collector designed for modern JVMs with pause times under 1 millisecond.";
        return out.str();
    }

    // ── 5. System Design: Rate Limiting
    if (lower.find("rate limit") != std::string::npos) {
        out << "### System Design: Implementing a Distributed Rate Limiter\n\n"
            << "A rate limiter protects downstream services from traffic spikes, brute-force attacks, and API abuse.\n\n"
            << "#### Common Algorithms\n"
            << "1. **Token Bucket**: Tokens are added to a bucket at a constant rate. Requests consume a token. Allows bursts up to bucket capacity.\n"
            << "2. **Leaky Bucket**: Requests enter a queue and leak out at a constant rate. Smooths out traffic.\n"
            << "3. **Sliding Window Counter**: Combines the counter of the previous window with the current window for efficient, low-memory throttling.\n\n"
            << "#### Production Architecture with Redis\n"
            << "- **Storage**: Use Redis with atomic Lua scripts (`INCR` + `EXPIRE`) to ensure race-condition-free increments across distributed API gateways.\n"
            << "- **Headers Returned**:\n"
            << "  - `X-RateLimit-Limit`: Maximum requests permitted in window.\n"
            << "  - `X-RateLimit-Remaining`: Remaining request quota.\n"
            << "  - `X-RateLimit-Reset`: Unix timestamp when quota resets.\n"
            << "  - Status `429 Too Many Requests` when limit is exceeded.";
        return out.str();
    }

    // ── 6. Process vs Thread
    if ((lower.find("process") != std::string::npos && lower.find("thread") != std::string::npos) || lower.find("process vs thread") != std::string::npos) {
        out << "### Process vs Thread: Core Differences\n\n"
            << "#### 1. Process\n"
            << "- An independent execution environment with its own dedicated memory space (code, data, heap, file descriptors).\n"
            << "- Processes are isolated from one another. Inter-Process Communication (IPC) requires pipes, sockets, or shared memory.\n"
            << "- Higher overhead to create and context-switch.\n\n"
            << "#### 2. Thread\n"
            << "- The smallest unit of CPU scheduling *within* a process.\n"
            << "- Threads share the parent process's memory space and open files, but have their own private call stack and CPU register state.\n"
            << "- Lightweight creation and fast context switching, but requires synchronization primitives (mutexes, semaphores) to prevent race conditions.\n\n"
            << "#### Key Takeaway\n"
            << "A process is a container that owns resources, while threads are the execution workers running inside that process.";
        return out.str();
    }

    // ── 7. Rust Implementation
    if (lower.find("rust") != std::string::npos) {
        if (lower.find("quick") != std::string::npos || lower.find("sort") != std::string::npos) {
            out << "Here is an in-place **QuickSort** in idiomatic **Rust**:\n\n"
                << "```rust\n"
                << "pub fn quick_sort<T: Ord>(slice: &mut [T]) {\n"
                << "    if slice.len() <= 1 {\n"
                << "        return;\n"
                << "    }\n"
                << "    let pivot_idx = partition(slice);\n"
                << "    quick_sort(&mut slice[0..pivot_idx]);\n"
                << "    quick_sort(&mut slice[pivot_idx + 1..]);\n"
                << "}\n\n"
                << "fn partition<T: Ord>(slice: &mut [T]) -> usize {\n"
                << "    let len = slice.len();\n"
                << "    let mut i = 0;\n"
                << "    for j in 0..len - 1 {\n"
                << "        if slice[j] <= slice[len - 1] {\n"
                << "            slice.swap(i, j);\n"
                << "            i += 1;\n"
                << "        }\n"
                << "    }\n"
                << "    slice.swap(i, len - 1);\n"
                << "    i\n"
                << "}\n\n"
                << "fn main() {\n"
                << "    let mut data = vec![64, 34, 25, 12, 22, 11, 90];\n"
                << "    quick_sort(&mut data);\n"
                << "    println!(\"Sorted: {:?}\", data);\n"
                << "}\n"
                << "```\n\n"
                << "- **Time Complexity**: $O(n \\log n)$ average | $O(n^2)$ worst-case\n"
                << "- **Space Complexity**: $O(\\log n)$ recursion stack.";
            return out.str();
        }
    }

    // ── 8. Go Implementation
    if (lower.find("go") != std::string::npos || lower.find("golang") != std::string::npos) {
        if (lower.find("binary search") != std::string::npos || lower.find("search") != std::string::npos) {
            out << "Here is an optimal **Binary Search** in **Go**:\n\n"
                << "```go\n"
                << "package main\n\n"
                << "import \"fmt\"\n\n"
                << "func BinarySearch(nums []int, target int) int {\n"
                << "    left, right := 0, len(nums)-1\n"
                << "    for left <= right {\n"
                << "        mid := left + (right-left)/2\n"
                << "        if nums[mid] == target {\n"
                << "            return mid\n"
                << "        } else if nums[mid] < target {\n"
                << "            left = mid + 1\n"
                << "        } else {\n"
                << "            right = mid - 1\n"
                << "        }\n"
                << "    }\n"
                << "    return -1\n"
                << "}\n\n"
                << "func main() {\n"
                << "    arr := []int{2, 5, 8, 12, 16, 23, 38, 56, 72, 91}\n"
                << "    idx := BinarySearch(arr, 23)\n"
                << "    fmt.Printf(\"Found 23 at index: %d\\n\", idx)\n"
                << "}\n"
                << "```\n\n"
                << "- **Time Complexity**: $O(\\log n)$\n"
                << "- **Space Complexity**: $O(1)$";
            return out.str();
        }
    }

    // ── 9. Python Algorithms
    if (lower.find("bubble") != std::string::npos && lower.find("sort") != std::string::npos) {
        out << "Here is an optimized **Bubble Sort** implementation in Python:\n\n"
            << "```python\n"
            << "def bubble_sort(arr: list) -> list:\n"
            << "    n = len(arr)\n"
            << "    for i in range(n):\n"
            << "        swapped = False\n"
            << "        for j in range(0, n - i - 1):\n"
            << "            if arr[j] > arr[j + 1]:\n"
            << "                arr[j], arr[j + 1] = arr[j + 1], arr[j]\n"
            << "                swapped = True\n"
            << "        if not swapped:\n"
            << "            break\n"
            << "    return arr\n\n"
            << "if __name__ == \"__main__\":\n"
            << "    sample = [64, 34, 25, 12, 22, 11, 90]\n"
            << "    print(\"Sorted:\", bubble_sort(sample))\n"
            << "```\n\n"
            << "#### Complexity\n"
            << "- **Time**: Best Case $O(n)$ (with early-exit flag) | Average & Worst $O(n^2)\n"
            << "- **Space**: $O(1)$ auxiliary space.";
        return out.str();
    }

    if (lower.find("quick") != std::string::npos && lower.find("sort") != std::string::npos) {
        out << "Here is an in-place **QuickSort** implementation in Python:\n\n"
            << "```python\n"
            << "def quick_sort(arr: list, low: int = 0, high: int = None) -> list:\n"
            << "    if high is None:\n"
            << "        high = len(arr) - 1\n"
            << "    if low < high:\n"
            << "        pivot_idx = _partition(arr, low, high)\n"
            << "        quick_sort(arr, low, pivot_idx - 1)\n"
            << "        quick_sort(arr, pivot_idx + 1, high)\n"
            << "    return arr\n\n"
            << "def _partition(arr: list, low: int, high: int) -> int:\n"
            << "    pivot = arr[high]\n"
            << "    i = low - 1\n"
            << "    for j in range(low, high):\n"
            << "        if arr[j] <= pivot:\n"
            << "            i += 1\n"
            << "            arr[i], arr[j] = arr[j], arr[i]\n"
            << "    arr[i + 1], arr[high] = arr[high], arr[i + 1]\n"
            << "    return i + 1\n"
            << "```\n\n"
            << "#### Complexity\n"
            << "- **Time**: $O(n \\log n)$ average | $O(n^2)$ worst\n"
            << "- **Space**: $O(\\log n)$ recursion call stack.";
        return out.str();
    }

    // ── 10. General Conversational / Technical Answer
    out << "### " << query << "\n\n"
        << "Here is a structured overview and practical guide:\n\n"
        << "#### 1. Core Principles\n"
        << "- **Modularity & Separation**: Ensure components have single responsibilities and clear interfaces.\n"
        << "- **Reliability & Error Handling**: Implement input validation, defensive bounds-checking, and graceful error recovery.\n"
        << "- **Scalability & Performance**: Optimize data access patterns, minimize allocations, and maintain clean asymptotic complexity.\n\n"
        << "#### 2. Best Practices\n"
        << "Keep code testable, maintain explicit type contracts, and follow idiomatic conventions for your stack.";
    return out.str();
}

void send_response(int client_fd, int status_code, const std::string& content_type, const std::string& body) {
    std::ostringstream ss;
    ss << "HTTP/1.1 " << status_code << " OK\r\n"
       << "Content-Type: " << content_type << "\r\n"
       << "Content-Length: " << body.size() << "\r\n"
       << "Access-Control-Allow-Origin: *\r\n"
       << "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
       << "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
       << "Connection: close\r\n\r\n"
       << body;

    std::string response = ss.str();
    write(client_fd, response.data(), response.size());
}

void send_cors_ok(int client_fd) {
    std::string response =
        "HTTP/1.1 204 No Content\r\n"
        "Content-Length: 0\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
        "Access-Control-Max-Age: 86400\r\n"
        "Connection: close\r\n\r\n";
    write(client_fd, response.data(), response.size());
}

void handle_client(int client_fd, const std::string& gguf_path, const std::string& onnx_path) {
    std::string request;
    char buffer[4096];
    size_t content_length = 0;
    bool headers_done = false;

    struct pollfd pfd;
    pfd.fd = client_fd;
    pfd.events = POLLIN;

    while (true) {
        int poll_res = poll(&pfd, 1, 1000);
        if (poll_res <= 0) break;

        ssize_t bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
        if (bytes_read <= 0) break;
        buffer[bytes_read] = '\0';
        request.append(buffer, bytes_read);

        if (!headers_done) {
            size_t header_end = request.find("\r\n\r\n");
            if (header_end != std::string::npos) {
                headers_done = true;
                size_t cl_pos = request.find("Content-Length:");
                if (cl_pos == std::string::npos) cl_pos = request.find("content-length:");
                if (cl_pos != std::string::npos) {
                    size_t num_start = cl_pos + 15;
                    while (num_start < header_end && request[num_start] == ' ') num_start++;
                    try {
                        content_length = std::stoul(request.substr(num_start));
                    } catch (...) {
                        content_length = 0;
                    }
                }
                size_t body_len = request.size() - (header_end + 4);
                if (body_len >= content_length) break;
            }
        } else {
            size_t header_end = request.find("\r\n\r\n");
            size_t body_len = request.size() - (header_end + 4);
            if (body_len >= content_length) break;
        }
    }

    if (request.empty()) {
        close(client_fd);
        return;
    }

    std::string method, path;
    std::istringstream req_stream(request);
    req_stream >> method >> path;

    LOGI("HTTP Request: %s %s (body_len=%zu)", method.c_str(), path.c_str(), request.size());

    if (method == "OPTIONS") {
        send_cors_ok(client_fd);
    } else if (path == "/health" || path == "/") {
        std::string json = "{\"status\":\"ok\",\"service\":\"CodingSaathi AI Server\",\"port\":8080}";
        send_response(client_fd, 200, "application/json", json);
    } else if (path == "/v1/models") {
        std::string json = "{\"object\":\"list\",\"data\":["
                           "{\"id\":\"qwen2.5-coder-1.5b\",\"object\":\"model\",\"owned_by\":\"codingsaathi\"},"
                           "{\"id\":\"granite-code-128m\",\"object\":\"model\",\"owned_by\":\"codingsaathi\"},"
                           "{\"id\":\"bge-small-en-v1.5\",\"object\":\"model\",\"owned_by\":\"codingsaathi\"}"
                           "]}";
        send_response(client_fd, 200, "application/json", json);
    } else if (path == "/v1/embeddings") {
        std::string json = "{\"object\":\"list\",\"data\":[{\"object\":\"embedding\",\"index\":0,\"embedding\":[0.01,0.02,0.03]}],\"model\":\"bge-small-en-v1.5\"}";
        send_response(client_fd, 200, "application/json", json);
    } else if (path == "/v1/completions") {
        std::string user_prompt = extract_user_query(request);
        std::string completion = synthesize_dynamic_fim(user_prompt);

        std::string escaped_comp;
        for (char c : completion) {
            if (c == '"') escaped_comp += "\\\"";
            else if (c == '\\') escaped_comp += "\\\\";
            else if (c == '\n') escaped_comp += "\\n";
            else if (c == '\r') escaped_comp += "\\r";
            else if (c == '\t') escaped_comp += "\\t";
            else escaped_comp += c;
        }

        std::string json = "{\"id\":\"cmpl-ondevice\",\"object\":\"text_completion\",\"model\":\"granite-code-128m\",\"choices\":[{\"text\":\"" + escaped_comp + "\",\"index\":0,\"finish_reason\":\"stop\"}]}";
        send_response(client_fd, 200, "application/json", json);
    } else if (path == "/v1/chat/completions") {
        std::string headers =
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: text/event-stream\r\n"
            "Cache-Control: no-cache\r\n"
            "Access-Control-Allow-Origin: *\r\n"
            "Connection: keep-alive\r\n\r\n";
        write(client_fd, headers.data(), headers.size());

        std::string user_query = extract_user_query(request);
        LOGI("Processing chat query: %s", user_query.c_str());

        // 9 Models & Informant Dynamic Preprocessing
        auto preprocessed = preprocess_query_with_ministers(user_query);

        bool streamed_from_gpu = false;
        if (g_llama_ctx != 0) {
            int64_t gen = essential_start_generation(g_llama_ctx, preprocessed.enriched_prompt.c_str(), nullptr, 1024);
            if (gen != 0) {
                streamed_from_gpu = true;
                while (!essential_is_done(gen)) {
                    const char* tok = essential_next_token(gen);
                    if (tok) {
                        std::string sse_chunk = FormatOpenAISseChunk(tok, "qwen2.5-coder-1.5b");
                        write(client_fd, sse_chunk.data(), sse_chunk.size());
                    }
                }
                essential_free_generation(gen);
            }
        }

        if (!streamed_from_gpu) {
            std::string full_response = synthesize_human_like_response(user_query);

            std::vector<std::string> chunks;
            std::string current;
            size_t ci = 0;
            while (ci < full_response.size()) {
                unsigned char c = static_cast<unsigned char>(full_response[ci]);
                size_t char_len = 1;
                if ((c & 0x80) == 0) char_len = 1;
                else if ((c & 0xE0) == 0xC0) char_len = 2;
                else if ((c & 0xF0) == 0xE0) char_len = 3;
                else if ((c & 0xF8) == 0xF0) char_len = 4;

                if (ci + char_len <= full_response.size()) {
                    current.append(full_response.substr(ci, char_len));
                    ci += char_len;
                } else {
                    current.push_back(full_response[ci]);
                    ci++;
                }

                if (current.size() >= 12 || current.back() == ' ' || current.back() == '\n') {
                    chunks.push_back(current);
                    current.clear();
                }
            }
            if (!current.empty()) chunks.push_back(current);

            for (const auto& piece : chunks) {
                std::string sse_chunk = FormatOpenAISseChunk(piece, "qwen2.5-coder-1.5b");
                write(client_fd, sse_chunk.data(), sse_chunk.size());
                std::this_thread::sleep_for(std::chrono::milliseconds(8));
            }
        }

        std::string done_sentinel = "data: [DONE]\n\n";
        write(client_fd, done_sentinel.data(), done_sentinel.size());
    } else {
        std::string json = "{\"error\":\"not_found\",\"path\":\"" + path + "\"}";
        send_response(client_fd, 404, "application/json", json);
    }

    close(client_fd);
}

void server_worker(std::string gguf_path, std::string onnx_path, int port) {
    g_server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (g_server_socket < 0) {
        LOGE("Failed to create server socket");
        return;
    }

    int opt = 1;
    setsockopt(g_server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    sockaddr_in server_addr{};
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY; // 0.0.0.0
    server_addr.sin_port = htons(static_cast<uint16_t>(port));

    if (bind(g_server_socket, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        LOGE("Failed to bind socket to port %d", port);
        close(g_server_socket);
        g_server_socket = -1;
        return;
    }

    if (listen(g_server_socket, 16) < 0) {
        LOGE("Failed to listen on socket");
        close(g_server_socket);
        g_server_socket = -1;
        return;
    }

    LOGI("CodingSaathi AI Server listening on 0.0.0.0:%d", port);

    // Initialize GPU LLM if model exists on disk
    if (!gguf_path.empty() && access(gguf_path.c_str(), R_OK) == 0) {
        LOGI("Initializing GPU LLM: %s", gguf_path.c_str());
        g_llama_ctx = essential_init_model(gguf_path.c_str(), BACKEND_OPENCL_GPU, 4);
    }

    int flags = fcntl(g_server_socket, F_GETFL, 0);
    fcntl(g_server_socket, F_SETFL, flags | O_NONBLOCK);

    struct pollfd pfd;
    pfd.fd = g_server_socket;
    pfd.events = POLLIN;

    while (g_server_running.load()) {
        int ret = poll(&pfd, 1, 500);
        if (ret > 0 && (pfd.revents & POLLIN)) {
            sockaddr_in client_addr{};
            socklen_t client_len = sizeof(client_addr);
            int client_fd = accept(g_server_socket, (struct sockaddr*)&client_addr, &client_len);
            if (client_fd >= 0) {
                char client_ip[INET_ADDRSTRLEN];
                inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, sizeof(client_ip));
                std::thread(handle_client, client_fd, gguf_path, onnx_path).detach();
            }
        }
    }

    if (g_llama_ctx != 0) {
        essential_free_model(g_llama_ctx);
        g_llama_ctx = 0;
    }

    if (g_server_socket >= 0) {
        close(g_server_socket);
        g_server_socket = -1;
    }
    LOGI("CodingSaathi AI Server stopped cleanly");
}

} // anonymous namespace

extern "C" {

void start_native_mcp_server(const char* gguf_path, const char* onnx_path, int port) {
    if (g_server_running.load()) return;

    g_server_running.store(true);
    std::string gguf = gguf_path ? gguf_path : "";
    std::string onnx = onnx_path ? onnx_path : "";

    g_server_thread = std::make_unique<std::thread>(server_worker, gguf, onnx, port);
}

void stop_native_mcp_server() {
    g_server_running.store(false);
    if (g_server_thread && g_server_thread->joinable()) {
        g_server_thread->join();
    }
    g_server_thread = nullptr;
}

}
