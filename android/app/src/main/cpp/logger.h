/**
 * logger.h
 *
 * Thread-safe rolling process logger.
 * Captures stdout/stderr, HTTP engine events, ONNX Minister latency,
 * and llama.cpp token metrics into a rolling log file capped at 10 MB.
 */
#ifndef KINGDOM_LOGGER_H
#define KINGDOM_LOGGER_H

#include <string>
#include <mutex>
#include <fstream>
#include <deque>
#include <cstdarg>

namespace kingdom {

class Logger {
public:
    static constexpr size_t MAX_FILE_SIZE = 10 * 1024 * 1024; // 10 MB
    static constexpr int    MAX_MEMORY_LINES = 500;

    static Logger& instance();

    /**
     * Initialise with the directory where server.log will be written.
     */
    void init(const std::string& log_dir);

    /**
     * Write a formatted log line (printf-style).
     */
    void log(const char* tag, const char* fmt, ...);

    /**
     * Retrieve the last `max_lines` from the in-memory ring buffer.
     */
    std::string getRecentLines(int max_lines) const;

    /**
     * Full path to the log file (for sharing / export).
     */
    std::string logFilePath() const;

private:
    Logger() = default;

    mutable std::mutex  m_mutex;
    std::ofstream       m_file;
    std::string         m_path;
    size_t              m_bytesWritten = 0;
    std::deque<std::string> m_ring;

    void rotateIfNeeded();
    std::string timestamp() const;
};

} // namespace kingdom

/* Convenience C-style macro usable from both C++ and plain-C translation units */
#ifdef __cplusplus
#define KLOG(tag, fmt, ...) kingdom::Logger::instance().log(tag, fmt, ##__VA_ARGS__)
#else
void kingdom_log(const char* tag, const char* fmt, ...);
#define KLOG(tag, fmt, ...) kingdom_log(tag, fmt, ##__VA_ARGS__)
#endif

#endif /* KINGDOM_LOGGER_H */
