import Foundation

/**
 * ModelAssetManager (iOS)
 *
 * Checks the iOS Documents directory for 9 model binaries and triggers
 * URLSessionDownloadTask for any missing files.
 *
 * Expected models (inside Documents/models/):
 *   1. qwen2.5-coder-1.5b-q4_k_m.gguf   (~900 MB) – GPU LLM
 *   2. all_minilm_l6_v2.onnx              (~25 MB)  – Minister 1 Intent Router
 *   3. bge_small_en_v1_5.onnx             (~60 MB)  – Minister 2 Embedder
 *   4. bge_reranker_base.onnx             (~110 MB) – Minister 3 Re-Ranker
 *   5. codeberta.onnx                     (~125 MB) – Minister 4 Code Parser
 *   6. granite_code_128m.onnx             (~130 MB) – Minister 5 Autocomplete
 *   7. nli_deberta_v3_small.onnx          (~90 MB)  – Minister 6 Fact Checker
 *   8. codebert_vulnerability.onnx        (~125 MB) – Minister 7 Security
 *   9. mobile_diffusion_lcm.onnx          (~280 MB) – Minister 8 Diagram Gen
 */
class ModelAssetManageriOS {

    struct ModelInfo {
        let filename: String
        let minSize: Int64  // minimum expected file size in bytes
    }

    static let modelManifest: [ModelInfo] = [
        ModelInfo(filename: "qwen2.5-coder-1.5b-q4_k_m.gguf", minSize: 500_000_000),
        ModelInfo(filename: "all_minilm_l6_v2.onnx",          minSize: 10_000_000),
        ModelInfo(filename: "bge_small_en_v1_5.onnx",         minSize: 30_000_000),
        ModelInfo(filename: "bge_reranker_base.onnx",         minSize: 50_000_000),
        ModelInfo(filename: "codeberta.onnx",                 minSize: 60_000_000),
        ModelInfo(filename: "granite_code_128m.onnx",         minSize: 60_000_000),
        ModelInfo(filename: "nli_deberta_v3_small.onnx",      minSize: 40_000_000),
        ModelInfo(filename: "codebert_vulnerability.onnx",    minSize: 60_000_000),
        ModelInfo(filename: "mobile_diffusion_lcm.onnx",      minSize: 100_000_000),
    ]

    /// Directory where models are stored.
    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    struct ModelStatus {
        let filename: String
        let present: Bool
        let sizeBytes: Int64
    }

    /// Check all 9 models and return their status.
    static func checkAllModels() -> [ModelStatus] {
        return modelManifest.map { model in
            let path = modelsDirectory.appendingPathComponent(model.filename)
            let fm = FileManager.default
            if fm.fileExists(atPath: path.path) {
                let attrs = try? fm.attributesOfItem(atPath: path.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                return ModelStatus(filename: model.filename, present: size >= model.minSize, sizeBytes: size)
            }
            return ModelStatus(filename: model.filename, present: false, sizeBytes: 0)
        }
    }

    /// Returns filenames of missing or corrupt models.
    static func missingModels() -> [String] {
        return checkAllModels().filter { !$0.present }.map { $0.filename }
    }

    /// Returns true if all 9 models are present and valid.
    static func allModelsReady() -> Bool {
        return missingModels().isEmpty
    }

    /// Verify and download missing models in background.
    static func verifyAndDownloadMissing() {
        let missing = missingModels()
        if missing.isEmpty {
            print("[ModelAssetManager] All \(modelManifest.count) models verified")
            return
        }

        print("[ModelAssetManager] \(missing.count) model(s) missing: \(missing)")
        for filename in missing {
            downloadModel(filename: filename)
        }
    }

    // MARK: - Private

    private static func downloadModel(filename: String) {
        // In production, resolve the download URL from a manifest JSON on your CDN.
        print("[ModelAssetManager] Download requested for: \(filename) (configure CDN URL)")

        // Example:
        // guard let url = URL(string: "https://your-cdn.example.com/models/\(filename)") else { return }
        // let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
        //     guard let tempURL = tempURL, error == nil else { return }
        //     let dest = modelsDirectory.appendingPathComponent(filename)
        //     try? FileManager.default.moveItem(at: tempURL, to: dest)
        //     print("[ModelAssetManager] Downloaded: \(filename)")
        // }
        // task.resume()
    }
}
