//
//  ConversationManager.swift
//  MBox Explorer
//
//  Manages multi-turn AI conversations with email context
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation
import Combine

/// Manages conversational AI interactions with email archive
@MainActor
class ConversationManager: ObservableObject {
    static let shared = ConversationManager()

    // MARK: - Published State

    @Published var currentConversation: Conversation?
    @Published var isProcessing = false
    @Published var streamingResponse = ""
    @Published var currentCitations: [EmailCitation] = []
    @Published var suggestedFollowUps: [String] = []
    @Published var lastError: String?

    // MARK: - Dependencies

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared
    private var vectorDB: VectorDatabase?

    // MARK: - Configuration

    private let maxContextTurns = 10
    private let maxContextTokens = 4000 // Approximate token limit for context

    // MARK: - Initialization

    private init() {}

    func setVectorDatabase(_ db: VectorDatabase) {
        self.vectorDB = db
    }

    // MARK: - Conversation Management

    /// Start a new conversation
    func startNewConversation(title: String? = nil) {
        let conversation = Conversation(
            title: title ?? "New Conversation"
        )
        currentConversation = conversation
        streamingResponse = ""
        currentCitations = []
        suggestedFollowUps = []
    }

    /// Load an existing conversation
    func loadConversation(_ conversation: Conversation) {
        currentConversation = conversation
        streamingResponse = ""

        // Restore citations from last assistant message
        if let lastAssistantMessage = conversation.messages.last(where: { $0.role == .assistant }) {
            currentCitations = lastAssistantMessage.citations
        } else {
            currentCitations = []
        }
    }

    /// Branch from a specific message (explore alternative paths)
    func branchConversation(from message: ConversationMessage) {
        guard let current = currentConversation else { return }

        // Find message index
        guard let messageIndex = current.messages.firstIndex(where: { $0.id == message.id }) else { return }

        // Create new conversation with messages up to branch point
        let branchedMessages = Array(current.messages.prefix(through: messageIndex))

        let branchedConversation = Conversation(
            title: "Branch: \(current.title)",
            messages: branchedMessages,
            tags: current.tags,
            emailContext: current.emailContext,
            branchParentId: current.id,
            branchPointMessageId: message.id
        )

        currentConversation = branchedConversation
        database.saveConversation(branchedConversation)
    }

    /// Save current conversation
    func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }
        database.saveConversation(conversation)
    }

    /// Delete a conversation
    func deleteConversation(_ conversation: Conversation) {
        database.deleteConversation(conversation)
        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }
    }

    /// Toggle favorite status
    func toggleFavorite() {
        guard var conversation = currentConversation else { return }
        conversation.isFavorite.toggle()
        currentConversation = conversation
        database.saveConversation(conversation)
    }

    /// Update conversation title
    func updateTitle(_ title: String) {
        guard var conversation = currentConversation else { return }
        conversation.title = title
        currentConversation = conversation
        database.saveConversation(conversation)
    }

    /// Add tag to conversation
    func addTag(_ tag: String) {
        guard var conversation = currentConversation else { return }
        if !conversation.tags.contains(tag) {
            conversation.tags.append(tag)
            currentConversation = conversation
            database.saveConversation(conversation)
        }
    }

    // MARK: - Message Handling

    /// Send a user message and get AI response
    func sendMessage(_ content: String) async {
        guard var conversation = currentConversation else {
            startNewConversation()
            await sendMessage(content)
            return
        }

        isProcessing = true
        streamingResponse = ""
        lastError = nil

        // Create user message
        let userMessage = ConversationMessage(
            role: .user,
            content: content
        )
        conversation.addMessage(userMessage)
        currentConversation = conversation

        let startTime = Date()

        do {
            // Search for relevant emails
            let searchResults = await searchRelevantEmails(query: content)

            // Build context with conversation history + email results
            let (systemPrompt, userPrompt) = buildPrompts(
                query: content,
                conversationHistory: conversation.contextMessages(maxTurns: maxContextTurns),
                emailResults: searchResults
            )

            // Generate response
            let response = try await aiBackend.generate(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                temperature: 0.7
            )

            // Create citations from search results
            let citations = createCitations(from: searchResults)

            // Parse suggested follow-ups from response
            let followUps = parseFollowUpSuggestions(from: response)

            // Create assistant message
            let processingTime = Date().timeIntervalSince(startTime)
            let metadata = MessageMetadata(
                queryType: detectQueryType(content),
                processingTime: processingTime,
                modelUsed: aiBackend.activeBackend?.rawValue,
                searchResults: searchResults.count,
                suggestedFollowUps: followUps
            )

            let assistantMessage = ConversationMessage(
                role: .assistant,
                content: response,
                citations: citations,
                metadata: metadata
            )

            conversation.addMessage(assistantMessage)

            // Update email context with referenced emails
            let referencedEmailIds = citations.map { $0.emailId }
            for emailId in referencedEmailIds {
                if !conversation.emailContext.contains(emailId) {
                    conversation.emailContext.append(emailId)
                }
            }

            // Auto-generate title if first exchange
            if conversation.messages.count == 2 && conversation.title == "New Conversation" {
                conversation.title = await generateConversationTitle(firstMessage: content)
            }

            currentConversation = conversation
            currentCitations = citations
            suggestedFollowUps = followUps

            // Save conversation
            database.saveConversation(conversation)

        } catch {
            lastError = error.localizedDescription

            // Add error message
            let errorMessage = ConversationMessage(
                role: .assistant,
                content: "I encountered an error: \(error.localizedDescription). Please try again."
            )
            conversation.addMessage(errorMessage)
            currentConversation = conversation
        }

        isProcessing = false
    }

    /// Continue from the last response (regenerate or elaborate)
    func continueThought() async {
        guard let conversation = currentConversation,
              let lastMessage = conversation.messages.last,
              lastMessage.role == .assistant else { return }

        let prompt = "Please continue and elaborate on your previous response."
        await sendMessage(prompt)
    }

    /// Regenerate the last response
    func regenerateLastResponse() async {
        guard var conversation = currentConversation else { return }

        // Remove last assistant message
        if let lastAssistantIndex = conversation.messages.lastIndex(where: { $0.role == .assistant }) {
            conversation.messages.remove(at: lastAssistantIndex)
            currentConversation = conversation

            // Get the user message that preceded it
            if let lastUserMessage = conversation.messages.last(where: { $0.role == .user }) {
                await sendMessage(lastUserMessage.content)
            }
        }
    }

    // MARK: - Search & Context

    private func searchRelevantEmails(query: String) async -> [SearchResult] {
        guard let vectorDB = vectorDB else { return [] }
        return await vectorDB.search(query: query)
    }

    private func buildPrompts(
        query: String,
        conversationHistory: [ConversationMessage],
        emailResults: [SearchResult]
    ) -> (system: String, user: String) {

        // Build conversation context
        var conversationContext = ""
        if !conversationHistory.isEmpty {
            conversationContext = "PREVIOUS CONVERSATION:\n"
            for message in conversationHistory.dropLast() { // Exclude current message
                let role = message.role == .user ? "User" : "Assistant"
                conversationContext += "\(role): \(message.content.prefix(500))\n"
            }
            conversationContext += "\n"
        }

        // Build email context
        var emailContext = ""
        if !emailResults.isEmpty {
            emailContext = "RELEVANT EMAILS:\n"
            for (index, result) in emailResults.prefix(10).enumerated() {
                emailContext += """
                [\(index + 1)] From: \(result.from)
                Subject: \(result.subject)
                Date: \(result.date)
                \(result.snippet.prefix(300))
                ---
                """
            }
        }

        let systemPrompt = """
        You are an intelligent email assistant helping the user understand and interact with their email archive.

        CAPABILITIES:
        - Answer questions about email content with citations [1], [2], etc.
        - Summarize threads and conversations
        - Track commitments and action items
        - Analyze relationships and communication patterns
        - Provide insights on sentiment and tone changes
        - Help draft responses based on conversation context

        GUIDELINES:
        - Always cite your sources using [N] notation when referencing specific emails
        - Remember the conversation context and refer back to previous exchanges
        - Be concise but thorough
        - If you don't have enough information, say so
        - Suggest relevant follow-up questions when appropriate

        RESPONSE FORMAT:
        - Provide clear, actionable answers
        - End with 1-2 suggested follow-up questions prefixed with "You might also ask:"
        """

        let userPrompt = """
        \(conversationContext)
        \(emailContext)

        CURRENT QUESTION: \(query)

        Please provide a helpful response based on the email context and conversation history.
        Remember to cite specific emails using [N] notation and suggest follow-up questions.
        """

        return (systemPrompt, userPrompt)
    }

    private func createCitations(from results: [SearchResult]) -> [EmailCitation] {
        return results.prefix(10).enumerated().map { index, result in
            EmailCitation(
                emailId: result.emailId,
                from: result.from,
                subject: result.subject,
                date: result.date,
                snippet: result.snippet,
                relevanceScore: result.score,
                citationIndex: index + 1
            )
        }
    }

    private func parseFollowUpSuggestions(from response: String) -> [String] {
        var suggestions: [String] = []

        // Look for follow-up patterns
        let patterns = [
            "You might also ask:",
            "Follow-up questions:",
            "You could also explore:",
            "Related questions:"
        ]

        for pattern in patterns {
            if let range = response.range(of: pattern, options: .caseInsensitive) {
                let afterPattern = response[range.upperBound...]
                let lines = afterPattern.components(separatedBy: .newlines)

                for line in lines.prefix(3) {
                    let cleaned = line.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)

                    if !cleaned.isEmpty && cleaned.count > 10 && cleaned.count < 200 {
                        suggestions.append(cleaned)
                    }

                    // Stop if we hit another section or empty line
                    if cleaned.isEmpty || cleaned.hasSuffix(":") {
                        break
                    }
                }
            }
        }

        // If no explicit suggestions found, generate generic ones based on query type
        if suggestions.isEmpty {
            suggestions = [
                "Tell me more about this topic",
                "What are the key action items?",
                "Show me related conversations"
            ]
        }

        return Array(suggestions.prefix(3))
    }

    private func detectQueryType(_ query: String) -> QueryType {
        let lowerQuery = query.lowercased()

        if lowerQuery.contains("summarize") || lowerQuery.contains("summary") {
            return .summary
        } else if lowerQuery.contains("draft") || lowerQuery.contains("write") || lowerQuery.contains("compose") {
            return .draft
        } else if lowerQuery.contains("forward") || lowerQuery.contains("send to") {
            return .forward
        } else if lowerQuery.contains("what if") || lowerQuery.contains("hypothetical") {
            return .hypothetical
        } else if lowerQuery.contains("talk to me as") || lowerQuery.contains("perspective") || lowerQuery.contains("would say") {
            return .persona
        } else if lowerQuery.contains("last month") || lowerQuery.contains("last year") || lowerQuery.contains("in 20") {
            return .timeTravel
        } else if lowerQuery.contains("analyze") || lowerQuery.contains("trend") || lowerQuery.contains("pattern") {
            return .analysis
        } else if lowerQuery.contains("find") || lowerQuery.contains("search") || lowerQuery.contains("show me") {
            return .search
        } else if lowerQuery.contains("what") || lowerQuery.contains("?") {
            return .clarification
        }

        return .search
    }

    private func generateConversationTitle(firstMessage: String) async -> String {
        // Use AI to generate a concise title
        let prompt = """
        Generate a very short (3-5 words) title for a conversation that started with this message:
        "\(firstMessage.prefix(200))"

        Respond with ONLY the title, nothing else.
        """

        do {
            let title = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You generate concise conversation titles. Respond with only the title.",
                temperature: 0.3
            )
            return title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50).description
        } catch {
            // Fallback: use first few words of message
            let words = firstMessage.components(separatedBy: .whitespaces).prefix(5)
            return words.joined(separator: " ")
        }
    }

    // MARK: - Citation Navigation

    /// Get email for a citation
    func getEmailForCitation(_ citation: EmailCitation) -> Email? {
        // This would be implemented to look up the email from the loaded emails
        // For now, return nil - the view layer should handle this
        return nil
    }

    /// Get all emails related to current conversation
    func getRelatedEmails() -> [String] {
        return currentConversation?.emailContext ?? []
    }
}
