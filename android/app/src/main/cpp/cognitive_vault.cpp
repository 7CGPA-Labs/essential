/**
 * cognitive_vault.cpp
 *
 * SQLite + sqlite-vec persistence layer for the Kingdom AI Server's
 * cognitive memory architecture.
 *
 * Tables:
 *   session_history  – short-term chat messages per Continue.dev session
 *   memory_records   – metadata for long-term episodic/semantic memory
 *   memory_vectors   – vec0 virtual table for 384-dim dense vector search
 *
 * Uses WAL mode (PRAGMA journal_mode=WAL) for concurrent reads/writes.
 */
#include "cognitive_vault.h"
#include "logger.h"

#include <sqlite3.h>
#include <cstring>
#include <cmath>
#include <algorithm>
#include <sstream>

#define VAULT_TAG "CognitiveVault"

namespace kingdom {

// ── Helpers ────────────────────────────────────────────────────────────────────

static sqlite3* db_ptr(void* p) { return static_cast<sqlite3*>(p); }

CognitiveVault::CognitiveVault(const std::string& db_path) {
    sqlite3* db = nullptr;
    int rc = sqlite3_open(db_path.c_str(), &db);
    if (rc != SQLITE_OK) {
        KLOG(VAULT_TAG, "Failed to open database: %s", sqlite3_errmsg(db));
        return;
    }
    m_db = db;

    // Enable WAL mode
    execSQL("PRAGMA journal_mode=WAL;");
    execSQL("PRAGMA synchronous=NORMAL;");

    // Session history table
    execSQL(
        "CREATE TABLE IF NOT EXISTS session_history ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  session_id TEXT NOT NULL,"
        "  role TEXT NOT NULL,"
        "  content TEXT NOT NULL,"
        "  created_at INTEGER DEFAULT (strftime('%s','now'))"
        ");"
    );
    execSQL("CREATE INDEX IF NOT EXISTS idx_sh_session ON session_history(session_id);");

    // Memory records metadata table
    execSQL(
        "CREATE TABLE IF NOT EXISTS memory_records ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  source_ref TEXT,"
        "  content TEXT,"
        "  category TEXT DEFAULT 'semantic',"
        "  importance REAL DEFAULT 1.0,"
        "  access_count INTEGER DEFAULT 1,"
        "  created_at INTEGER DEFAULT (strftime('%s','now'))"
        ");"
    );

    /* sqlite-vec virtual table for 384-dim dense vectors.
     * If sqlite-vec extension is not loaded this will fail silently;
     * the engine will fall back to brute-force cosine search. */
    execSQL(
        "CREATE VIRTUAL TABLE IF NOT EXISTS memory_vectors USING vec0("
        "  record_id INTEGER PRIMARY KEY,"
        "  embedding FLOAT[384]"
        ");"
    );

    KLOG(VAULT_TAG, "Vault opened: %s", db_path.c_str());
}

CognitiveVault::~CognitiveVault() {
    if (m_db) {
        sqlite3_close(db_ptr(m_db));
        m_db = nullptr;
    }
}

void CognitiveVault::execSQL(const char* sql) {
    char* err = nullptr;
    int rc = sqlite3_exec(db_ptr(m_db), sql, nullptr, nullptr, &err);
    if (rc != SQLITE_OK && err) {
        KLOG(VAULT_TAG, "SQL error: %s – %s", err, sql);
        sqlite3_free(err);
    }
}

// ── Session history ────────────────────────────────────────────────────────────

void CognitiveVault::addSessionMessage(const std::string& session_id,
                                        const std::string& role,
                                        const std::string& content) {
    std::lock_guard<std::mutex> lock(m_mutex);
    const char* sql = "INSERT INTO session_history(session_id, role, content) VALUES(?,?,?);";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_ptr(m_db), sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, role.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, content.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
}

std::vector<CognitiveVault::ChatMessage>
CognitiveVault::getSessionHistory(const std::string& session_id, int limit) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<ChatMessage> result;
    const char* sql =
        "SELECT role, content, created_at FROM session_history "
        "WHERE session_id=? ORDER BY id DESC LIMIT ?;";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_ptr(m_db), sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, session_id.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            ChatMessage m;
            m.role    = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 0));
            m.content = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));
            m.ts      = sqlite3_column_int64(stmt, 2);
            result.push_back(std::move(m));
        }
        sqlite3_finalize(stmt);
    }
    std::reverse(result.begin(), result.end());
    return result;
}

// ── Vector store ───────────────────────────────────────────────────────────────

void CognitiveVault::addEmbedding(const std::string& source_ref,
                                   const std::string& content,
                                   const std::vector<float>& embedding,
                                   const std::string& category,
                                   float importance) {
    std::lock_guard<std::mutex> lock(m_mutex);

    // Insert metadata row
    const char* meta_sql =
        "INSERT INTO memory_records(source_ref, content, category, importance) VALUES(?,?,?,?);";
    sqlite3_stmt* stmt = nullptr;
    int64_t record_id = 0;
    if (sqlite3_prepare_v2(db_ptr(m_db), meta_sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(stmt, 1, source_ref.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, content.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, category.c_str(), -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 4, static_cast<double>(importance));
        sqlite3_step(stmt);
        record_id = sqlite3_last_insert_rowid(db_ptr(m_db));
        sqlite3_finalize(stmt);
    }

    // Insert vector into vec0
    if (record_id > 0 && embedding.size() == 384) {
        const char* vec_sql = "INSERT INTO memory_vectors(record_id, embedding) VALUES(?,?);";
        if (sqlite3_prepare_v2(db_ptr(m_db), vec_sql, -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, record_id);
            sqlite3_bind_blob(stmt, 2, embedding.data(),
                              static_cast<int>(embedding.size() * sizeof(float)),
                              SQLITE_TRANSIENT);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }
}

std::vector<MemoryRecord>
CognitiveVault::searchSimilar(const std::vector<float>& query_vec,
                               int top_k,
                               const std::string& category_filter) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<MemoryRecord> results;

    // Try sqlite-vec KNN query first
    std::string sql =
        "SELECT mv.record_id, mv.distance, mr.source_ref, mr.content, mr.category, mr.importance "
        "FROM memory_vectors mv "
        "JOIN memory_records mr ON mr.id = mv.record_id "
        "WHERE mv.embedding MATCH ? AND k = ?";

    if (!category_filter.empty()) {
        sql += " AND mr.category = '" + category_filter + "'";
    }
    sql += ";";

    sqlite3_stmt* stmt = nullptr;
    if (query_vec.size() == 384 &&
        sqlite3_prepare_v2(db_ptr(m_db), sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_blob(stmt, 1, query_vec.data(),
                          static_cast<int>(query_vec.size() * sizeof(float)),
                          SQLITE_TRANSIENT);
        sqlite3_bind_int(stmt, 2, top_k);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            MemoryRecord r;
            r.id         = sqlite3_column_int64(stmt, 0);
            r.source_ref = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2));
            r.content    = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3));
            r.category   = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 4));
            r.importance = static_cast<float>(sqlite3_column_double(stmt, 5));
            results.push_back(std::move(r));
        }
        sqlite3_finalize(stmt);
    }

    return results;
}

int64_t CognitiveVault::totalRecords() const {
    std::lock_guard<std::mutex> lock(m_mutex);
    int64_t count = 0;
    sqlite3_stmt* stmt = nullptr;
    const char* sql = "SELECT COUNT(*) FROM memory_records;";
    if (sqlite3_prepare_v2(db_ptr(m_db), sql, -1, &stmt, nullptr) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    return count;
}

} // namespace kingdom
