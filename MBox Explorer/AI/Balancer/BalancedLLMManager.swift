//
//  BalancedLLMManager.swift
//  MBox Explorer
//
//  Multi-model load-balanced LLM dispatch. Mirrors the balanced-dispatch wiring
//  of AIStudio's `LLMBackendManager`, adapted to MBox Explorer:
//
//   • Three persisted toggles compose the balancer pool:
//       - All local models   (every Ollama model + locally-installed MLX models)
//       - All frontier models (OpenRouter, bring-your-own-key)
//       - Nova Gateway        (OPTIONAL OpenAI-compatible backend, 127.0.0.1:18792)
//   • The pure `LoadBalancer` (see ModelRegistry.swift) spreads work across the
//     healthy enabled pool; unhealthy backends are gated out and everything else
//     keeps working.
//
//  Nova is NEVER a hard requirement: with zero Nova the app still balances across
//  local Ollama/MLX and (if a key is set) OpenRouter. A failed Nova health check
//  simply drops the gateway from the pool and the toggle reads "unavailable".
//

import Foundation
import Combine

@MainActor
final class BalancedLLMManager: ObservableObject {
    static let shared = BalancedLLMManager()

    // MARK: - Persisted toggles

    @Published var useAllLocalModels: Bool { didSet { persist(Keys.useAllLocal, useAllLocalModels) } }
    @Published var enableAllFrontierModels: Bool { didSet { persist(Keys.useFrontier, enableAllFrontierModels) } }
    @Published var useNovaGateway: Bool { didSet { persist(Keys.useNova, useNovaGateway) } }
    @Published var novaGatewayURL: String { didSet { UserDefaults.standard.set(novaGatewayURL, forKey: Keys.novaURL) } }
    @Published var selectedOpenRouterModel: String { didSet { UserDefaults.standard.set(selectedOpenRouterModel, forKey: Keys.openRouterModel) } }

    // MARK: - Discovered state

    @Published var openRouterModels: [String] = OpenRouterProvider.fallbackModels
    @Published var discoveredModels: [DiscoveredModel] = []
    @Published var novaGatewayStatus: BackendStatus = .disconnected
    @Published var poolStatus: String = "Load balancing disabled"

    // MARK: - Balancer

    /// Pure, network-free balancer that spreads work across the enabled pool.
    let balancer = LoadBalancer()
    /// Least-busy mirrors how Nova's gateway spreads load.
    var balancerPolicy: BalancerPolicy = .leastBusy
    /// Keychain-backed store for the OpenRouter API key (never in UserDefaults).
    let openRouterKeychain = KeychainStore()

    private let ollamaBaseURL = "http://localhost:11434"
    private let session: URLSession

    private enum Keys {
        static let useAllLocal = "Balancer_UseAllLocalModels"
        static let useFrontier = "Balancer_EnableAllFrontierModels"
        static let useNova = "Balancer_UseNovaGateway"
        static let novaURL = "Balancer_NovaGatewayURL"
        static let openRouterModel = "Balancer_SelectedOpenRouterModel"
    }

    private func persist(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        let d = UserDefaults.standard
        self.useAllLocalModels = d.object(forKey: Keys.useAllLocal) as? Bool ?? false
        self.enableAllFrontierModels = d.object(forKey: Keys.useFrontier) as? Bool ?? false
        self.useNovaGateway = d.object(forKey: Keys.useNova) as? Bool ?? false
        self.novaGatewayURL = d.string(forKey: Keys.novaURL) ?? ModelRegistry.novaGatewayDefaultURL
        self.selectedOpenRouterModel = d.string(forKey: Keys.openRouterModel) ?? OpenRouterProvider.defaultModel
    }

    // MARK: - Toggle state

    /// True when any load-balancing toggle is on, so a request should be
    /// dispatched through the balanced path rather than a single backend.
    var isBalancingEnabled: Bool {
        useAllLocalModels || enableAllFrontierModels || useNovaGateway
    }

    // MARK: - OpenRouter API key (Keychain-backed)

    func setOpenRouterAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { openRouterKeychain.delete() } else { openRouterKeychain.set(trimmed) }
    }
    func openRouterAPIKey() -> String? { openRouterKeychain.get() }
    var hasOpenRouterKey: Bool { openRouterKeychain.hasValue }

    // MARK: - Availability probes (thin, resilient)

    func checkAvailability(_ type: LLMBackendType) async -> Bool {
        switch type {
        case .ollama: return await checkOllama()
        case .mlx: return await checkMLX()
        case .openRouter: return await checkOpenRouter()
        case .novaGateway: return await checkNovaGateway()
        default: return false
        }
    }

    private func checkOllama() async -> Bool {
        guard let url = URL(string: "\(ollamaBaseURL)/api/tags") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func checkMLX() async -> Bool {
        let pythonPath = AIBackendManager.shared.pythonPath
        guard FileManager.default.fileExists(atPath: pythonPath) else { return false }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-c", "import mlx.core as mx; print('OK')"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            } catch { continuation.resume(returning: false) }
        }
    }

    private func checkOpenRouter() async -> Bool {
        guard let key = openRouterAPIKey(), !key.isEmpty,
              let url = URL(string: OpenRouterProvider.modelsURL) else { return false }
        var request = URLRequest(url: url)
        for (header, value) in OpenRouterProvider.authHeaders(apiKey: key) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let models = OpenRouterProvider.parseModels(data)
            if !models.isEmpty {
                openRouterModels = models
                if !models.contains(selectedOpenRouterModel) {
                    selectedOpenRouterModel = models.contains(OpenRouterProvider.defaultModel)
                        ? OpenRouterProvider.defaultModel : models[0]
                }
            }
            return true
        } catch { return false }
    }

    private func checkNovaGateway() async -> Bool {
        // Probe the OpenAI-compatible models listing; fall back to the base URL.
        let candidates = ["\(novaGatewayURL)/v1/models", "\(novaGatewayURL)/"].compactMap { URL(string: $0) }
        for url in candidates {
            do {
                let (_, response) = try await session.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return true }
            } catch { continue }
        }
        return false
    }

    /// Refresh the Nova Gateway status flag for the settings UI (never throws).
    func refreshNovaGatewayStatus() async {
        guard useNovaGateway else { novaGatewayStatus = .disconnected; return }
        novaGatewayStatus = .checking
        novaGatewayStatus = await checkNovaGateway() ? .connected : .disconnected
    }

    // MARK: - Pool discovery (honors the three toggles)

    /// Discover the enabled balancer pool. Resilient: any unreachable source
    /// contributes zero models.
    func discoverEnabledPool() async -> [DiscoveredModel] {
        var ollama: [DiscoveredModel] = []
        var mlx: [DiscoveredModel] = []
        var frontier: [DiscoveredModel] = []

        if useAllLocalModels {
            ollama = await ModelRegistry.discoverOllama(baseURL: ollamaBaseURL, session: session)
            mlx = ModelRegistry.discoverMLX()
        }
        if enableAllFrontierModels {
            frontier = ModelRegistry.frontierModels(from: openRouterModels)
        }
        let nova = useNovaGateway ? ModelRegistry.novaGatewayModel(url: novaGatewayURL) : nil

        let pool = ModelRegistry.assemblePool(
            ollama: ollama,
            mlx: mlx,
            frontier: frontier,
            novaGateway: nova,
            useAllLocalModels: useAllLocalModels,
            enableAllFrontierModels: enableAllFrontierModels,
            useNovaGateway: useNovaGateway
        )
        discoveredModels = pool
        poolStatus = pool.isEmpty
            ? (isBalancingEnabled ? "No models discovered for the enabled backends" : "Load balancing disabled")
            : "\(pool.count) model\(pool.count == 1 ? "" : "s") across \(Set(pool.map { $0.backend }).count) backend\(Set(pool.map { $0.backend }).count == 1 ? "" : "s")"
        return pool
    }

    /// Build a `[modelId: Bool]` health map for `pool` by probing each distinct
    /// backend once (health-gating, composed with `FailoverPlanner` semantics).
    private func healthMap(for pool: [DiscoveredModel]) async -> [String: Bool] {
        var backendHealth: [LLMBackendType: Bool] = [:]
        for backend in Set(pool.map { $0.backend }) {
            backendHealth[backend] = await checkAvailability(backend)
        }
        var map: [String: Bool] = [:]
        for model in pool { map[model.id] = backendHealth[model.backend] ?? false }
        return map
    }

    // MARK: - Balanced generation

    /// Balanced dispatch: pick a model via the `LoadBalancer` over the healthy
    /// enabled pool and route it through the appropriate backend. Returns nil
    /// when no pool/healthy model exists so the caller can fall back cleanly.
    func generateBalanced(
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String? {
        let pool = await discoverEnabledPool()
        guard !pool.isEmpty else { return nil }

        let health = await healthMap(for: pool)
        var remaining = pool
        var lastError: Error?

        while let choice = balancer.next(pool: remaining, health: health, policy: balancerPolicy) {
            balancer.checkOut(choice.id)
            do {
                let result = try await dispatch(model: choice, prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
                balancer.checkIn(choice.id)
                return result
            } catch {
                balancer.checkIn(choice.id)
                lastError = error
                remaining.removeAll { $0.id == choice.id }
                continue
            }
        }
        if let lastError = lastError { throw lastError }
        return nil
    }

    /// Route a single balancer-selected model through the appropriate backend
    /// implementation (all OpenAI-compatible backends ride the generic path).
    private func dispatch(
        model: DiscoveredModel,
        prompt: String,
        systemPrompt: String?,
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        switch model.backend {
        case .ollama:
            return try await generateWithOllama(model: model.modelName, prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .mlx:
            return try await generateWithMLX(model: model.modelName, prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        case .openRouter:
            guard let key = openRouterAPIKey(), !key.isEmpty else { throw LLMError.noBackendAvailable }
            return try await generateOpenAICompatible(endpoint: model.endpoint, model: model.modelName, headers: OpenRouterProvider.authHeaders(apiKey: key), prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        case .novaGateway:
            return try await generateOpenAICompatible(endpoint: model.endpoint, model: model.modelName, headers: [:], prompt: prompt, systemPrompt: systemPrompt, temperature: temperature, maxTokens: maxTokens)
        default:
            throw LLMError.noBackendAvailable
        }
    }

    // MARK: - Backend implementations

    private func generateWithOllama(model: String, prompt: String, systemPrompt: String?, temperature: Float, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(ollamaBaseURL)/api/chat") else { throw LLMError.invalidURL }
        var messages: [[String: String]] = []
        if let system = systemPrompt, !system.isEmpty { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": prompt])
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            "options": ["temperature": temperature, "num_predict": maxTokens]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.noResponse
        }
        return content
    }

    private func generateOpenAICompatible(endpoint: String, model: String, headers: [String: String], prompt: String, systemPrompt: String?, temperature: Float, maxTokens: Int) async throws -> String {
        let apiMessages = OpenAICompatibleRequest.chatMessages(prompt: prompt, systemPrompt: systemPrompt, history: [])
        var request = try OpenAICompatibleRequest.build(
            endpoint: endpoint, model: model, messages: apiMessages,
            temperature: temperature, maxTokens: maxTokens, stream: false, headers: headers
        )
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct OpenAIResponse: Codable {
            struct Choice: Codable { struct Message: Codable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    private func generateWithMLX(model: String, prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> String {
        let pythonPath = AIBackendManager.shared.pythonPath
        guard FileManager.default.fileExists(atPath: pythonPath) else { throw LLMError.mlxNotAvailable }

        var fullPrompt = prompt
        if let system = systemPrompt, !system.isEmpty { fullPrompt = "\(system)\n\n\(prompt)" }

        let promptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("mbox_mlx_prompt_\(UUID().uuidString).txt")
        try fullPrompt.write(to: promptFile, atomically: true, encoding: .utf8)

        return try await withCheckedThrowingContinuation { continuation in
            defer { try? FileManager.default.removeItem(at: promptFile) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-c", """
                from mlx_lm import load, generate
                with open('\(promptFile.path)', 'r', encoding='utf-8') as f:
                    prompt = f.read()
                model, tokenizer = load("\(model)")
                response = generate(model, tokenizer, prompt=prompt, max_tokens=\(maxTokens))
                print(response)
                """]
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: LLMError.mlxNotAvailable); return
                }
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                    continuation.resume(throwing: LLMError.noResponse); return
                }
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                continuation.resume(throwing: LLMError.mlxNotAvailable)
            }
        }
    }

    // MARK: - Balanced embeddings (bulk semantic indexing)

    /// The local, Ollama-served models eligible to spread embedding work across.
    /// Bulk indexing routes its model selection through here so the work fans out
    /// over every local model instead of hammering one.
    func localEmbeddingPool() async -> [DiscoveredModel] {
        guard useAllLocalModels else { return [] }
        return await ModelRegistry.discoverOllama(baseURL: ollamaBaseURL, session: session)
            .filter { $0.backend == .ollama }
    }

    /// Pick the next local model for an embedding request via the load balancer.
    func nextEmbeddingModel(from pool: [DiscoveredModel]) -> DiscoveredModel? {
        balancer.next(pool: pool, policy: balancerPolicy)
    }

    /// Generate one embedding against a specific Ollama model (used by the
    /// balanced embedding provider). Network call, so kept off the pure path.
    func embed(text: String, model: String) async throws -> [Float] {
        guard let url = URL(string: "\(ollamaBaseURL)/api/embeddings") else { throw LLMError.invalidURL }
        let body: [String: Any] = ["model": model, "prompt": text]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct EmbeddingResponse: Codable { let embedding: [Float] }
        return try JSONDecoder().decode(EmbeddingResponse.self, from: data).embedding
    }
}
