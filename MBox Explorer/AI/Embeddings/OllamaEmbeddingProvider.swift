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

    private let baseURL: String
    private var availableModels: [String] = []

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = baseURL

        // Load saved model preference
        if let savedModel = UserDefaults.standard.string(forKey: "OllamaEmbedding_Model") {
            self.selectedModel = savedModel
        }
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

            // Parse available models
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }

                // Check for embedding models
                let embeddingModels = modelNames.filter {
                    $0.contains("embed") || $0.contains("nomic") || $0.contains("minilm") || $0.contains("mxbai")
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
        UserDefaults.standard.set(model, forKey: "OllamaEmbedding_Model")
    }

    var models: [String] { availableModels }
}
