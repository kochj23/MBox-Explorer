//
//  OpenAIEmbeddingProvider.swift
//  MBox Explorer
//
//  OpenAI-based embedding provider (cloud)
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// OpenAI embedding provider using text-embedding-3-small/large
class OpenAIEmbeddingProvider: EmbeddingProvider, ObservableObject {
    let name = "OpenAI"

    @Published var isAvailable = false
    @Published var selectedModel = "text-embedding-3-small"

    var embeddingDimension: Int {
        switch selectedModel {
        case "text-embedding-3-small": return 1536
        case "text-embedding-3-large": return 3072
        case "text-embedding-ada-002": return 1536
        default: return 1536
        }
    }

    private var apiKey: String?
    private let baseURL = "https://api.openai.com/v1/embeddings"

    // Available models
    static let availableModels = [
        "text-embedding-3-small",  // Cheapest, good quality
        "text-embedding-3-large",  // Highest quality
        "text-embedding-ada-002"   // Legacy
    ]

    // Pricing per 1M tokens (as of 2024)
    static let pricing: [String: Double] = [
        "text-embedding-3-small": 0.02,
        "text-embedding-3-large": 0.13,
        "text-embedding-ada-002": 0.10
    ]

    init() {
        // Load API key from AIBackendManager
        loadAPIKey()

        // Load saved model preference
        if let savedModel = UserDefaults.standard.string(forKey: "OpenAIEmbedding_Model") {
            self.selectedModel = savedModel
        }
    }

    private func loadAPIKey() {
        // Try to get from AIBackendManager's cloud credentials
        if let data = try? Data(contentsOf: getCredentialsURL()),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let openai = json["openai"] as? [String: Any],
           let key = openai["apiKey"] as? String {
            apiKey = key
        }
    }

    private func getCredentialsURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MBoxExplorer/cloud_credentials.json")
    }

    func checkAvailability() async {
        loadAPIKey()

        guard let key = apiKey, !key.isEmpty else {
            await MainActor.run { isAvailable = false }
            return
        }

        // Verify API key with a minimal request
        do {
            _ = try await generateEmbedding(for: "test")
            await MainActor.run { isAvailable = true }
        } catch {
            await MainActor.run { isAvailable = false }
        }
    }

    func setAPIKey(_ key: String) {
        apiKey = key
        Task {
            await checkAvailability()
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard let key = apiKey, !key.isEmpty else {
            throw EmbeddingError.apiKeyMissing
        }

        guard let url = URL(string: baseURL) else {
            throw EmbeddingError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": selectedModel,
            "input": text
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmbeddingError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw EmbeddingError.apiKeyMissing
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw EmbeddingError.generationFailed(message)
            }
            throw EmbeddingError.generationFailed("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]],
              let first = dataArray.first,
              let embedding = first["embedding"] as? [Double] else {
            throw EmbeddingError.generationFailed("Invalid response format")
        }

        return embedding.map { Float($0) }
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        guard let key = apiKey, !key.isEmpty else {
            throw EmbeddingError.apiKeyMissing
        }

        // OpenAI supports batch embeddings natively
        guard let url = URL(string: baseURL) else {
            throw EmbeddingError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": selectedModel,
            "input": texts
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.generationFailed("HTTP error")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            throw EmbeddingError.generationFailed("Invalid response format")
        }

        // Sort by index to maintain order
        let sorted = dataArray.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }

        return sorted.compactMap { item -> [Float]? in
            guard let embedding = item["embedding"] as? [Double] else { return nil }
            return embedding.map { Float($0) }
        }
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "OpenAIEmbedding_Model")
    }

    /// Estimate cost for embedding texts
    func estimateCost(texts: [String]) -> Double {
        let totalChars = texts.reduce(0) { $0 + $1.count }
        let estimatedTokens = Double(totalChars) / 4.0 // Rough estimate
        let pricePerMillion = Self.pricing[selectedModel] ?? 0.02
        return (estimatedTokens / 1_000_000) * pricePerMillion
    }
}
