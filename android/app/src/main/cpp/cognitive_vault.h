#pragma once

#include <sqlite3.h>
#include <vector>
#include <string>
#include <mutex>
#include <optional>
#include <functional>

namespace kingdom {

struct VaultRecord {
    int64_t id = 0;
    std::string file_path;
    std::string content_chunk;
    std::vector<float> embedding; // 384-dim
    std::string category = "semantic_memory";
    float importance_score = 1.0f;
    int access_count = 1;
    int64_t created_at = 0;
};

class CognitiveVault {
public:
    CognitiveVault(const std::string& db_path);
    ~CognitiveVault();

    int64_t insert_record(const VaultRecord& record);
    std::vector<VaultRecord> search_similar(const std::vector<float>& query_vec, int top_k = 5, const std::string& category_filter = "");
    bool delete_record(int64_t id);
    std::vector<VaultRecord> get_session_history(int limit = 50);
    void prune_old_records(int keep_count = 1000);
    std::string export_diagnostics();

private:
    void init_schema();
    VaultRecord row_to_record(sqlite3_stmt* stmt, bool include_embedding = false);
    std::string vec_to_blob(const std::vector<float>& v);
    std::vector<float> blob_to_vec(const void* data, int bytes);

    sqlite3* m_db;
    std::mutex m_mutex;
    std::string m_db_path;
};

} // namespace kingdom
