#include "sidecar_engine.h"
#include <cmath>
#include <algorithm>
#include <cstring>
#include <sstream>
#include <chrono>

namespace essential {

SidecarPipelineCoordinator::SidecarPipelineCoordinator(const std::string& langPath,
                                                         const std::string& embedPath,
                                                         const std::string& dbPath)
    : m_langPath(langPath), m_embedPath(embedPath), m_dbPath(dbPath) {
    
    // Seed vector store with initial codebase chunks for rapid dot-product retrieval
    AddEmbedding(
        "lib/mini_apps/mini_app_webview.dart",
        "Essential JS bridge providing GPS, Notifications, Flashlight, and Sensor streams.",
        GenerateEmbedding("Essential JS bridge providing GPS, Notifications, Flashlight, and Sensor streams.")
    );
    AddEmbedding(
        "lib/projects/project_studio_page.dart",
        "Split-screen pair programming studio for live HTML mini app generation and diff-based editing.",
        GenerateEmbedding("Split-screen pair programming studio for live HTML mini app generation and diff-based editing.")
    );
}

SidecarPipelineCoordinator::~SidecarPipelineCoordinator() {}

float SidecarPipelineCoordinator::CosineSimilarity(const std::vector<float>& a, const std::vector<float>& b) {
    if (a.empty() || b.empty() || a.size() != b.size()) return 0.0f;

    float dot = 0.0f;
    float normA = 0.0f;
    float normB = 0.0f;

    for (size_t i = 0; i < a.size(); ++i) {
        dot += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }

    if (normA == 0.0f || normB == 0.0f) return 0.0f;
    return dot / (std::sqrt(normA) * std::sqrt(normB));
}

void SidecarPipelineCoordinator::AddEmbedding(const std::string& filePath,
                                               const std::string& chunk,
                                               const std::vector<float>& vec) {
    std::lock_guard<std::mutex> lock(m_vectorMutex);
    m_vectorStore.push_back({filePath, chunk, vec});
}

std::vector<VectorRecord> SidecarPipelineCoordinator::SearchSimilar(const std::vector<float>& queryVec, size_t topK) {
    std::lock_guard<std::mutex> lock(m_vectorMutex);
    
    struct ScoredRecord {
        VectorRecord record;
        float score;
    };

    std::vector<ScoredRecord> scored;
    for (const auto& rec : m_vectorStore) {
        float sim = CosineSimilarity(queryVec, rec.embedding);
        scored.push_back({rec, sim});
    }

    std::sort(scored.begin(), scored.end(), [](const ScoredRecord& a, const ScoredRecord& b) {
        return a.score > b.score;
    });

    std::vector<VectorRecord> results;
    for (size_t i = 0; i < std::min(topK, scored.size()); ++i) {
        results.push_back(scored[i].record);
    }
    return results;
}

std::string SidecarPipelineCoordinator::DetectLanguage(const std::string& codeText) {
    if (codeText.find("void main") != std::string::npos || codeText.find("import 'package:") != std::string::npos) {
        return "dart";
    } else if (codeText.find("def ") != std::string::npos || codeText.find("import ") != std::string::npos) {
        return "python";
    } else if (codeText.find("#include") != std::string::npos || codeText.find("std::") != std::string::npos) {
        return "cpp";
    } else if (codeText.find("function") != std::string::npos || codeText.find("const ") != std::string::npos) {
        return "javascript";
    }
    return "auto-detected";
}

std::vector<float> SidecarPipelineCoordinator::GenerateEmbedding(const std::string& text) {
    // 384-dimensional dense vector simulation for bge-small-en-v1.5
    std::vector<float> vec(384, 0.0f);
    for (size_t i = 0; i < text.size(); ++i) {
        size_t idx = (i * 13 + static_cast<unsigned char>(text[i])) % 384;
        vec[idx] += 1.0f;
    }
    // Normalize vector L2
    float norm = 0.0f;
    for (float f : vec) norm += f * f;
    norm = std::sqrt(norm);
    if (norm > 0) {
        for (float& f : vec) f /= norm;
    }
    return vec;
}

SidecarResult* SidecarPipelineCoordinator::Process(const uint8_t* imgBytes, int32_t imgLen, const std::string& userQuery) {
    auto futureEmbed = std::async(std::launch::async, [this, &userQuery]() {
        return GenerateEmbedding(userQuery);
    });

    std::vector<float> queryVec = futureEmbed.get();

    std::string detectedLang = DetectLanguage(userQuery);
    std::vector<VectorRecord> topDocs = SearchSimilar(queryVec, 2);

    std::string retrievedContext = "";
    for (const auto& doc : topDocs) {
        retrievedContext += "[" + doc.filePath + "]: " + doc.contentChunk + "\n";
    }

    std::string fullPrompt =
        "<|im_start|>system\nYou are CodingSaathi AI running on GPU.\n"
        "Context:\n" + retrievedContext + "<|im_end|>\n"
        "<|im_start|>user\n" + userQuery + "<|im_end|>\n"
        "<|im_start|>assistant\n";

    // Allocate SidecarResult heap pointers for C-ABI export
    SidecarResult* res = new SidecarResult();
    res->extracted_code = strdup("");
    res->detected_language = strdup(detectedLang.c_str());
    res->retrieved_context = strdup(retrievedContext.c_str());
    res->fully_formatted_prompt = strdup(fullPrompt.c_str());

    return res;
}

} // namespace essential
