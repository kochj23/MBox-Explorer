//
//  ModelRegistry.swift
//  MBox Explorer (balancer core — copied verbatim from AIStudio)
//
//  Created by Jordan Koch on 2026-02-19.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//
//  Discovers every model available on the machine and normalizes them into a
//  flat `[DiscoveredModel]` pool that the load balancer can spread work across —
//  the single-user version of how Nova's gateway balances load.
//
//  The parsing/composition logic is factored into pure, network-free functions so
//  it is fully unit-testable; the thin discovery wrappers do the actual I/O and
//  never throw to the caller (an unreachable backend simply contributes zero
//  models).
//

import Foundation

// MARK: - Discovered model

/// A single model discovered on the machine, normalized across backends.
struct DiscoveredModel: Identifiable, Hashable, Sendable {
    /// Stable, pool-unique identifier (`"<backend>|<model>"`).
    let id: String
    /// The raw model name/id passed to the backend API (e.g. `mistral:latest`).
    let modelName: String
    /// Human-friendly label for pickers.
    let displayName: String
    /// Which backend serves this model.
    let backend: LLMBackendType
    /// Base or chat-completions endpoint the model is reachable at (informational
    /// for MLX, which runs in-process).
    let endpoint: String

    init(modelName: String, displayName: String? = nil, backend: LLMBackendType, endpoint: String) {
        self.id = "\(backend.rawValue)|\(modelName)"
        self.modelName = modelName
        self.displayName = displayName ?? modelName
        self.backend = backend
        self.endpoint = endpoint
    }
}

// MARK: - Model registry

/// Discovers and normalizes the models available on this machine.
///
/// All the JSON/structured-input → `[DiscoveredModel]` mapping lives in pure,
/// network-free functions (`parseOllamaTags`, `parseMLXModels`, `frontierModels`,
/// `assemblePool`) so they can be unit-tested without hitting the network. The
/// `discover*` wrappers add the thin I/O layer and swallow every error.
enum ModelRegistry {
    /// Default local Ollama base URL.
    static let ollamaBaseURL = "http://localhost:11434"
    /// Default Nova Gateway base URL (OpenAI-compatible, inherits Nova's routing).
    static let novaGatewayDefaultURL = "http://127.0.0.1:18792"

    // MARK: Pure parsing (network-free, unit-tested)

    /// Map an Ollama `/api/tags` response body to `[DiscoveredModel]`.
    /// Returns `[]` for empty/garbage input — never throws.
    static func parseOllamaTags(_ data: Data, baseURL: String = ollamaBaseURL) -> [DiscoveredModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            return []
        }
        let endpoint = "\(baseURL)/api/chat"
        return models.compactMap { entry -> DiscoveredModel? in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            return DiscoveredModel(modelName: name, backend: .ollama, endpoint: endpoint)
        }
    }

    /// Map a set of Hugging Face hub cache directory names to locally-installed
    /// MLX models. A hub directory is named `models--<org>--<repo>`; this converts
    /// it back to the `<org>/<repo>` model id and keeps only MLX models. Pure and
    /// network-free; the discovery wrapper feeds it the real directory listing.
    static func parseMLXModels(hubDirectoryNames names: [String]) -> [DiscoveredModel] {
        names.compactMap { raw -> DiscoveredModel? in
            guard raw.hasPrefix("models--") else { return nil }
            let repo = raw.dropFirst("models--".count).replacingOccurrences(of: "--", with: "/")
            guard !repo.isEmpty, repo.lowercased().contains("mlx") else { return nil }
            let short = repo.split(separator: "/").last.map(String.init) ?? repo
            // MLX runs in-process — no HTTP endpoint.
            return DiscoveredModel(modelName: repo, displayName: short, backend: .mlx, endpoint: "")
        }
    }

    /// Map OpenRouter model ids (from `OpenRouterProvider.parseModels`) into the
    /// registry as frontier models. Pure and network-free.
    static func frontierModels(from openRouterModelIds: [String]) -> [DiscoveredModel] {
        openRouterModelIds.compactMap { id -> DiscoveredModel? in
            guard !id.isEmpty else { return nil }
            return DiscoveredModel(modelName: id, backend: .openRouter, endpoint: OpenRouterProvider.chatCompletionsURL)
        }
    }

    /// The single Nova Gateway "model" — the app routes to Nova and inherits her
    /// own internal routing, so it presents as one balancer entry.
    static func novaGatewayModel(url: String = novaGatewayDefaultURL) -> DiscoveredModel {
        DiscoveredModel(
            modelName: "nova",
            displayName: "Nova Gateway",
            backend: .novaGateway,
            endpoint: "\(url)/v1/chat/completions"
        )
    }

    /// Compose the enabled balancer pool from per-source model lists and the three
    /// toggles. Pure and network-free — this is the toggle-composition contract the
    /// load balancer runs over.
    static func assemblePool(
        ollama: [DiscoveredModel] = [],
        mlx: [DiscoveredModel] = [],
        frontier: [DiscoveredModel] = [],
        novaGateway: DiscoveredModel? = nil,
        useAllLocalModels: Bool,
        enableAllFrontierModels: Bool,
        useNovaGateway: Bool
    ) -> [DiscoveredModel] {
        var pool: [DiscoveredModel] = []
        if useAllLocalModels {
            pool.append(contentsOf: ollama)
            pool.append(contentsOf: mlx)
        }
        if enableAllFrontierModels {
            pool.append(contentsOf: frontier)
        }
        if useNovaGateway, let nova = novaGateway {
            pool.append(nova)
        }
        // De-duplicate by id while preserving first-seen order.
        var seen = Set<String>()
        return pool.filter { seen.insert($0.id).inserted }
    }

    // MARK: Discovery I/O (thin, resilient — never throws)

    /// Discover local Ollama models. Any failure → `[]`.
    static func discoverOllama(baseURL: String = ollamaBaseURL, session: URLSession = .shared) async -> [DiscoveredModel] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return parseOllamaTags(data, baseURL: baseURL)
        } catch {
            return []
        }
    }

    /// Discover locally-installed MLX models from the Hugging Face hub cache. Any
    /// failure (no cache dir, unreadable) → `[]`.
    static func discoverMLX(hubPath: String? = nil) -> [DiscoveredModel] {
        let path = hubPath ?? (NSHomeDirectory() as NSString).appendingPathComponent(".cache/huggingface/hub")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return parseMLXModels(hubDirectoryNames: entries)
    }
}

// MARK: - Load balancer

/// Balancer selection policy.
enum BalancerPolicy: String, CaseIterable, Sendable {
    /// Cycle through the pool in order, wrapping around.
    case roundRobin
    /// Prefer the model with the fewest in-flight requests.
    case leastBusy
}

/// Pure, network-free load balancer over a `[DiscoveredModel]` pool. Given the
/// pool, a per-model health map and a policy, it returns the next model to use —
/// no network, so it is fully unit-testable. In-flight counts (for `.leastBusy`)
/// are tracked internally via `checkOut`/`checkIn`.
///
/// Composes with `FailoverPlanner`: the manager gates the pool to healthy backends
/// first (skip unhealthy, fall through), then the balancer spreads load across
/// what remains. A model is eligible unless the health map marks it `false`.
final class LoadBalancer {
    /// In-flight request count per model id.
    private(set) var inFlight: [String: Int] = [:]
    /// Rolling cursor for round-robin.
    private var cursor: Int = 0

    init() {}

    /// The healthy subset of `pool`, preserving pool order. A model is healthy
    /// unless the map explicitly marks it `false`.
    func healthy(in pool: [DiscoveredModel], health: [String: Bool]) -> [DiscoveredModel] {
        pool.filter { health[$0.id] != false }
    }

    /// Select the next model from the healthy subset of `pool` under `policy`.
    /// Returns `nil` when nothing is healthy (the manager then falls back cleanly).
    func next(pool: [DiscoveredModel], health: [String: Bool] = [:], policy: BalancerPolicy) -> DiscoveredModel? {
        let candidates = healthy(in: pool, health: health)
        guard !candidates.isEmpty else { return nil }

        switch policy {
        case .roundRobin:
            let choice = candidates[cursor % candidates.count]
            cursor += 1
            return choice
        case .leastBusy:
            // Lowest in-flight count wins; ties broken by pool order (first).
            return candidates.min { lhs, rhs in
                (inFlight[lhs.id] ?? 0) < (inFlight[rhs.id] ?? 0)
            }
        }
    }

    /// Mark a request as started against `modelId`.
    func checkOut(_ modelId: String) {
        inFlight[modelId, default: 0] += 1
    }

    /// Mark a request against `modelId` as finished.
    func checkIn(_ modelId: String) {
        let current = inFlight[modelId] ?? 0
        inFlight[modelId] = max(0, current - 1)
    }

    /// Reset all balancer state (cursor + in-flight counts).
    func reset() {
        inFlight.removeAll()
        cursor = 0
    }
}
