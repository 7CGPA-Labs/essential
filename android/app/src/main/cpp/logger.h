#pragma once

#include <string>
#include <mutex>
#include <fstream>
#include <deque>
#include <sstream>
#include <chrono>
#include <iomanip>
#include <android/log.h>

namespace kingdom {

enum class LogLevel { DEBUG, INFO, WARN, ERROR };

class RollingLogger {
public:
    RollingLogger(const std::string& log_path, size_t max_bytes = 10 * 1024 * 1024);
    ~RollingLogger() = default;

    void log(LogLevel level, const std::string& tag, const std::string& message);
    std::string get_recent_lines(int max_lines) const;
    void flush();

private:
    void rotate_if_needed();

    mutable std::mutex m_mutex;
    std::ofstream m_file;
    std::string m_path;
    size_t m_max_bytes;
    size_t m_current_bytes;
    std::deque<std::string> m_recent_lines; // capped at 500
};

} // namespace kingdom

// Convenience macros
#define KLOG_D(logger, tag, msg) \
    do { \
        if (logger) (logger)->log(kingdom::LogLevel::DEBUG, tag, msg); \
        __android_log_print(ANDROID_LOG_DEBUG, (tag), "%s", std::string(msg).c_str()); \
    } while(0)

#define KLOG_I(logger, tag, msg) \
    do { \
        if (logger) (logger)->log(kingdom::LogLevel::INFO, tag, msg); \
        __android_log_print(ANDROID_LOG_INFO, (tag), "%s", std::string(msg).c_str()); \
    } while(0)

#define KLOG_W(logger, tag, msg) \
    do { \
        if (logger) (logger)->log(kingdom::LogLevel::WARN, tag, msg); \
        __android_log_print(ANDROID_LOG_WARN, (tag), "%s", std::string(msg).c_str()); \
    } while(0)

#define KLOG_E(logger, tag, msg) \
    do { \
        if (logger) (logger)->log(kingdom::LogLevel::ERROR, tag, msg); \
        __android_log_print(ANDROID_LOG_ERROR, (tag), "%s", std::string(msg).c_str()); \
    } while(0)
