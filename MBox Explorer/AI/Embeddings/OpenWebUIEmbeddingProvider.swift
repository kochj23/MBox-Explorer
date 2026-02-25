//
//  OpenWebUIEmbeddingProvider.swift
//  MBox Explorer
//
//  OpenWebUI-based embedding provider using OpenAI-compatible API
//  Author: Jordan Koch
//  Date: 2026-01-30
//
//  THIRD-PARTY INTEGRATION:
//  OpenWebUI Community Project (https://github.com/open-webui/open-webui)
//  Self-hosted AI platform with OpenAI-compatible API
//

import Foundation
import Security

/// OpenWebUI embedding provider using OpenAI-compatible embeddings API
/// OpenWebUI: https://github.com/open-webui/open-webui
class OpenWebUIEmbeddingProvider: EmbeddingProvider, ObservableObject {
    let name = "OpenWebUI"

    @Published var isAvailable = false
    @Published var selectedModel = "text-embedding-ada-002"
    @Published var apiKey: String = ""

    var embeddingDimension: Int {
        // OpenAI-compatible dimensions
        switch selectedModel {
        case "text-embedding-ada-002": return 1536
        case "text-embedding-3-small": return 1536
        case "text-embedding-3-large": return 3072
        case "nomic-embed-text": return 768
        case "all-minilm": return 384
        default: return 1536
        }
    }

    private var baseURL: String
    private var availableModels: [String] = ["text-embedding-ada-002", "nomic-embed-text"]

    // MARK: - Keychain Helpers

    private static let keychainService = "com.jordankoch.MBoxExplorer"
    private static let keychainAccount = "OpenWebUIEmbedding_APIKey"

    private func saveAPIKeyToKeychain(_ key: String) {
        guard let data = key.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrService as String: Self.keychainService
        ]
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        // Add new item
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteAPIKeyFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrService as String: Self.keychainService
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Migrate API key from UserDefaults to Keychain (one-time migration)
    private func migrateAPIKeyToKeychain() {
        if let legacyKey = UserDefaults.standard.string(forKey: "OpenWebUIEmbedding_APIKey"), !legacyKey.isEmpty {
            saveAPIKeyToKeychain(legacyKey)
            UserDefaults.standard.removeObject(forKey: "OpenWebUIEmbedding_APIKey")
            NSLog("[OpenWebUI] Migrated API key from UserDefaults to Keychain")
        }
    }

    init(baseURL: String = "http://localhost:8080") {
        self.baseURL = baseURL

        // Load saved settings
        if let savedURL = UserDefaults.standard.string(forKey: "OpenWebUIEmbedding_URL") {
            self.baseURL = savedURL
        }
        if let savedModel = UserDefaults.standard.string(forKey: "OpenWebUIEmbedding_Model") {
            self.selectedModel = savedModel
        }

        // Migrate API key from UserDefaults to Keychain if needed
        migrateAPIKeyToKeychain()

        // Load API key from Keychain
        if let savedKey = loadAPIKeyFromKeychain() {
            self.apiKey = savedKey
        }
    }

    func checkAvailability() async {
        // Try multiple common ports for OpenWebUI
        let urlsToTry = [
            baseURL,
            "http://localhost:8080",
            "http://localhost:3000"
        ]

        for urlString in urlsToTry {
            do {
                guard let url = URL(string: "\(urlString)/") else { continue }

                var request = URLRequest(url: url)
                request.timeoutInterval = 5

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                // Found a working URL
                await MainActor.run {
                    if self.baseURL != urlString {
                        self.baseURL = urlString
                        UserDefaults.standard.set(urlString, forKey: "OpenWebUIEmbedding_URL")
                    }
                }

                // Try to get available models
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
        // Try OpenWebUI's models endpoint
        let endpoints = [
            "\(baseURL)/api/models",
            "\(baseURL)/ollama/api/tags",  // OpenWebUI's Ollama proxy
            "\(baseURL)/v1/models"  // OpenAI-compatible
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }

            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // OpenAI-style response
                    if let dataArray = json["data"] as? [[String: Any]] {
                        let modelIds = dataArray.compactMap { $0["id"] as? String }
                        let embeddingModels = modelIds.filter {
                            $0.contains("embed") || $0.contains("nomic") || $0.contains("minilm")
                        }
                        if !embeddingModels.isEmpty {
                            await MainActor.run {
                                self.availableModels = embeddingModels
                            }
                            return
                        }
                    }

                    // Ollama-style response
                    if let models = json["models"] as? [[String: Any]] {
                        let modelNames = models.compactMap { $0["name"] as? String }
                        let embeddingModels = modelNames.filter {
                            $0.contains("embed") || $0.contains("nomic") || $0.contains("minilm")
                        }
                        if !embeddingModels.isEmpty {
                            await MainActor.run {
                                self.availableModels = embeddingModels
                            }
                            return
                        }
                    }
                }
            } catch {
                continue
            }
        }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("OpenWebUI")
        }

        // Try OpenWebUI's embeddings endpoint first, then OpenAI-compatible
        let endpoints = [
            "\(baseURL)/api/embeddings",
            "\(baseURL)/v1/embeddings",
            "\(baseURL)/ollama/api/embeddings"
        ]

        var lastError: Error?

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60

            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            // Different body formats for different endpoints
            let body: [String: Any]
            if endpoint.contains("ollama") {
                body = [
                    "model": selectedModel,
                    "prompt": text
                ]
            } else {
                body = [
                    "input": text,
                    "model": selectedModel
                ]
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                // Try to parse response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // OpenAI-style response
                    if let dataArray = json["data"] as? [[String: Any]],
                       let first = dataArray.first,
                       let embedding = first["embedding"] as? [Double] {
                        return embedding.map { Float($0) }
                    }

                    // Ollama-style response
                    if let embedding = json["embedding"] as? [Double] {
                        return embedding.map { Float($0) }
                    }

                    // Alternative format
                    if let embeddings = json["embeddings"] as? [[Double]],
                       let first = embeddings.first {
                        return first.map { Float($0) }
                    }
                }
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? EmbeddingError.generationFailed("All embedding endpoints failed")
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        guard isAvailable else {
            throw EmbeddingError.providerUnavailable("OpenWebUI")
        }

        // Try batch request first
        guard let url = URL(string: "\(baseURL)/v1/embeddings") else {
            return try await generateBatchSequentially(texts)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "input": texts,
            "model": selectedModel
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return try await generateBatchSequentially(texts)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]] {
                var embeddings: [[Float]] = []
                for item in dataArray {
                    if let embedding = item["embedding"] as? [Double] {
                        embeddings.append(embedding.map { Float($0) })
                    }
                }
                if embeddings.count == texts.count {
                    return embeddings
                }
            }
        } catch {
            // Fallback
        }

        return try await generateBatchSequentially(texts)
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
        UserDefaults.standard.set(url, forKey: "OpenWebUIEmbedding_URL")
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: "OpenWebUIEmbedding_Model")
    }

    func setAPIKey(_ key: String) {
        apiKey = key
        if key.isEmpty {
            deleteAPIKeyFromKeychain()
        } else {
            saveAPIKeyToKeychain(key)
        }
    }

    var models: [String] { availableModels }
    var serverURL: String { baseURL }
}
