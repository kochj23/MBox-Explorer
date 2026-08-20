//
//  BalancerSupport.swift
//  MBox Explorer
//
//  Supporting value types for the multi-model load balancer.
//
//  These are the small, network-free types the balancer's copied-verbatim
//  pieces (`ModelRegistry`, `OpenRouterProvider`, `OpenAICompatibleRequest`)
//  depend on. In AIStudio they live alongside the manager; MBox Explorer already
//  defines its own `ChatMessage` (see `OllamaClient.swift`), so the balancer's
//  chat-message value type is namespaced as `BalancerChatMessage`/`BalancerChatRole`
//  to avoid a duplicate-declaration collision. Everything here is pure and
//  fully unit-testable.
//

import Foundation

// MARK: - Backend connection status

/// Connection status for a single balancer backend (extracted verbatim from
/// AIStudio's `BackendConfiguration.swift`).
enum BackendStatus: Sendable, Equatable {
    case connected
    case disconnected
    case checking
    case error(String)

    var displayText: String {
        switch self {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .checking: return "Checking..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var statusColor: String {
        switch self {
        case .connected: return "green"
        case .disconnected: return "gray"
        case .checking: return "yellow"
        case .error: return "red"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - Balancer chat message

/// Role in a chat conversation used by the balancer request builder.
/// (Named `BalancerChatRole` to avoid colliding with the host app's own
/// chat-message types.)
enum BalancerChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

/// A single chat message consumed by `OpenAICompatibleRequest`. Namespaced as
/// `BalancerChatMessage` because MBox Explorer already declares a `ChatMessage`.
struct BalancerChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: BalancerChatRole
    var content: String

    init(role: BalancerChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
    }
}

// MARK: - LLM errors

/// Errors surfaced by the balanced dispatch path (extracted verbatim from
/// AIStudio's `LLMBackendManager.swift`).
enum LLMError: LocalizedError, Sendable {
    case noBackendAvailable
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noResponse
    case mlxNotAvailable

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No LLM backend is available. Enable a local model, add an OpenRouter key, or enable the Nova Gateway."
        case .invalidURL:
            return "Invalid backend URL configuration."
        case .invalidResponse:
            return "Received invalid response from LLM backend."
        case .httpError(let code):
            return "HTTP error \(code) from LLM backend."
        case .noResponse:
            return "No response received from LLM backend."
        case .mlxNotAvailable:
            return "MLX not available. Install: pip install mlx-lm"
        }
    }
}
