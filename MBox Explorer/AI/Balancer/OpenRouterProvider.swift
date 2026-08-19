//
//  OpenRouterProvider.swift
//  MBox Explorer (balancer core — copied verbatim from AIStudio)
//
//  Created by Jordan Koch on 2026-02-19.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//
//  OpenRouter frontier-model access + the deterministic (network-free) pieces of
//  the OpenAI-compatible request path and the automatic-failover selection logic.
//  These are factored out as pure helpers so they can be unit-tested without
//  hitting the network.
//

import Foundation

// MARK: - OpenRouter constants & helpers

/// Static configuration and pure helpers for the OpenRouter provider.
enum OpenRouterProvider {
    /// OpenAI-compatible base URL (already includes `/v1`).
    static let baseURL = "https://openrouter.ai/api/v1"
    /// Full chat-completions endpoint.
    static var chatCompletionsURL: String { "\(baseURL)/chat/completions" }
    /// Models listing endpoint.
    static var modelsURL: String { "\(baseURL)/models" }

    /// Attribution headers required/recommended by OpenRouter.
    static let referer = "https://github.com/kochj23/MBox-Explorer"
    static let title = "MBox-Explorer"

    /// macOS Keychain service used to store the OpenRouter API key.
    static let keychainService = "com.jkoch.mboxexplorer.openrouter"

    /// Hardcoded fallback model list used when the live `/models` fetch fails.
    /// A few popular current models spanning providers.
    static let fallbackModels: [String] = [
        "anthropic/claude-sonnet-4.5",
        "openai/gpt-4o",
        "google/gemini-2.0-flash-001",
        "meta-llama/llama-3.3-70b-instruct",
        "deepseek/deepseek-chat"
    ]

    /// Default model selected when none has been chosen yet.
    static var defaultModel: String { fallbackModels.first ?? "openai/gpt-4o" }

    /// Auth + attribution headers for OpenRouter requests.
    static func authHeaders(apiKey: String) -> [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "HTTP-Referer": referer,
            "X-Title": title
        ]
    }

    /// Parse the model ids out of an OpenRouter `/models` response body.
    /// Returns an empty array if the payload can't be parsed.
    static func parseModels(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            return []
        }
        return models.compactMap { $0["id"] as? String }
    }
}

// MARK: - OpenAI-compatible request construction

/// Pure builders for the generic OpenAI-compatible `/v1/chat/completions` request.
/// No network, no shared state — fully unit-testable.
enum OpenAICompatibleRequest {
    /// Map a prompt + optional system prompt + prior history into the OpenAI
    /// `messages` array shape.
    static func chatMessages(
        prompt: String,
        systemPrompt: String?,
        history: [BalancerChatMessage]
    ) -> [[String: String]] {
        var messages: [[String: String]] = []

        if let system = systemPrompt, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }

        for msg in history where msg.role != .system {
            messages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        // Add the new user prompt unless it's already the trailing message.
        if history.last?.role != .user || history.last?.content != prompt {
            messages.append(["role": "user", "content": prompt])
        }

        return messages
    }

    /// Build a POST `URLRequest` for a full chat-completions endpoint URL.
    /// - Parameter endpoint: the complete URL (e.g. OpenRouter's
    ///   `https://openrouter.ai/api/v1/chat/completions`, or a local
    ///   `http://host/v1/chat/completions`).
    static func build(
        endpoint: String,
        model: String,
        messages: [[String: String]],
        temperature: Float,
        maxTokens: Int,
        stream: Bool,
        headers: [String: String] = [:]
    ) throws -> URLRequest {
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": maxTokens,
            "stream": stream
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Automatic failover selection

/// Pure selection logic for health-checked automatic failover — the single-user
/// version of Nova's load balancing. Given an ordered preference chain and a map
/// of per-backend availability, pick which backend to use. No network here so it
/// is fully unit-testable; the manager injects live availability.
enum FailoverPlanner {
    /// Default ordered preference chain: local-first, then frontier.
    static let defaultChain: [LLMBackendType] = [.ollama, .mlx, .openRouter]

    /// The ordered subset of `chain` that is currently available.
    static func orderedHealthy(
        chain: [LLMBackendType],
        availability: [LLMBackendType: Bool]
    ) -> [LLMBackendType] {
        chain.filter { availability[$0] == true }
    }

    /// The first backend in `chain` that is available, or nil if none are.
    static func firstHealthy(
        chain: [LLMBackendType],
        availability: [LLMBackendType: Bool]
    ) -> LLMBackendType? {
        chain.first { availability[$0] == true }
    }
}
