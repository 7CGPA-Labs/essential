#include "logger.h"
#include <ctime>
#include <chrono>
#include <sstream>
#include <iomanip>
#include <filesystem>

namespace kingdom {

RollingLogger::RollingLogger(const std::string& log_path, size_t max_bytes)
    : m_path(log_path), m_max_bytes(max_bytes), m_current_bytes(0) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_file.open(m_path, std::ios::app);
    if (m_file.is_open()) {
        m_file.seekp(0, std::ios::end);
        m_current_bytes = static_cast<size_t>(m_file.tellp());
    }
}

void RollingLogger::log(LogLevel level, const std::string& tag, const std::string& message) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto now = std::chrono::system_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;
    auto now_c = std::chrono::system_clock::to_time_t(now);
    std::tm* tm = std::localtime(&now_c);

    std::ostringstream oss;
    oss << "[" << std::put_time(tm, "%Y-%m-%d %H:%M:%S") << "." << std::setfill('0') << std::setw(3) << ms.count() << "] ";

    switch (level) {
        case LogLevel::DEBUG: oss << "[DEBUG] "; break;
        case LogLevel::INFO:  oss << "[INFO] "; break;
        case LogLevel::WARN:  oss << "[WARN] "; break;
        case LogLevel::ERROR: oss << "[ERROR] "; break;
    }

    oss << "[" << tag << "] " << message;
    std::string log_line = oss.str();

    if (m_file.is_open()) {
        m_file << log_line << std::endl;
        m_current_bytes += log_line.length() + 1; // +1 for newline
    }

    m_recent_lines.push_back(log_line);
    if (m_recent_lines.size() > 500) {
        m_recent_lines.pop_front();
    }

    rotate_if_needed();
}

void RollingLogger::rotate_if_needed() {
    if (m_current_bytes >= m_max_bytes) {
        if (m_file.is_open()) {
            m_file.close();
        }
        
        std::error_code ec;
        std::string old_path = m_path + ".old";
        std::filesystem::remove(old_path, ec);
        std::filesystem::rename(m_path, old_path, ec);
        
        m_file.open(m_path, std::ios::app);
        m_current_bytes = 0;
    }
}

std::string RollingLogger::get_recent_lines(int max_lines) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::ostringstream oss;
    
    int count = 0;
    int start_idx = static_cast<int>(m_recent_lines.size()) - max_lines;
    if (start_idx < 0) start_idx = 0;
    
    for (int i = start_idx; i < m_recent_lines.size(); ++i) {
        oss << m_recent_lines[i] << "\n";
    }
    
    return oss.str();
}

void RollingLogger::flush() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_file.is_open()) {
        m_file.flush();
    }
}

} // namespace kingdom
