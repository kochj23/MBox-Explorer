//
//  AISummarizer.swift
//  MBox Explorer
//
//  User-facing "Summarize" (email detail view) on NovaAIKit (AppAI): Auto failover across the configured backends,
//  retries, the AI on/off switch, output validation, and a basic extractive summary whenever AI is not used.
//  Prompt construction stays in the pure, network-free `SummarizationRequest` enum (unit-tested).
//

import Foundation
import NovaAIKit

// MARK: - Pure request building & validation (network-free, unit-tested)

enum SummarizationRequest {
    /// System prompt shared by single-email and thread summarization.
    static let systemPrompt = "You are a concise email summarizer. Provide a brief, clear summary focusing on key points and action items."

    /// Default cap on how much body text is sent to the model.
    static let defaultBodyLimit = 4000

    /// Longest summary shown (characters).
    static let maxSummaryCharacters = 1200

    /// Validator: non-empty plain text, reasoning removed, capped, and no figures that are not in the email(s).
    static func validator(source: String) -> @Sendable (String) throws -> String {
        { raw in
            let text = NovaAIText.plain(try AppAI.validText(raw), max: maxSummaryCharacters)
            guard !text.isEmpty else { throw NovaAIValidationError("empty summary") }
            let invented = AppAI.inventedFigures(in: text, source: source)
            guard invented.isEmpty else {
                throw NovaAIValidationError("the summary contains figures that are not in the email: \(invented.prefix(5).joined(separator: ", "))")
            }
            return text
        }
    }

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
}

// MARK: - Summary result

struct AISummary: Identifiable {
    let id = UUID()
    /// The summary text (model-generated, or a basic extractive fallback).
    let summary: String
    /// Where it came from: "AI · Ollama (qwen3:8b)" or "Built-in".
    let sourceLabel: String
    /// When non-nil, the AI summary was not used and `summary` is the basic fallback.
    let unavailableReason: String?

    var isFallback: Bool { unavailableReason != nil }
}

// MARK: - Async summarizer

@MainActor
final class AISummarizer: ObservableObject {
    @Published var isProcessing = false

    private let ai: NovaAI?

    /// - Parameter ai: the NovaAI to use (tests inject one); nil = `AppAI.shared`.
    init(ai: NovaAI? = nil) {
        self.ai = ai
    }

    /// Summarize a single email; never throws.
    func summarize(email: Email) async -> AISummary {
        isProcessing = true
        defer { isProcessing = false }
        let prompt = SummarizationRequest.emailPrompt(subject: email.subject, from: email.from, date: email.date, body: email.body)
        return await run(prompt: prompt, basisText: email.body, source: "\(email.subject)\n\(email.date)\n\(email.body)")
    }

    /// Summarize an email thread; never throws.
    func summarize(thread: [Email]) async -> AISummary {
        isProcessing = true
        defer { isProcessing = false }
        let messages = thread.map { (from: $0.from, date: $0.date, subject: $0.subject, body: $0.body) }
        let prompt = SummarizationRequest.threadPrompt(messages: messages)
        let basis = thread.map { $0.body }.joined(separator: "\n")
        return await run(prompt: prompt, basisText: basis, source: prompt)
    }

    private func run(prompt: String, basisText: String, source: String) async -> AISummary {
        let result = await AppAI.text(prompt: prompt,
                                      systemPrompt: SummarizationRequest.systemPrompt,
                                      temperature: 0.3,
                                      maxTokens: 512,
                                      validate: SummarizationRequest.validator(source: source),
                                      ai: ai,
                                      fallback: { AISummarizer.basicSummary(basisText) })
        return AISummary(summary: result.value, sourceLabel: result.source.label, unavailableReason: Self.reason(result.source))
    }

    /// Why the built-in summary was used (nil when AI produced it).
    nonisolated static func reason(_ source: NovaAISource) -> String? {
        guard case .fallback(let why) = source else { return nil }
        switch why {
        case .disabled: return "AI is turned off (Settings › AI). Showing the first lines of the message."
        case .unavailable(let detail): return "No AI backend answered (\(detail)). Showing the first lines of the message."
        case .validationFailed(let detail): return "The AI summary was rejected (\(detail)). Showing the first lines of the message."
        }
    }

    /// Network-free extractive fallback used when no AI summary is available.
    nonisolated static func basicSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.prefix(10).joined(separator: " ")
        return joined.count > 300 ? String(joined.prefix(300)) + "…" : joined
    }
}
