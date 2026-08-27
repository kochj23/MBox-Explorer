//
//  LMStudioEmbeddingProvider.swift
//  MBox Explorer
//
//  LM Studio-based embedding provider using OpenAI-compatible API
//  Author: Jordan Koch
//  Date: 2026-08-26
//

import Foundation

class LMStudioEmbeddingProvider: EmbeddingProvider, ObservableObject {
    let name = "LM Studio"

    @Published var isAvailable = false
    @Published var selectedModel: String = ""
    @Published var availableModels: [String] = []

    var embeddingDimension: Int {
        // LM Studio supports various embedding models with different dimensions
        switch selectedModel.lowercased() {
        case "text-embedding-ada-002": return 1536
        case "text-embedding-3-small": return 1536
        case "text-embedding-3-large": return 3072
        case "nomic-embed-text": return 768
        case "all-minilm": return 384
        case "bge-large": return 1024
        default: return 1536
        }
    }

    private let defaultURL = "http://localhost:1234"
    private var baseURL: String

    init(baseURL: String = "http://localhost:1234") {
        self.baseURL = baseURL
        loadSettings()
    }

    private func loadSettings() {
        if let savedURL = UserDefaults.standard.string(forKey: "LMStudioEmbedding_URL") {
            self.baseURL = savedURL
        }
        if let savedModel = UserDefaults.standard.string(forKey: "LMStudioEmbedding_Model") {
            self.selectedModel = savedModel
        }
    }

    func checkAvailability() async {
        let candidates = [baseURL, defaultURL]

        for url in candidates {
            do {
                guard let modelsURL = URL(string: "\(url)/v1/models") else { continue }

                let (_, response) = try await URLSession.shared.data(from: modelsURL)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                await MainActor.run {
                    if self.baseURL != url {
                        self.baseURL = url
                        UserDefaults.standard.set(url, forKey: "LMStudioEmbedding_URL")
                    }
                }

                await fetchAvailableModels()
                await MainActor.run { isAvailable = true }
                return
            } catch {
                continue
            }
        }

        await MainActor.run { isAvailable = false }
    }

    private func fetchAvailableModels() async {
        guard let url = URL(string: "\(baseURL)/v1/models") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]] {
                let models = dataArray.compactMap { $0["id"] as? String }

                await MainActor.run {
                    self.availableModels = models
                    if !models.contains(selectedModel) && !models.isEmpty {
                        self.selectedModel = models[0]
                        UserDefaults.standard.set(models[0], forKey: "LMStudioEmbedding_Model")
                    }
                }
            }
        } catch {
            await fetchOllamaStyleModels()
        }
    }

    private func fetchOllamaStyleModels() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }

                await MainActor.run {
                    self.availableModels = modelNames
                    if !modelNames.contains(selectedModel) && !modelNames.isEmpty {
                        self.selectedModel = modelNames[0]
                        UserDefaults.standard.set(modelNames[0], forKey: "LMStudioEmbedding_Model")
                    }
                }
            }
        } catch {
            // Return empty - no models found
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable, !selectedModel.isEmpty else {
            throw EmbeddingError.providerUnavailable("LM Studio")
        }

        if let embedding = try? await generateWithOpenAICompatible(text: text) {
            return embedding
        }

        return try await generateWithOllamaStyle(text: text)
    }

    private func generateWithOpenAICompatible(text: String) async throws -> [Float]? {
        guard let url = URL(string: "\(baseURL)/v1/embeddings") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "input": text,
            "model": selectedModel
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]],
               let first = dataArray.first,
               let embedding = first["embedding"] as? [Double] {
                return embedding.map { Float($0) }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func generateWithOllamaStyle(text: String) async throws -> [Float] {
        guard let url = URL(string: "\(baseURL)/api/embeddings") else {
            throw EmbeddingError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

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
        var embeddings: [[Float]] = []

        for text in texts {
            let embedding = try await generateEmbedding(for: text)
            embeddings.append(embedding)
        }

        return embeddings
    }

    func setBaseURL(_ url: String) {
        baseURL = url
        UserDefaults.standard.set(url, forKey: "LMStudioEmbedding_URL")
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "LMStudioEmbedding_Model")
    }
}
