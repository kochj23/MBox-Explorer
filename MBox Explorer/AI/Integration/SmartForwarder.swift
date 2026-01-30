//
//  SmartForwarder.swift
//  MBox Explorer
//
//  AI-powered email summarization for forwarding
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Generates smart summaries for email forwarding
@MainActor
class SmartForwarder: ObservableObject {
    static let shared = SmartForwarder()

    @Published var lastSummary: ForwardSummary?
    @Published var isGenerating = false

    private let aiBackend = AIBackendManager.shared

    private init() {}

    // MARK: - Summary Generation

    /// Generate an executive summary for forwarding a thread
    func generateForwardSummary(
        thread: [Email],
        recipient: String,
        context: String = "",
        removeSensitive: Bool = true
    ) async -> ForwardSummary {
        isGenerating = true

        let sortedThread = thread.sorted { ($0.dateObject ?? Date()) < ($1.dateObject ?? Date()) }

        let prompt = """
        Create an executive summary of this email thread for forwarding to \(recipient).

        \(context.isEmpty ? "" : "CONTEXT: \(context)\n")

        EMAIL THREAD (\(thread.count) messages):
        \(formatThread(sortedThread))

        Generate:
        1. A brief introduction (1 sentence explaining why you're forwarding)
        2. Key points (3-5 bullet points)
        3. Action items (if any)
        4. Important dates/deadlines mentioned

        \(removeSensitive ? "Remove any potentially sensitive information, personal details, or internal discussions not relevant to the recipient." : "")

        Format the summary professionally for business communication.
        """

        do {
            let summary = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert at creating concise, professional email summaries for executive communication."
            )

            let result = ForwardSummary(
                originalThread: thread.map { $0.id.uuidString },
                recipient: recipient,
                summary: summary,
                generatedAt: Date()
            )

            lastSummary = result
            isGenerating = false

            return result
        } catch {
            let errorResult = ForwardSummary(
                originalThread: thread.map { $0.id.uuidString },
                recipient: recipient,
                summary: "Error generating summary: \(error.localizedDescription)",
                generatedAt: Date()
            )

            isGenerating = false
            return errorResult
        }
    }

    /// Generate a summary for a single email
    func summarizeForForward(
        email: Email,
        recipient: String,
        highlights: [String] = []
    ) async -> ForwardSummary {
        isGenerating = true

        let prompt = """
        Summarize this email for forwarding to \(recipient).

        FROM: \(email.from)
        SUBJECT: \(email.subject)
        DATE: \(email.date)
        ---
        \(email.body)

        \(highlights.isEmpty ? "" : "HIGHLIGHT THESE POINTS:\n\(highlights.map { "- \($0)" }.joined(separator: "\n"))")

        Provide a professional summary that includes:
        1. One-line context (why this is relevant)
        2. Key information
        3. Any required actions
        """

        do {
            let summary = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You create concise email summaries for forwarding."
            )

            let result = ForwardSummary(
                originalThread: [email.id.uuidString],
                recipient: recipient,
                summary: summary,
                generatedAt: Date()
            )

            lastSummary = result
            isGenerating = false

            return result
        } catch {
            let errorResult = ForwardSummary(
                originalThread: [email.id.uuidString],
                recipient: recipient,
                summary: "Error: \(error.localizedDescription)",
                generatedAt: Date()
            )

            isGenerating = false
            return errorResult
        }
    }

    /// Redact sensitive information from email content
    func redactSensitiveContent(_ text: String) async -> String {
        let prompt = """
        Remove or redact sensitive information from this text:

        \(text)

        Redact:
        - Personal phone numbers (replace with [PHONE])
        - Social security numbers (replace with [SSN])
        - Credit card numbers (replace with [CC])
        - Personal addresses (replace with [ADDRESS])
        - Salary/compensation details (replace with [COMPENSATION])
        - Internal politics or gossip
        - Personal health information

        Keep business-relevant information intact.
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You redact sensitive information while preserving business-relevant content."
            )
        } catch {
            return text
        }
    }

    /// Generate a quick forward note
    func generateForwardNote(for email: Email, to recipient: String, reason: String) async -> String {
        let prompt = """
        Generate a brief forward note for this email.

        FORWARDING TO: \(recipient)
        REASON: \(reason)

        ORIGINAL EMAIL:
        From: \(email.from)
        Subject: \(email.subject)

        Generate a 1-2 sentence forward note that explains why you're forwarding this.
        Example format: "Hi [name], forwarding this for your review - [reason]."
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You write brief, professional email forward notes.",
                temperature: 0.5
            )
        } catch {
            return "FYI - \(reason)"
        }
    }

    /// Generate a summary for forwarding to different audiences
    func generateAudienceSummary(
        thread: [Email],
        audience: ForwardAudience
    ) async -> String {
        let sortedThread = thread.sorted { ($0.dateObject ?? Date()) < ($1.dateObject ?? Date()) }

        let audienceGuidelines: String
        switch audience {
        case .executive:
            audienceGuidelines = "Focus on business impact, decisions, and outcomes. Keep it under 5 bullet points. Skip technical details."
        case .technical:
            audienceGuidelines = "Include technical details, specifications, and implementation concerns. Be precise."
        case .stakeholder:
            audienceGuidelines = "Focus on progress, blockers, and impact on deliverables. Highlight risks and dependencies."
        case .legal:
            audienceGuidelines = "Include any commitments made, contractual references, and compliance-related information."
        case .general:
            audienceGuidelines = "Provide a balanced summary suitable for anyone. Clear and professional."
        }

        let prompt = """
        Summarize this email thread for a \(audience.rawValue.lowercased()) audience.

        AUDIENCE GUIDELINES: \(audienceGuidelines)

        EMAIL THREAD:
        \(formatThread(sortedThread))

        Generate an appropriate summary.
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You create audience-appropriate email summaries."
            )
        } catch {
            return "Error generating summary: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func formatThread(_ emails: [Email]) -> String {
        return emails.prefix(10).map { email in
            """
            From: \(email.from)
            Date: \(email.date)
            Subject: \(email.subject)
            ---
            \(email.body.prefix(500))
            """
        }.joined(separator: "\n\n===\n\n")
    }
}

// MARK: - Supporting Types

struct ForwardSummary: Identifiable {
    let id = UUID()
    let originalThread: [String]
    let recipient: String
    let summary: String
    let generatedAt: Date
}

enum ForwardAudience: String, CaseIterable {
    case executive = "Executive"
    case technical = "Technical"
    case stakeholder = "Stakeholder"
    case legal = "Legal"
    case general = "General"
}
