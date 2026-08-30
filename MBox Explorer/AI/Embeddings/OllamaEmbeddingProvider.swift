//
//  OllamaEmbeddingProvider.swift
//  MBox Explorer
//
//  Ollama-based embedding provider
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Ollama embedding provider using nomic-embed-text or similar models
class OllamaEmbeddingProvider: EmbeddingProvider, ObservableObject {
    let name = "Ollama"

    @Published var isAvailable = false
    @Published var selectedModel = "nomic-embed-text"

    var embeddingDimension: Int {
        // nomic-embed-text: 768, all-minilm: 384, bge-m3: 1024, mxbai-embed-large: 1024
        let model = selectedModel.lowercased()
        if model.contains("bge") || model.contains("mxbai") || model.contains("e5-large") {
            return 1024
        }
        if model.contains("minilm") || model.contains("e5-small") || model.contains("gte-small") {
            return 384
        }
        return 768  // nomic-embed-text, e5-base, gte-base, etc.
    }

    private var baseURL: String
    private var availableModels: [String] = []

    init(baseURL: String? = nil) {
        // Use shared Ollama URL from UserDefaults, fallback to default
        self.baseURL = baseURL ?? UserDefaults.standard.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"

        // Load saved model preference from shared key
        if let savedModel = UserDefaults.standard.string(forKey: "ollamaEmbeddingModel") {
            self.selectedModel = savedModel
        }
    }

    /// Update the base URL (called when user changes Ollama server in settings)
    func updateBaseURL(_ urlString: String) {
        self.baseURL = urlString
    }

    /// Update the selected model (called when user changes embedding model in settings)
    func updateModel(_ model: String) {
        self.selectedModel = model
    }

    func checkAvailability() async {
        #if DEBUG
        DebugLogger.shared.debug("OllamaEmbeddingProvider.checkAvailability: baseURL=\(baseURL), selectedModel=\(selectedModel)")
        #endif
        do {
            // Check if Ollama is running
            guard let url = URL(string: "\(baseURL)/api/tags") else {
                #if DEBUG
                DebugLogger.shared.warn("OllamaEmbeddingProvider: invalid URL \(baseURL)/api/tags")
                #endif
                await MainActor.run { isAvailable = false }
                return
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if DEBUG
                DebugLogger.shared.warn("OllamaEmbeddingProvider: HTTP status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                await MainActor.run { isAvailable = false }
                return
            }

            // Parse available models using JSONDecoder for consistency with OllamaClient
            let decoder = JSONDecoder()
            if let modelsResponse = try? decoder.decode(OllamaModelsResponse.self, from: data) {
                let modelNames = modelsResponse.models.map { $0.name }
                #if DEBUG
                DebugLogger.shared.info("OllamaEmbeddingProvider: found models: \(modelNames)")
                #endif

                // Check for embedding models
                let embeddingModels = modelNames.filter {
                    $0.contains("embed") || $0.contains("nomic") || $0.contains("minilm") || $0.contains("mxbai") || $0.contains("bge") || $0.contains("e5-") || $0.contains("gte-")
                }

                #if DEBUG
                DebugLogger.shared.info("OllamaEmbeddingProvider: embedding models: \(embeddingModels)")
                #endif

                await MainActor.run {
                    availableModels = embeddingModels
                    isAvailable = !embeddingModels.isEmpty

                    // Auto-select best available model
                    if !embeddingModels.contains(selectedModel) && !embeddingModels.isEmpty {
                        selectedModel = embeddingModels.first!
                    }
                }
            } else {
                #if DEBUG
                DebugLogger.shared.warn("OllamaEmbeddingProvider: failed to parse models response")
                #endif
                await MainActor.run { isAvailable = false }
            }
        } catch {
            #if DEBUG
            DebugLogger.shared.error("OllamaEmbeddingProvider.checkAvailability error: \(error)")
            #endif
            await MainActor.run { isAvailable = false }
        }
    }

    // Ollama API response model for /api/tags
    private struct OllamaModelsResponse: Codable {
        struct Model: Codable {
            let name: String
        }
        let models: [Model]
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("Ollama")
        }

        guard let url = URL(string: "\(baseURL)/api/embeddings") else {
            throw EmbeddingError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": selectedModel,
            "prompt": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.generationFailed("HTTP error")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedding = json["embedding"] as? [Double] else {
            throw EmbeddingError.generationFailed("Invalid response format")
        }

        return embedding.map { Float($0) }
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        // Ollama doesn't have native batch support, so process sequentially
        var embeddings: [[Float]] = []

        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            embeddings.append(embedding)
        }

        return embeddings
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "ollamaEmbeddingModel")
    }

    var models: [String] { availableModels }
}
