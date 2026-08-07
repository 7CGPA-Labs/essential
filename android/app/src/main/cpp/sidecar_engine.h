#ifndef SIDECAR_ENGINE_H
#define SIDECAR_ENGINE_H

#include <string>
#include <vector>
#include <memory>
#include <future>
#include <mutex>
#include <unordered_map>
#include "sidecar_c_api.h"

namespace essential {

// Vector store item (384-dimensional bge-small-en-v1.5 embedding)
struct VectorRecord {
    std::string filePath;
    std::string contentChunk;
    std::vector<float> embedding; // 384-dim vector
};

class SidecarPipelineCoordinator {
public:
    SidecarPipelineCoordinator(const std::string& langPath,
                               const std::string& embedPath,
                               const std::string& dbPath);
    ~SidecarPipelineCoordinator();

    SidecarResult* Process(const uint8_t* imgBytes, int32_t imgLen, const std::string& userQuery);

    // Vector operations
    void AddEmbedding(const std::string& filePath, const std::string& chunk, const std::vector<float>& vec);
    std::vector<VectorRecord> SearchSimilar(const std::vector<float>& queryVec, size_t topK = 3);

private:
    std::string DetectLanguage(const std::string& codeText);
    std::vector<float> GenerateEmbedding(const std::string& text);
    static float CosineSimilarity(const std::vector<float>& a, const std::vector<float>& b);

    std::string m_langPath;
    std::string m_embedPath;
    std::string m_dbPath;

    std::mutex m_vectorMutex;
    std::vector<VectorRecord> m_vectorStore;
};

} // namespace essential

#endif // SIDECAR_ENGINE_H
