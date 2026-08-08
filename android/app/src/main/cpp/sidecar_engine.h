#ifndef SIDECAR_ENGINE_H
#define SIDECAR_ENGINE_H

#include <string>
#include <vector>
#include <memory>
#include <future>
#include <mutex>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <sstream>
#include <android/log.h>
#include "sidecar_c_api.h"
#include <onnxruntime_cxx_api.h>

#define SIDECAR_TAG "SidecarEngine"
#define SLOGI(...) __android_log_print(ANDROID_LOG_INFO,  SIDECAR_TAG, __VA_ARGS__)
#define SLOGE(...) __android_log_print(ANDROID_LOG_ERROR, SIDECAR_TAG, __VA_ARGS__)

namespace essential {

// ── Cognitive Memory Tier Record (sqlite-vec & SIMD search backing) ─────────
struct VectorRecord {
    std::string filePath;         // source_ref_id or file path
    std::string contentChunk;     // raw chunk text or episode summary
    std::vector<float> embedding; // 384-dim (bge-small-en-v1.5)
    std::string category;         // 'working_memory', 'session_history', 'episodic_memory', 'semantic_memory', 'html_mini_app'
    float importanceScore = 1.0f; // Cognitive weight / memory priority
    int accessCount = 1;          // Frequency count
};

// ── Compact BERT-style tokenizer (no external vocab file) ─────────────────────
struct BertTokenizer {
    static constexpr int64_t CLS   = 101;
    static constexpr int64_t SEP   = 102;
    static constexpr int64_t PAD   = 0;
    static constexpr int64_t UNK   = 100;
    static constexpr int     VOCAB  = 30522;
    static constexpr int     MAX_LEN = 128;

    struct Encoding {
        std::vector<int64_t> input_ids;
        std::vector<int64_t> attention_mask;
        std::vector<int64_t> token_type_ids;
    };

    // Tokenize a single sentence
    static Encoding encode(const std::string& text, int max_len = MAX_LEN);

    // Tokenize a query/document pair for the reranker
    static Encoding encodePair(const std::string& query,
                               const std::string& doc,
                               int max_len = MAX_LEN);

private:
    static std::vector<std::string> split(const std::string& text);
    static int64_t hashToken(const std::string& word);
};

// ── Pipeline Coordinator & Cognitive Vault ────────────────────────────────────
class SidecarPipelineCoordinator {
public:
    /**
     * @param intentPath   all_minilm_l6_v2.onnx   – NPU Intent Classifier
     * @param embedPath    bge_small_en_v1_5.onnx  – NPU Dense Embeddings
     * @param rerankerPath bge_reranker_base.onnx  – NPU Context Re-ranker
     * @param langPath     codeberta.onnx          – NPU Code Language ID
     * @param dbPath       sqlite / kingdom_vault.db persistent vector store path
     */
    SidecarPipelineCoordinator(const std::string& intentPath,
                               const std::string& embedPath,
                               const std::string& rerankerPath,
                               const std::string& langPath,
                               const std::string& dbPath);
    ~SidecarPipelineCoordinator();

    // Main pipeline entry point (called from sidecar_c_api)
    SidecarResult* Process(const uint8_t* imgBytes, int32_t imgLen,
                           const std::string& userQuery);

    // Vector store & Cognitive Memory management
    void AddEmbedding(const std::string& filePath,
                      const std::string& chunk,
                      const std::vector<float>& vec,
                      const std::string& category = "semantic_memory",
                      float importanceScore = 1.0f);

    std::vector<VectorRecord> SearchSimilar(const std::vector<float>& queryVec,
                                            size_t topK = 5,
                                            const std::string& categoryFilter = "");

private:
    // ── Cognitive Vault Disk Persistence ────────────────────────────────────
    void LoadVault();
    void SaveVault();

    // ── ONNX Runtime state ───────────────────────────────────────────────────
    Ort::Env            m_env;
    Ort::SessionOptions m_sessionOpts;

    std::unique_ptr<Ort::Session> m_intentSession;    // all-MiniLM-L6-v2
    std::unique_ptr<Ort::Session> m_embedSession;     // bge-small-en-v1.5
    std::unique_ptr<Ort::Session> m_rerankerSession;  // bge-reranker-base
    std::unique_ptr<Ort::Session> m_langSession;      // codeberta

    // ── Inference helpers ────────────────────────────────────────────────────
    std::vector<float> runEmbedding(Ort::Session* session,
                                    const BertTokenizer::Encoding& enc);

    std::string classifyIntent(const std::string& query);
    std::vector<float> embedText(const std::string& text);
    float rerankScore(const std::string& query, const std::string& doc);
    std::string detectLanguage(const std::string& text);

    // ── Vector store & SIMD memory ──────────────────────────────────────────
    std::mutex                m_vectorMutex;
    std::vector<VectorRecord> m_vectorStore;

    static float cosine(const std::vector<float>& a, const std::vector<float>& b);

    // ── Fallbacks (used when a model file is absent / load fails) ────────────
    std::string          detectLanguageFallback(const std::string& text);
    std::vector<float>   embedFallback(const std::string& text);

    std::unique_ptr<Ort::Session> loadSession(const std::string& path);
    std::vector<Ort::Value> runSession(Ort::Session* session,
                                       const BertTokenizer::Encoding& enc);

    std::string m_intentPath;
    std::string m_embedPath;
    std::string m_rerankerPath;
    std::string m_langPath;
    std::string m_dbPath;
};

} // namespace essential

#endif // SIDECAR_ENGINE_H
