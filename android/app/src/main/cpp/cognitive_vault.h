/**
 * cognitive_vault.h
 *
 * Repository-pattern persistence layer wrapping SQLite + sqlite-vec.
 * Manages:
 *   - Working Memory (active KV-cache metadata)
 *   - Short-Term Memory (session_history for Continue.dev chat threads)
 *   - Long-Term Episodic & Semantic Memory (384-dim dense vectors via vec0)
 *
 * Uses WAL mode for non-blocking concurrent reads and writes.
 */
#ifndef COGNITIVE_VAULT_H
#define COGNITIVE_VAULT_H

#include <string>
#include <vector>
#include <mutex>

namespace kingdom {

struct MemoryRecord {
    int64_t     id;
    std::string source_ref;      // file path or session id
    std::string content;         // raw text chunk
    std::string category;        // working_memory | session_history | episodic | semantic
    float       importance;
    int         access_count;
    std::vector<float> embedding; // 384-dim
};

class CognitiveVault {
public:
    /**
     * Open (or create) the vault database at `db_path`.
     * Enables WAL mode and creates tables including vec0 virtual table.
     */
    explicit CognitiveVault(const std::string& db_path);
    ~CognitiveVault();

    // ── Session history (short-term memory) ─────────────────────────────────
    void addSessionMessage(const std::string& session_id,
                           const std::string& role,
                           const std::string& content);

    struct ChatMessage { std::string role; std::string content; int64_t ts; };
    std::vector<ChatMessage> getSessionHistory(const std::string& session_id,
                                                int limit = 50);

    // ── Vector store (long-term memory) ─────────────────────────────────────
    void addEmbedding(const std::string& source_ref,
                      const std::string& content,
                      const std::vector<float>& embedding,
                      const std::string& category = "semantic",
                      float importance = 1.0f);

    std::vector<MemoryRecord> searchSimilar(const std::vector<float>& query_vec,
                                             int top_k = 5,
                                             const std::string& category_filter = "");

    // ── Diagnostics ─────────────────────────────────────────────────────────
    int64_t totalRecords() const;

private:
    void* m_db = nullptr; // sqlite3*
    mutable std::mutex m_mutex;

    void execSQL(const char* sql);
};

} // namespace kingdom

#endif /* COGNITIVE_VAULT_H */
