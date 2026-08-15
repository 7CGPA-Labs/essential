import Foundation

actor ModelAssetManager {
    static let shared = ModelAssetManager()
    
    struct ModelSpec {
        let filename: String
        let url: URL
        let expectedSizeBytes: Int64
        let subdirectory: String
        
        init(_ filename: String, _ url: URL, _ expectedSizeBytes: Int64, _ subdirectory: String) {
            self.filename = filename
            self.url = url
            self.expectedSizeBytes = expectedSizeBytes
            self.subdirectory = subdirectory
        }
    }
    
    static let modelRegistry: [ModelSpec] = [
        ModelSpec("qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
                  URL(string: "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf")!,
                  1_100_000_000, ""),
        ModelSpec("all_minilm_l6_v2.onnx",
                  URL(string: "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx")!,
                  25_000_000, "models"),
        ModelSpec("bge_small_en_v1_5.onnx",
                  URL(string: "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/onnx/model.onnx")!,
                  60_000_000, "models"),
        ModelSpec("bge_reranker_base.onnx",
                  URL(string: "https://huggingface.co/BAAI/bge-reranker-base/resolve/main/onnx/model.onnx")!,
                  110_000_000, "models"),
        ModelSpec("codeberta_base.onnx",
                  URL(string: "https://huggingface.co/huggingface/CodeBERTa-small-v1/resolve/main/onnx/model.onnx")!,
                  125_000_000, "models"),
        ModelSpec("nli_deberta_v3_small.onnx",
                  URL(string: "https://huggingface.co/cross-encoder/nli-deberta-v3-small/resolve/main/onnx/model.onnx")!,
                  90_000_000, "models"),
        ModelSpec("granite_code_128m.onnx",
                  URL(string: "https://huggingface.co/ibm-granite/granite-3.3-2b-instruct/resolve/main/onnx/model.onnx")!,
                  130_000_000, "models"),
        ModelSpec("codebert_base.onnx",
                  URL(string: "https://huggingface.co/microsoft/codebert-base/resolve/main/onnx/model.onnx")!,
                  125_000_000, "models"),
        ModelSpec("mobile_diffusion_lcm.onnx",
                  URL(string: "https://huggingface.co/nicjac/lcm-sdxl-onnx/resolve/main/unet/model.onnx")!,
                  280_000_000, "models")
    ]
    
    enum ModelStatus { case present, missing, downloading(progress: Double), failed(Error) }
    
    func checkAllModels() async -> [String: ModelStatus] {
        var statuses: [String: ModelStatus] = [:]
        for spec in Self.modelRegistry {
            if verifyModel(spec) {
                statuses[spec.filename] = .present
            } else {
                statuses[spec.filename] = .missing
            }
        }
        return statuses
    }
    
    func downloadMissingModels(progress: @escaping (String, Double) -> Void) async throws {
        for spec in Self.modelRegistry {
            if !verifyModel(spec) {
                try await downloadModel(spec, progress: progress)
            }
        }
    }
    
    func getModelsDirectory() -> URL {
        let fm = FileManager.default
        let docURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let modelsDir = docURL.appendingPathComponent("KingdomModels")
        if !fm.fileExists(atPath: modelsDir.path) {
            try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        return modelsDir
    }
    
    func getLLMPath() -> String {
        let modelsDir = getModelsDirectory()
        return modelsDir.appendingPathComponent("qwen2.5-coder-1.5b-instruct-q4_k_m.gguf").path
    }
    
    func verifyModel(_ spec: ModelSpec) -> Bool {
        let fileURL = getModelsDirectory().appendingPathComponent(spec.subdirectory).appendingPathComponent(spec.filename)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64 else {
            return false
        }
        // Verification: size >= 90% of expected
        return fileSize > Int64(Double(spec.expectedSizeBytes) * 0.9)
    }
    
    private func downloadModel(_ spec: ModelSpec, progress: @escaping (String, Double) -> Void) async throws {
        let targetDir = getModelsDirectory().appendingPathComponent(spec.subdirectory)
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let targetURL = targetDir.appendingPathComponent(spec.filename)
        let tempURL = targetURL.appendingPathExtension("tmp")
        
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: spec.url)
        let expectedLength = response.expectedContentLength
        
        guard let outputStream = OutputStream(url: tempURL, append: false) else { return }
        outputStream.open()
        defer { outputStream.close() }
        
        var bytesDownloaded: Int64 = 0
        var lastUpdate = Date()
        
        for try await byte in asyncBytes {
            var buffer = byte
            outputStream.write(&buffer, maxLength: 1)
            bytesDownloaded += 1
            
            let now = Date()
            if now.timeIntervalSince(lastUpdate) > 0.5 {
                let prog = expectedLength > 0 ? Double(bytesDownloaded) / Double(expectedLength) : 0.0
                progress(spec.filename, prog)
                lastUpdate = now
            }
        }
        
        progress(spec.filename, 1.0)
        
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: targetURL)
    }
}
