//
//  OllamaClient.swift
//  MBox Explorer
//
//  Ollama HTTP API client for LLM and embeddings
//  Author: Jordan Koch
//  Date: 2025-01-17
//

import Foundation

/// Ollama API client for chat completion and embeddings
class OllamaClient: ObservableObject {
    @Published var isConnected = false
    @Published var availableModels: [String] = []
    @Published var currentLLMModel: String
    @Published var currentEmbeddingModel: String

    private var serverURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: - Initialization

    init() {
        // Load settings from UserDefaults
        let urlString = UserDefaults.standard.string(forKey: "ollamaServerURL") ?? "http://localhost:11434"
        self.serverURL = URL(string: urlString)!
        self.currentLLMModel = UserDefaults.standard.string(forKey: "ollamaLLMModel") ?? "llama2"
        self.currentEmbeddingModel = UserDefaults.standard.string(forKey: "ollamaEmbeddingModel") ?? "nomic-embed-text"

        // Configure URLSession with timeout (increased for RAG queries with large context)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180  // 3 minutes for RAG processing
        config.timeoutIntervalForResource = 600 // 10 minutes for large operations
        self.session = URLSession(configuration: config)

        // Check connection on init
        Task {
            await checkConnection()
        }
    }

    // MARK: - Connection Management

    /// Check if Ollama server is running
    func checkConnection() async {
        do {
            var request = URLRequest(url: serverURL)
            request.httpMethod = "GET"

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                await MainActor.run {
                    self.isConnected = httpResponse.statusCode == 200
                }

                if isConnected {
                    await loadAvailableModels()
                }
            }
        } catch {
            print("Ollama connection error: \(error.localizedDescription)")
            await MainActor.run {
                self.isConnected = false
            }
        }
    }

    /// Load available models from Ollama
    func loadAvailableModels() async {
        do {
            let url = serverURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let (data, _) = try await session.data(for: request)

            struct ModelsResponse: Codable {
                struct Model: Codable {
                    let name: String
                }
                let models: [Model]
            }

            let response = try decoder.decode(ModelsResponse.self, from: data)

            await MainActor.run {
                self.availableModels = response.models.map { $0.name }
            }
        } catch {
            print("Error loading models: \(error.localizedDescription)")
        }
    }

    // MARK: - Chat Completion

    /// Generate chat completion using Ollama
    func generate(prompt: String, model: String? = nil, system: String? = nil, temperature: Float? = nil) async throws -> String {
        let useModel = model ?? currentLLMModel
        let url = serverURL.appendingPathComponent("api/generate")

        var requestBody: [String: Any] = [
            "model": useModel,
            "prompt": prompt,
            "stream": false
        ]

        if let system = system {
            requestBody["system"] = system
        }

        if let temperature = temperature {
            requestBody["options"] = ["temperature": temperature]
        } else {
            let savedTemp = UserDefaults.standard.float(forKey: "ollamaTemperature")
            if savedTemp > 0 {
                requestBody["options"] = ["temperature": savedTemp]
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed("HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct GenerateResponse: Codable {
            let response: String
            let done: Bool
        }

        let generateResponse = try decoder.decode(GenerateResponse.self, from: data)
        return generateResponse.response
    }

    /// Chat with conversation history
    func chat(messages: [ChatMessage], model: String? = nil, temperature: Float? = nil) async throws -> String {
        let useModel = model ?? currentLLMModel
        let url = serverURL.appendingPathComponent("api/chat")

        var requestBody: [String: Any] = [
            "model": useModel,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false
        ]

        if let temperature = temperature {
            requestBody["options"] = ["temperature": temperature]
        } else {
            let savedTemp = UserDefaults.standard.float(forKey: "ollamaTemperature")
            if savedTemp > 0 {
                requestBody["options"] = ["temperature": savedTemp]
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed("HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct ChatResponse: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
            let done: Bool
        }

        let chatResponse = try decoder.decode(ChatResponse.self, from: data)
        return chatResponse.message.content
    }

    // MARK: - Embeddings

    /// Generate embeddings for text
    func embeddings(text: String, model: String? = nil) async throws -> [Float] {
        let useModel = model ?? currentEmbeddingModel
        let url = serverURL.appendingPathComponent("api/embeddings")

        let requestBody: [String: Any] = [
            "model": useModel,
            "prompt": text
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed("HTTP status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        struct EmbeddingsResponse: Codable {
            let embedding: [Float]
        }

        let embeddingsResponse = try decoder.decode(EmbeddingsResponse.self, from: data)
        return embeddingsResponse.embedding
    }

    /// Generate embeddings for multiple texts (batch processing)
    func batchEmbeddings(texts: [String], model: String? = nil, progressCallback: @escaping (Int, Int) -> Void) async throws -> [[Float]] {
        var embeddings: [[Float]] = []

        for (index, text) in texts.enumerated() {
            do {
                let embedding = try await self.embeddings(text: text, model: model)
                embeddings.append(embedding)
                progressCallback(index + 1, texts.count)
            } catch {
                print("Error generating embedding for text \(index): \(error)")
                // Use zero vector as fallback
                let dimensions = 384 // nomic-embed-text dimensions
                embeddings.append(Array(repeating: 0.0, count: dimensions))
            }
        }

        return embeddings
    }

    // MARK: - Model Management

    /// Pull a model from Ollama library
    func pullModel(name: String, progressCallback: @escaping (String) -> Void) async throws {
        let url = serverURL.appendingPathComponent("api/pull")

        let requestBody: [String: Any] = [
            "name": name,
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed("Failed to pull model")
        }

        // Stream progress updates
        for try await line in bytes.lines {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                progressCallback(status)
            }
        }

        await loadAvailableModels()
    }

    // MARK: - Configuration

    /// Update server URL
    func updateServerURL(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }

        await MainActor.run {
            self.serverURL = url
        }

        UserDefaults.standard.set(urlString, forKey: "ollamaServerURL")
        await checkConnection()
    }

    /// Update LLM model
    func updateLLMModel(_ model: String) {
        currentLLMModel = model
        UserDefaults.standard.set(model, forKey: "ollamaLLMModel")
    }

    /// Update embedding model
    func updateEmbeddingModel(_ model: String) {
        currentEmbeddingModel = model
        UserDefaults.standard.set(model, forKey: "ollamaEmbeddingModel")
    }

    /// Update temperature
    func updateTemperature(_ temperature: Float) {
        UserDefaults.standard.set(temperature, forKey: "ollamaTemperature")
    }
}

// MARK: - Supporting Types

struct ChatMessage: Codable {
    let role: String // "system", "user", or "assistant"
    let content: String
}

enum OllamaError: LocalizedError {
    case notConnected
    case requestFailed(String)
    case invalidResponse
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Ollama server not running. Start Ollama with: ollama serve"
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from Ollama server"
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Pull it with: ollama pull \(model)"
        }
    }
}
