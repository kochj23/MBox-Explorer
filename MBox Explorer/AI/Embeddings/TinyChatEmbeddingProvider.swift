//
//  TinyChatEmbeddingProvider.swift
//  MBox Explorer
//
//  TinyChat-based embedding provider using OpenAI-compatible API
//  Author: Jordan Koch
//  Date: 2026-01-30
//
//  THIRD-PARTY INTEGRATION:
//  TinyChat by Jason Cox (https://github.com/jasonacox/tinychat)
//  A minimal, fast chatbot interface with OpenAI-compatible API
//

import Foundation

/// TinyChat embedding provider using OpenAI-compatible embeddings API
/// TinyChat by Jason Cox: https://github.com/jasonacox/tinychat
class TinyChatEmbeddingProvider: EmbeddingProvider, ObservableObject {
    let name = "TinyChat"

    @Published var isAvailable = false
    @Published var selectedModel = "text-embedding-ada-002"

    var embeddingDimension: Int {
        // OpenAI-compatible dimensions
        switch selectedModel {
        case "text-embedding-ada-002": return 1536
        case "text-embedding-3-small": return 1536
        case "text-embedding-3-large": return 3072
        default: return 1536
        }
    }

    private var baseURL: String
    private var availableModels: [String] = ["text-embedding-ada-002", "text-embedding-3-small"]

    init(baseURL: String = "http://localhost:8000") {
        self.baseURL = baseURL

        // Load saved settings
        if let savedURL = UserDefaults.standard.string(forKey: "TinyChatEmbedding_URL") {
            self.baseURL = savedURL
        }
        if let savedModel = UserDefaults.standard.string(forKey: "TinyChatEmbedding_Model") {
            self.selectedModel = savedModel
        }
    }

    func checkAvailability() async {
        do {
            // Check if TinyChat is running by hitting the root endpoint
            guard let url = URL(string: "\(baseURL)/") else {
                await MainActor.run { isAvailable = false }
                return
            }

            let (_, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await MainActor.run { isAvailable = false }
                return
            }

            // Try to get config to check available models
            if let configURL = URL(string: "\(baseURL)/api/config") {
                do {
                    let (configData, configResponse) = try await URLSession.shared.data(from: configURL)
                    if let configHttp = configResponse as? HTTPURLResponse,
                       configHttp.statusCode == 200,
                       let json = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
                       let models = json["available_models"] as? [String] {
                        await MainActor.run {
                            // Filter for embedding-capable models
                            self.availableModels = models.filter { $0.contains("embed") }
                            if self.availableModels.isEmpty {
                                self.availableModels = ["text-embedding-ada-002"]
                            }
                        }
                    }
                } catch {
                    // Config endpoint might not exist, use defaults
                }
            }

            await MainActor.run { isAvailable = true }
        } catch {
            await MainActor.run { isAvailable = false }
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("TinyChat")
        }

        // TinyChat uses OpenAI-compatible /v1/embeddings endpoint
        guard let url = URL(string: "\(baseURL)/v1/embeddings") else {
            throw EmbeddingError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "input": text,
            "model": selectedModel
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.networkError("Invalid response")
        }

        // Check for errors
        if httpResponse.statusCode != 200 {
            // TinyChat might not support embeddings directly - fallback to proxied embeddings
            if httpResponse.statusCode == 404 {
                throw EmbeddingError.generationFailed("TinyChat embeddings endpoint not available. TinyChat proxies to backend LLM - ensure your backend (Ollama/OpenAI) supports embeddings.")
            }
            throw EmbeddingError.generationFailed("HTTP error: \(httpResponse.statusCode)")
        }

        // Parse OpenAI-compatible response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let embedding = first["embedding"] as? [Double] else {
            throw EmbeddingError.generationFailed("Invalid response format")
        }

        return embedding.map { Float($0) }
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("TinyChat")
        }

        // Try batch request first (OpenAI-compatible)
        guard let url = URL(string: "\(baseURL)/v1/embeddings") else {
            throw EmbeddingError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // 5 minutes for batch

        let body: [String: Any] = [
            "input": texts,
            "model": selectedModel
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Fallback to sequential processing
                return try await generateBatchSequentially(texts)
            }

            // Parse batch response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json["data"] as? [[String: Any]] else {
                return try await generateBatchSequentially(texts)
            }

            var embeddings: [[Float]] = []
            for item in dataArray {
                if let embedding = item["embedding"] as? [Double] {
                    embeddings.append(embedding.map { Float($0) })
                }
            }

            return embeddings
        } catch {
            // Fallback to sequential
            return try await generateBatchSequentially(texts)
        }
    }

    private func generateBatchSequentially(_ texts: [String]) async throws -> [[Float]] {
        var embeddings: [[Float]] = []
        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            embeddings.append(embedding)
        }
        return embeddings
    }

    func setBaseURL(_ url: String) {
        baseURL = url
        UserDefaults.standard.set(url, forKey: "TinyChatEmbedding_URL")
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "TinyChatEmbedding_Model")
    }

    var models: [String] { availableModels }
    var serverURL: String { baseURL }
}
