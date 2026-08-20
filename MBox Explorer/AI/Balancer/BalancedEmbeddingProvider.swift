//
//  BalancedEmbeddingProvider.swift
//  MBox Explorer
//
//  Bulk semantic indexing spread across ALL local models via the load balancer.
//
//  Instead of pinning indexing to a single embedding model, this provider routes
//  each embedding request's model selection through `BalancedLLMManager`'s pure
//  `LoadBalancer` (round-robin / least-busy) over the discovered local Ollama
//  pool. Bulk indexing therefore fans out across every local model.
//
//  Resumability is unaffected: this only changes *which model* serves each
//  embedding; `VectorDatabase.pendingEmails(...)` still drives the resumable work
//  set, so a cancelled/partial run picks up exactly where it left off.
//
//  Degrades gracefully: when no local model is discoverable, `isAvailable` is
//  false and `EmbeddingManager` falls back (indexing continues without vectors).
//

import Foundation

final class BalancedEmbeddingProvider: EmbeddingProvider {
    let name = "Balanced (All Local Models)"

    private(set) var isAvailable = false
    /// Ollama's default embedding models are 768-d (nomic-embed-text); reported as
    /// a stable default and corrected after the first successful embedding.
    private(set) var embeddingDimension: Int = 768

    private let manager: BalancedLLMManager
    /// The local model pool the balancer spreads embedding work across.
    private var pool: [DiscoveredModel] = []

    init(manager: BalancedLLMManager = .shared) {
        self.manager = manager
    }

    func checkAvailability() async {
        let discovered = await manager.localEmbeddingPool()
        let enabled = await MainActor.run { manager.useAllLocalModels }
        self.pool = discovered
        self.isAvailable = enabled && !discovered.isEmpty
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        guard isAvailable, !pool.isEmpty else {
            throw EmbeddingError.providerUnavailable(name)
        }
        // Route the model selection through the balancer.
        let choice = await MainActor.run { manager.nextEmbeddingModel(from: pool) }
        guard let model = choice else { throw EmbeddingError.providerUnavailable(name) }

        manager.balancer.checkOut(model.id)
        defer { manager.balancer.checkIn(model.id) }
        do {
            let embedding = try await manager.embed(text: text, model: model.modelName)
            if !embedding.isEmpty { embeddingDimension = embedding.count }
            return embedding
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
