//
//  LocalLLM.swift
//  MBox Explorer
//
//  Local LLM integration using Ollama
//  Author: Jordan Koch
//  Date: 2025-12-03
//  Updated: 2025-01-17 - Replaced MLX stub with Ollama
//

import Foundation

/// Local LLM manager using AI Backend (Ollama or MLX)
class LocalLLM: ObservableObject {
    @Published var isAvailable = false
    @Published var isProcessing = false
    @Published var lastResponse = ""

    private let aiBackend = AIBackendManager.shared

    init() {
        Task {
            await checkAvailability()
        }
    }

    func checkAvailability() async {
        await aiBackend.checkBackendAvailability()
        await MainActor.run {
            isAvailable = aiBackend.activeBackend != nil
        }
    }

    /// Get active backend for display
    @MainActor
    func getActiveBackend() -> AIBackend? {
        return aiBackend.activeBackend
    }

    /// Ask a question about emails using RAG (Retrieval-Augmented Generation)
    func askQuestion(_ question: String, context: [SearchResult]) async -> String {
        guard isAvailable else {
            return "AI Backend not available. Using basic context extraction:\n\n" + generateBasicAnswer(question, context: context)
        }

        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Step 1: Prepare context from retrieved emails (RAG - Augmentation step)
        let contextText = context.prefix(10).map { result in
            """
            From: \(result.from)
            Subject: \(result.subject)
            Date: \(result.date)
            \(result.snippet)
            ---
            """
        }.joined(separator: "\n")

        // Step 2: Build RAG prompt
        let systemPrompt = """
        You are an email assistant. Answer the user's question based on the following emails.
        Be concise and cite specific emails when relevant. If the emails don't contain enough information to answer the question, say so.
        """

        let userPrompt = """
        EMAILS:
        \(contextText)

        QUESTION: \(question)

        Provide a helpful answer based on the email context above.
        """

        // Step 3: Generate response using AI Backend
        do {
            let response = try await aiBackend.generate(
                prompt: userPrompt,
                systemPrompt: systemPrompt
            )

            await MainActor.run {
                lastResponse = response
            }

            return response
        } catch {
            let errorMessage = "AI Backend error: \(error.localizedDescription)"
            print(errorMessage)
            return errorMessage + "\n\nFalling back to basic extraction:\n\n" + generateBasicAnswer(question, context: context)
        }
    }

    private func generateBasicAnswer(_ question: String, context: [SearchResult]) -> String {
        var answer = "Found \(context.count) relevant emails:\n\n"

        for (index, result) in context.prefix(3).enumerated() {
            answer += "\(index + 1). From: \(result.from)\n"
            answer += "   Subject: \(result.subject)\n"
            answer += "   Date: \(result.date)\n"
            answer += "   \(result.snippet)\n\n"
        }

        if context.count > 3 {
            answer += "...and \(context.count - 3) more emails\n"
        }

        return answer
    }

    /// Generate summary of email or thread
    func summarize(content: String) async -> String {
        guard isAvailable else {
            return generateBasicSummary(content)
        }

        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let prompt = """
        Summarize the following email content in 2-3 sentences. Focus on the key points and main action items.

        EMAIL CONTENT:
        \(content.prefix(2000))
        """

        do {
            let summary = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are a concise email summarizer. Provide brief, clear summaries.",
                temperature: 0.3 // Lower temperature for more consistent summaries
            )
            return summary
        } catch {
            print("Summarization error: \(error.localizedDescription)")
            return generateBasicSummary(content)
        }
    }

    private func generateBasicSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let firstLines = lines.prefix(10).joined(separator: " ")

        if firstLines.count > 200 {
            return String(firstLines.prefix(200)) + "..."
        }
        return firstLines
    }
}
