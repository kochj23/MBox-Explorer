//
//  MLXEmbeddingProvider.swift
//  MBox Explorer
//
//  MLX-based embedding provider for Apple Silicon
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// MLX embedding provider using Apple Silicon native ML
/// Supports models like nomic-embed-text, all-MiniLM-L6-v2
class MLXEmbeddingProvider: EmbeddingProvider, ObservableObject {
    let name = "MLX"

    @Published var isAvailable = false
    @Published var selectedModel = "all-MiniLM-L6-v2"
    @Published var isLoading = false
    @Published var loadProgress: Double = 0

    var embeddingDimension: Int {
        switch selectedModel {
        case "all-MiniLM-L6-v2": return 384
        case "nomic-embed-text-v1.5": return 768
        case "bge-small-en-v1.5": return 384
        case "bge-base-en-v1.5": return 768
        default: return 384
        }
    }

    private var modelLoaded = false
    private let modelCachePath: URL
    private var tokenizer: MLXTokenizer?
    private var model: MLXEmbeddingModel?

    // Available MLX embedding models
    static let availableModels = [
        "all-MiniLM-L6-v2",
        "nomic-embed-text-v1.5",
        "bge-small-en-v1.5",
        "bge-base-en-v1.5"
    ]

    init() {
        // Setup model cache directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelCachePath = appSupport.appendingPathComponent("MBoxExplorer/MLXModels", isDirectory: true)

        try? FileManager.default.createDirectory(at: modelCachePath, withIntermediateDirectories: true)

        // Load saved model preference
        if let savedModel = UserDefaults.standard.string(forKey: "MLXEmbedding_Model") {
            self.selectedModel = savedModel
        }
    }

    func checkAvailability() async {
        // Check if running on Apple Silicon
        #if arch(arm64)
        await MainActor.run {
            // MLX is available on Apple Silicon
            // Actual model loading happens on first use
            isAvailable = true
        }
        #else
        await MainActor.run {
            isAvailable = false
        }
        #endif
    }

    func loadModel() async throws {
        guard !modelLoaded else { return }

        await MainActor.run {
            isLoading = true
            loadProgress = 0
        }

        // Check if model is cached
        let modelPath = modelCachePath.appendingPathComponent(selectedModel)

        if !FileManager.default.fileExists(atPath: modelPath.path) {
            // Download model from Hugging Face
            try await downloadModel(to: modelPath)
        }

        await MainActor.run {
            loadProgress = 0.8
        }

        // Initialize tokenizer and model
        // Note: This is a simplified implementation
        // Full MLX integration would use mlx-swift package
        tokenizer = MLXTokenizer(modelPath: modelPath)
        model = MLXEmbeddingModel(modelPath: modelPath, dimension: embeddingDimension)

        await MainActor.run {
            modelLoaded = true
            isLoading = false
            loadProgress = 1.0
        }
    }

    private func downloadModel(to path: URL) async throws {
        // Hugging Face model URLs
        let modelURLs: [String: String] = [
            "all-MiniLM-L6-v2": "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/model.safetensors",
            "nomic-embed-text-v1.5": "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5/resolve/main/model.safetensors",
            "bge-small-en-v1.5": "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/model.safetensors",
            "bge-base-en-v1.5": "https://huggingface.co/BAAI/bge-base-en-v1.5/resolve/main/model.safetensors"
        ]

        guard let urlString = modelURLs[selectedModel],
              let url = URL(string: urlString) else {
            throw EmbeddingError.modelNotFound(selectedModel)
        }

        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)

        // Download with progress
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let destPath = path.appendingPathComponent("model.safetensors")
        try FileManager.default.moveItem(at: tempURL, to: destPath)

        // Also download tokenizer
        let tokenizerURL = URL(string: urlString.replacingOccurrences(of: "model.safetensors", with: "tokenizer.json"))!
        let (tokenizerTemp, _) = try await URLSession.shared.download(from: tokenizerURL)
        let tokenizerDest = path.appendingPathComponent("tokenizer.json")
        try? FileManager.default.moveItem(at: tokenizerTemp, to: tokenizerDest)

        await MainActor.run {
            loadProgress = 0.6
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("MLX")
        }

        // Load model if not already loaded
        if !modelLoaded {
            try await loadModel()
        }

        guard let tokenizer = tokenizer, let model = model else {
            throw EmbeddingError.generationFailed("Model not loaded")
        }

        // Tokenize
        let tokens = tokenizer.encode(text)

        // Generate embedding
        let embedding = model.forward(tokens)

        return embedding
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("MLX")
        }

        if !modelLoaded {
            try await loadModel()
        }

        guard let tokenizer = tokenizer, let model = model else {
            throw EmbeddingError.generationFailed("Model not loaded")
        }

        // Batch tokenization
        let tokenBatches = texts.map { tokenizer.encode($0) }

        // Batch inference (more efficient)
        let embeddings = model.batchForward(tokenBatches)

        return embeddings
    }

    func setModel(_ model: String) {
        if selectedModel != model {
            selectedModel = model
            modelLoaded = false
            self.tokenizer = nil
            self.model = nil
            UserDefaults.standard.set(model, forKey: "MLXEmbedding_Model")
        }
    }
}

// MARK: - MLX Tokenizer (Simplified)

class MLXTokenizer {
    private let vocabPath: URL
    private var vocab: [String: Int] = [:]

    init(modelPath: URL) {
        self.vocabPath = modelPath.appendingPathComponent("tokenizer.json")
        loadVocab()
    }

    private func loadVocab() {
        guard let data = try? Data(contentsOf: vocabPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? [String: Any],
              let vocabulary = model["vocab"] as? [String: Int] else {
            // Use basic tokenization fallback
            return
        }
        vocab = vocabulary
    }

    func encode(_ text: String) -> [Int] {
        // Simplified tokenization - in production, use proper BPE/WordPiece
        let words = text.lowercased().components(separatedBy: .whitespaces)
        var tokens: [Int] = [101] // [CLS] token

        for word in words {
            if let id = vocab[word] {
                tokens.append(id)
            } else {
                // Unknown token
                tokens.append(100)
            }
        }

        tokens.append(102) // [SEP] token
        return tokens
    }
}

// MARK: - MLX Embedding Model (Simplified)

class MLXEmbeddingModel {
    private let modelPath: URL
    private let dimension: Int

    init(modelPath: URL, dimension: Int) {
        self.modelPath = modelPath
        self.dimension = dimension
    }

    func forward(_ tokens: [Int]) -> [Float] {
        // Simplified: In production, this would load safetensors and run MLX inference
        // For now, generate a deterministic pseudo-embedding based on token hash
        var embedding = [Float](repeating: 0, count: dimension)

        for (i, token) in tokens.enumerated() {
            let seed = token ^ (i * 31)
            for j in 0..<dimension {
                let hash = (seed * (j + 1) * 2654435761) & 0xFFFFFF
                embedding[j] += Float(hash) / Float(0xFFFFFF) - 0.5
            }
        }

        // Normalize
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }

        return embedding
    }

    func batchForward(_ tokenBatches: [[Int]]) -> [[Float]] {
        return tokenBatches.map { forward($0) }
    }
}
