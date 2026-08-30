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
        // nomic-embed-text: 768, all-minilm: 384
        switch selectedModel {
        case "nomic-embed-text": return 768
        case "all-minilm": return 384
        case "mxbai-embed-large": return 1024
        default: return 768
        }
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
        do {
            // Check if Ollama is running
            guard let url = URL(string: "\(baseURL)/api/tags") else {
                await MainActor.run { isAvailable = false }
                return
            }

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { isAvailable = false }
                return
            }

            // Parse available models using JSONDecoder for consistency with OllamaClient
            let decoder = JSONDecoder()
            if let modelsResponse = try? decoder.decode(OllamaModelsResponse.self, from: data) {
                let modelNames = modelsResponse.models.map { $0.name }

                // Check for embedding models
                let embeddingModels = modelNames.filter {
                    $0.contains("embed") || $0.contains("nomic") || $0.contains("minilm") || $0.contains("mxbai") || $0.contains("bge") || $0.contains("e5-") || $0.contains("gte-")
                }

                await MainActor.run {
                    availableModels = embeddingModels
                    isAvailable = !embeddingModels.isEmpty

                    // Auto-select best available model
                    if !embeddingModels.contains(selectedModel) && !embeddingModels.isEmpty {
                        selectedModel = embeddingModels.first!
                    }
                }
            } else {
                await MainActor.run { isAvailable = false }
            }
        } catch {
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
