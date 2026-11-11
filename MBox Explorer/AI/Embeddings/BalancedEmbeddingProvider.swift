//
//  BalancedEmbeddingProvider.swift
//  MBox Explorer
//
//  Bulk semantic indexing spread across every local Ollama model (round-robin).
//
//  Embeddings are not chat AI, so this stays app-owned (NovaAIKit covers chat/summaries only). The Ollama URL comes
//  from the AI settings (AppAI). Resumability is unaffected: this only changes which model serves each embedding;
//  `VectorDatabase.pendingEmails(...)` still drives the resumable work set.
//
//  Degrades gracefully: with no local model, `isAvailable` is false and `EmbeddingManager` falls back (indexing
//  continues without vectors).
//

import Foundation
import NovaAIKit

/// Pure round-robin over a model pool (network-free, unit-tested).
struct EmbeddingRoundRobin {
    private var index = 0

    /// The next model in `pool`, wrapping around; nil for an empty pool.
    mutating func next(from pool: [String]) -> String? {
        guard !pool.isEmpty else { return nil }
        defer { index += 1 }
        return pool[index % pool.count]
    }
}

final class BalancedEmbeddingProvider: EmbeddingProvider {
    let name = "Balanced (All Local Models)"

    private(set) var isAvailable = false
    /// Ollama's default embedding models are 768-d (nomic-embed-text); corrected after the first embedding.
    private(set) var embeddingDimension: Int = 768

    private var baseURL = NovaAIBackend.ollama.defaultURL
    private var pool: [String] = []
    private var roundRobin = EmbeddingRoundRobin()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkAvailability() async {
        let (url, engine) = await MainActor.run { (AppAI.shared.settings.url(for: .ollama), AppAI.shared.engine) }
        baseURL = url
        pool = await engine.listModels(.ollama)
        isAvailable = !pool.isEmpty
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable, let model = roundRobin.next(from: pool) else {
            throw EmbeddingError.providerUnavailable(name)
        }
        guard let url = URL(string: "\(baseURL)/api/embeddings") else {
            throw EmbeddingError.networkError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": text])
        request.timeoutInterval = 120
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw EmbeddingError.generationFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0) from \(model)")
            }
            struct EmbeddingResponse: Decodable { let embedding: [Float] }
            let embedding = try JSONDecoder().decode(EmbeddingResponse.self, from: data).embedding
            if !embedding.isEmpty { embeddingDimension = embedding.count }
            return embedding
        } catch let error as EmbeddingError {
            throw error
        } catch {
            throw EmbeddingError.generationFailed(error.localizedDescription)
        }
    }

    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            results.append(try await generateEmbedding(for: text))
        }
        return results
    }
}
