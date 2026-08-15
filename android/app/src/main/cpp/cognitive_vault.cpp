#include "cognitive_vault.h"
#include <iostream>
#include <cmath>
#include <sstream>
#include <algorithm>
#include <filesystem>
#include <android/log.h>
#include <cstring>

#define VAULT_LOG_E(msg) __android_log_print(ANDROID_LOG_ERROR, "CognitiveVault", "%s", (msg))
#define VAULT_LOG_I(msg) __android_log_print(ANDROID_LOG_INFO, "CognitiveVault", "%s", (msg))

namespace kingdom {

CognitiveVault::CognitiveVault(const std::string& db_path) : m_db_path(db_path), m_db(nullptr) {
    if (sqlite3_open(m_db_path.c_str(), &m_db) != SQLITE_OK) {
        VAULT_LOG_E(("Failed to open DB: " + std::string(sqlite3_errmsg(m_db))).c_str());
        return;
    }
    init_schema();
}

CognitiveVault::~CognitiveVault() {
    if (m_db) {
        sqlite3_close(m_db);
        m_db = nullptr;
    }
}

void CognitiveVault::init_schema() {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    char* err_msg = nullptr;
    sqlite3_exec(m_db, "PRAGMA journal_mode=WAL;", nullptr, nullptr, &err_msg);
    if (err_msg) { sqlite3_free(err_msg); }

    const char* schema_sql = R"(
        CREATE TABLE IF NOT EXISTS session_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            content_chunk TEXT NOT NULL,
            category TEXT DEFAULT 'semantic_memory',
            importance_score REAL DEFAULT 1.0,
            access_count INTEGER DEFAULT 1,
            created_at INTEGER DEFAULT (strftime('%s','now')),
            embedding_blob BLOB
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_embeddings USING vec0(
            record_id INTEGER PRIMARY KEY,
            embedding float[384]
        );
    )";

    if (sqlite3_exec(m_db, schema_sql, nullptr, nullptr, &err_msg) != SQLITE_OK) {
        VAULT_LOG_E(("Schema init failed: " + std::string(err_msg)).c_str());
        sqlite3_free(err_msg);
    }
}

std::string CognitiveVault::vec_to_blob(const std::vector<float>& v) {
    return std::string(reinterpret_cast<const char*>(v.data()), v.size() * sizeof(float));
}

std::vector<float> CognitiveVault::blob_to_vec(const void* data, int bytes) {
    std::vector<float> v(bytes / sizeof(float));
    std::memcpy(v.data(), data, bytes);
    return v;
}

int64_t CognitiveVault::insert_record(const VaultRecord& record) {
    std::lock_guard<std::mutex> lock(m_mutex);
    
    sqlite3_exec(m_db, "BEGIN TRANSACTION;", nullptr, nullptr, nullptr);

    const char* insert_sql = "INSERT INTO session_history (file_path, content_chunk, category, importance_score, access_count, embedding_blob) VALUES (?, ?, ?, ?, ?, ?);";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(m_db, insert_sql, -1, &stmt, nullptr) != SQLITE_OK) {
        sqlite3_exec(m_db, "ROLLBACK;", nullptr, nullptr, nullptr);
        return -1;
    }

    sqlite3_bind_text(stmt, 1, record.file_path.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, record.content_chunk.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, record.category.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 4, record.importance_score);
    sqlite3_bind_int(stmt, 5, record.access_count);
    
    std::string blob = vec_to_blob(record.embedding);
    sqlite3_bind_blob(stmt, 6, blob.data(), blob.size(), SQLITE_TRANSIENT);

    if (sqlite3_step(stmt) != SQLITE_DONE) {
        sqlite3_finalize(stmt);
        sqlite3_exec(m_db, "ROLLBACK;", nullptr, nullptr, nullptr);
        return -1;
    }
    
    int64_t new_id = sqlite3_last_insert_rowid(m_db);
    sqlite3_finalize(stmt);

    const char* vec_insert_sql = "INSERT INTO vec_embeddings(record_id, embedding) VALUES (?, ?);";
    if (sqlite3_prepare_v2(m_db, vec_insert_sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, new_id);
        sqlite3_bind_blob(stmt, 2, blob.data(), blob.size(), SQLITE_TRANSIENT);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    } else {
        // vec0 might not be available, ignore
    }

    sqlite3_exec(m_db, "COMMIT;", nullptr, nullptr, nullptr);
    return new_id;
}

VaultRecord CognitiveVault::row_to_record(sqlite3_stmt* stmt, bool include_embedding) {
    VaultRecord rec;
    rec.id = sqlite3_column_int64(stmt, 0);
    rec.file_path = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 1));
    rec.content_chunk = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 2));
    rec.category = reinterpret_cast<const char*>(sqlite3_column_text(stmt, 3));
    rec.importance_score = sqlite3_column_double(stmt, 4);
    rec.access_count = sqlite3_column_int(stmt, 5);
    rec.created_at = sqlite3_column_int64(stmt, 6);
    
    if (include_embedding) {
        int bytes = sqlite3_column_bytes(stmt, 7);
        const void* blob = sqlite3_column_blob(stmt, 7);
        if (blob && bytes > 0) {
            rec.embedding = blob_to_vec(blob, bytes);
        }
    }
    return rec;
}

std::vector<VaultRecord> CognitiveVault::search_similar(const std::vector<float>& query_vec, int top_k, const std::string& category_filter) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<VaultRecord> results;

    // Fallback: cosine similarity in C++
    std::string sql = "SELECT id, file_path, content_chunk, category, importance_score, access_count, created_at, embedding_blob FROM session_history";
    if (!category_filter.empty()) {
        sql += " WHERE category = ?";
    }
    
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(m_db, sql.c_str(), -1, &stmt, nullptr) != SQLITE_OK) return results;
    
    if (!category_filter.empty()) {
        sqlite3_bind_text(stmt, 1, category_filter.c_str(), -1, SQLITE_TRANSIENT);
    }

    struct ScoredRecord {
        VaultRecord rec;
        float score;
    };
    std::vector<ScoredRecord> candidates;

    auto cosine_sim = [](const std::vector<float>& a, const std::vector<float>& b) {
        if (a.size() != b.size() || a.empty()) return 0.0f;
        float dot = 0, norm_a = 0, norm_b = 0;
        for (size_t i = 0; i < a.size(); ++i) {
            dot += a[i] * b[i];
            norm_a += a[i] * a[i];
            norm_b += b[i] * b[i];
        }
        return (norm_a > 0 && norm_b > 0) ? dot / (std::sqrt(norm_a) * std::sqrt(norm_b)) : 0.0f;
    };

    while (sqlite3_step(stmt) == SQLITE_ROW) {
        VaultRecord rec = row_to_record(stmt, true);
        float score = cosine_sim(query_vec, rec.embedding);
        candidates.push_back({rec, score});
    }
    sqlite3_finalize(stmt);

    std::sort(candidates.begin(), candidates.end(), [](const ScoredRecord& a, const ScoredRecord& b) {
        return a.score > b.score;
    });

    for (int i = 0; i < std::min(top_k, static_cast<int>(candidates.size())); ++i) {
        results.push_back(candidates[i].rec);
    }

    return results;
}

bool CognitiveVault::delete_record(int64_t id) {
    std::lock_guard<std::mutex> lock(m_mutex);
    const char* sql = "DELETE FROM session_history WHERE id = ?;";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(m_db, sql, -1, &stmt, nullptr) != SQLITE_OK) return false;
    sqlite3_bind_int64(stmt, 1, id);
    bool success = (sqlite3_step(stmt) == SQLITE_DONE);
    sqlite3_finalize(stmt);
    
    if (success) {
        const char* vec_sql = "DELETE FROM vec_embeddings WHERE record_id = ?;";
        if (sqlite3_prepare_v2(m_db, vec_sql, -1, &stmt, nullptr) == SQLITE_OK) {
            sqlite3_bind_int64(stmt, 1, id);
            sqlite3_step(stmt);
            sqlite3_finalize(stmt);
        }
    }
    return success;
}

std::vector<VaultRecord> CognitiveVault::get_session_history(int limit) {
    std::lock_guard<std::mutex> lock(m_mutex);
    std::vector<VaultRecord> results;
    
    const char* sql = "SELECT id, file_path, content_chunk, category, importance_score, access_count, created_at FROM session_history ORDER BY created_at DESC LIMIT ?;";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(m_db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(stmt, 1, limit);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            results.push_back(row_to_record(stmt, false));
        }
        sqlite3_finalize(stmt);
    }
    return results;
}

void CognitiveVault::prune_old_records(int keep_count) {
    std::lock_guard<std::mutex> lock(m_mutex);
    const char* sql = "DELETE FROM session_history WHERE id NOT IN (SELECT id FROM session_history ORDER BY importance_score DESC, created_at DESC LIMIT ?);";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(m_db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(stmt, 1, keep_count);
        sqlite3_step(stmt);
        sqlite3_finalize(stmt);
    }
}

std::string CognitiveVault::export_diagnostics() {
    std::lock_guard<std::mutex> lock(m_mutex);
    int count = 0;
    const char* sql = "SELECT COUNT(*) FROM session_history;";
    sqlite3_stmt* stmt;
    if (sqlite3_prepare_v2(m_db, sql, -1, &stmt, nullptr) == SQLITE_OK) {
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }
    
    std::error_code ec;
    auto size = std::filesystem::file_size(m_db_path, ec);
    if (ec) size = 0;

    std::ostringstream oss;
    oss << "{\"record_count\": " << count << ", \"db_size_bytes\": " << size << ", \"wal_mode\": true}";
    return oss.str();
}

} // namespace kingdom
