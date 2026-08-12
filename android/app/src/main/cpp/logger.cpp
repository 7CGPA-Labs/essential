/**
 * logger.cpp
 *
 * Thread-safe rolling process logger implementation.
 * Redirects C++ HTTP engine events to a rolling log file (server.log)
 * capped at 10 MB with automatic rotation.
 */
#include "logger.h"

#include <chrono>
#include <ctime>
#include <cstdio>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <filesystem>

#ifdef __ANDROID__
#include <android/log.h>
#endif

namespace kingdom {

Logger& Logger::instance() {
    static Logger s_instance;
    return s_instance;
}

void Logger::init(const std::string& log_dir) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_path = log_dir + "/server.log";

    // Attempt to get existing file size for rotation tracking
    std::ifstream probe(m_path, std::ios::ate | std::ios::binary);
    if (probe.is_open()) {
        m_bytesWritten = static_cast<size_t>(probe.tellg());
        probe.close();
    } else {
        m_bytesWritten = 0;
    }

    m_file.open(m_path, std::ios::app);
    if (m_file.is_open()) {
        std::string msg = "[Logger] Initialised – log_dir=" + log_dir + "\n";
        m_file << msg;
        m_file.flush();
        m_bytesWritten += msg.size();
    }
}

void Logger::log(const char* tag, const char* fmt, ...) {
    char buf[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    std::string ts = timestamp();
    std::string line = ts + " [" + (tag ? tag : "?") + "] " + buf + "\n";

#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, tag ? tag : "Kingdom", "%s", buf);
#endif

    std::lock_guard<std::mutex> lock(m_mutex);

    // Ring buffer
    m_ring.push_back(line);
    if (static_cast<int>(m_ring.size()) > MAX_MEMORY_LINES) {
        m_ring.pop_front();
    }

    // File
    if (m_file.is_open()) {
        rotateIfNeeded();
        m_file << line;
        m_file.flush();
        m_bytesWritten += line.size();
    }
}

std::string Logger::getRecentLines(int max_lines) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::ostringstream out;
    int start = 0;
    if (max_lines > 0 && max_lines < static_cast<int>(m_ring.size())) {
        start = static_cast<int>(m_ring.size()) - max_lines;
    }
    for (int i = start; i < static_cast<int>(m_ring.size()); ++i) {
        out << m_ring[static_cast<size_t>(i)];
    }
    return out.str();
}

std::string Logger::logFilePath() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_path;
}

void Logger::rotateIfNeeded() {
    if (m_bytesWritten >= MAX_FILE_SIZE) {
        m_file.close();
        std::string backup = m_path + ".old";
        std::rename(m_path.c_str(), backup.c_str());
        m_file.open(m_path, std::ios::trunc);
        m_bytesWritten = 0;
    }
}

std::string Logger::timestamp() const {
    auto now = std::chrono::system_clock::now();
    auto t = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;
    std::tm tm_buf{};
#ifdef _WIN32
    localtime_s(&tm_buf, &t);
#else
    localtime_r(&t, &tm_buf);
#endif
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm_buf);
    std::ostringstream ss;
    ss << buf << "." << std::setfill('0') << std::setw(3) << ms.count();
    return ss.str();
}

} // namespace kingdom

/* C-linkage wrapper for plain-C translation units */
extern "C" void kingdom_log(const char* tag, const char* fmt, ...) {
    char buf[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    kingdom::Logger::instance().log(tag, "%s", buf);
}
