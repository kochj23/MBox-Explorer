//
//  BalancedSummarizer.swift
//  MBox Explorer
//
//  User-facing "Summarize" powered by the multi-model load balancer.
//
//  The request-construction and availability-decision logic is factored into the
//  pure, network-free `SummarizationRequest` enum so it is fully unit-testable.
//  `BalancedSummarizer` adds the thin async layer that actually dispatches:
//    1. balanced pool (when any load-balancing toggle is on),
//    2. the app's existing single active backend,
//    3. graceful degradation — a clear reason + basic extractive summary, never a crash.
//

import Foundation

// MARK: - Pure request building & availability (network-free, unit-tested)

enum SummarizationRequest {
    /// System prompt shared by single-email and thread summarization.
    static let systemPrompt = "You are a concise email summarizer. Provide a brief, clear summary focusing on key points and action items."

    /// Default cap on how much body text is sent to the model.
    static let defaultBodyLimit = 4000

    /// Truncate `text` to at most `limit` characters (pure).
    static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    /// Build the user prompt for a single email (pure).
    static func emailPrompt(subject: String, from: String, date: String, body: String, bodyLimit: Int = defaultBodyLimit) -> String {
        """
        Summarize the following email in 2-3 sentences. Focus on the key points and any action items.

        From: \(from)
        Date: \(date)
        Subject: \(subject)

        BODY:
        \(truncate(body, limit: bodyLimit))
        """
    }

    /// Build the user prompt for a thread of emails (pure).
    static func threadPrompt(messages: [(from: String, date: String, subject: String, body: String)], bodyLimit: Int = defaultBodyLimit) -> String {
        let combined = messages.map { m in
            "From: \(m.from)\nDate: \(m.date)\nSubject: \(m.subject)\n\n\(m.body)"
        }.joined(separator: "\n\n---\n\n")
        return """
        Summarize the following email thread of \(messages.count) message\(messages.count == 1 ? "" : "s") in 3-4 sentences. Capture the overall topic, decisions made, and outstanding action items.

        THREAD:
        \(truncate(combined, limit: bodyLimit))
        """
    }

    /// Which dispatch path a summarization request should take, given the current
    /// configuration. Pure — the graceful-no-backend decision is fully testable.
    enum Availability: Equatable {
        case balanced
        case single
        case unavailable(reason: String)
    }

    /// Decide the dispatch path from configuration flags (pure).
    /// - Parameters:
    ///   - isBalancingEnabled: any load-balancing toggle is on.
    ///   - balancerHasBackend: the enabled pool has at least one healthy model.
    ///   - singleBackendAvailable: the app's single active backend is reachable.
    static func availability(isBalancingEnabled: Bool, balancerHasBackend: Bool, singleBackendAvailable: Bool) -> Availability {
        if isBalancingEnabled && balancerHasBackend { return .balanced }
        if singleBackendAvailable { return .single }
        if isBalancingEnabled && !balancerHasBackend {
            return .unavailable(reason: "Load balancing is on, but no enabled backend is reachable. Start Ollama, add an OpenRouter key, or enable the Nova Gateway.")
        }
        return .unavailable(reason: "No AI backend is available. Start Ollama, enable load balancing, or configure a backend in AI Settings.")
    }
}

// MARK: - Summary result

struct BalancedSummary: Identifiable {
    let id = UUID()
    /// The summary text (model-generated, or a basic extractive fallback).
    let summary: String
    /// Human-readable label for how it was produced (e.g. "Balanced pool (3 models)").
    let sourceLabel: String
    /// When non-nil, the AI summary was unavailable and `summary` is a basic fallback.
    let unavailableReason: String?

    var isFallback: Bool { unavailableReason != nil }
}

// MARK: - Async summarizer

@MainActor
final class BalancedSummarizer: ObservableObject {
    @Published var isProcessing = false

    private let balancer: BalancedLLMManager
    private let aiBackend: AIBackendManager

    init(balancer: BalancedLLMManager = .shared, aiBackend: AIBackendManager = .shared) {
        self.balancer = balancer
        self.aiBackend = aiBackend
    }

    /// Summarize a single email through the balancer, degrading gracefully.
    func summarize(email: Email) async -> BalancedSummary {
        isProcessing = true
        defer { isProcessing = false }
        let prompt = SummarizationRequest.emailPrompt(subject: email.subject, from: email.from, date: email.date, body: email.body)
        return await run(prompt: prompt, basisText: email.body)
    }

    /// Summarize an email thread through the balancer, degrading gracefully.
    func summarize(thread: [Email]) async -> BalancedSummary {
        isProcessing = true
        defer { isProcessing = false }
        let messages = thread.map { (from: $0.from, date: $0.date, subject: $0.subject, body: $0.body) }
        let prompt = SummarizationRequest.threadPrompt(messages: messages)
        let basis = thread.map { $0.body }.joined(separator: "\n")
        return await run(prompt: prompt, basisText: basis)
    }

    private func run(prompt: String, basisText: String) async -> BalancedSummary {
        // Path 1: balanced pool.
        if balancer.isBalancingEnabled {
            do {
                if let result = try await balancer.generateBalanced(prompt: prompt, systemPrompt: SummarizationRequest.systemPrompt, temperature: 0.3, maxTokens: 512), !result.isEmpty {
                    let count = balancer.discoveredModels.count
                    return BalancedSummary(summary: result, sourceLabel: "Balanced pool (\(count) model\(count == 1 ? "" : "s"))", unavailableReason: nil)
                }
            } catch {
                // Fall through to single-backend / graceful path.
            }
        }

        // Path 2: single active backend.
        if aiBackend.activeBackend != nil {
            do {
                let result = try await aiBackend.generate(prompt: prompt, systemPrompt: SummarizationRequest.systemPrompt, temperature: aiBackend.summaryTemperature, maxTokens: 512)
                if !result.isEmpty {
                    let label = aiBackend.activeBackend?.rawValue ?? "Local backend"
                    return BalancedSummary(summary: result, sourceLabel: label, unavailableReason: nil)
                }
            } catch {
                // Fall through to graceful path.
            }
        }

        // Path 3: graceful degradation — never crash, always show something.
        let decision = SummarizationRequest.availability(
            isBalancingEnabled: balancer.isBalancingEnabled,
            balancerHasBackend: !balancer.discoveredModels.isEmpty,
            singleBackendAvailable: aiBackend.activeBackend != nil
        )
        let reason: String
        if case .unavailable(let r) = decision { reason = r } else { reason = "The AI backend did not return a summary." }
        return BalancedSummary(summary: Self.basicSummary(basisText), sourceLabel: "Basic extraction", unavailableReason: reason)
    }

    /// Network-free extractive fallback used when no AI backend is available.
    nonisolated static func basicSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.prefix(10).joined(separator: " ")
        return joined.count > 300 ? String(joined.prefix(300)) + "…" : joined
    }
}
