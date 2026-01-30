//
//  LocalLLM.swift
//  MBox Explorer
//
//  Local LLM integration using Ollama with RAG Pipeline
//  Author: Jordan Koch
//  Date: 2025-12-03
//  Updated: 2025-01-17 - Replaced MLX stub with Ollama
//  Updated: 2025-01-30 - Enhanced RAG pipeline, conversation memory, custom prompts
//

import Foundation

/// Metadata about the email archive for AI context
struct EmailMetadata {
    let totalEmails: Int
    let dateRange: String
    let threadCount: Int
    let uniqueSenders: Int
    let topSenders: [(name: String, count: Int)]

    init(totalEmails: Int, dateRange: String, threadCount: Int, uniqueSenders: Int, topSenders: [(name: String, count: Int)]) {
        self.totalEmails = totalEmails
        self.dateRange = dateRange
        self.threadCount = threadCount
        self.uniqueSenders = uniqueSenders
        self.topSenders = topSenders
    }
}

/// Conversation message for memory
struct RAGConversationTurn: Identifiable, Codable {
    let id: UUID
    let role: String  // "user" or "assistant"
    let content: String
    let timestamp: Date
    let sourcesUsed: Int  // Number of emails used as context

    init(role: String, content: String, sourcesUsed: Int = 0) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.sourcesUsed = sourcesUsed
    }
}

/// Question type for smart routing
enum QuestionType {
    case statistics      // "how many", "count", "total"
    case topList         // "who sent the most", "top senders"
    case dateRange       // "when", "date range", "oldest/newest"
    case contentSearch   // "find emails about", "what did X say"
    case summary         // "summarize", "overview"
    case followUp        // References previous conversation

    static func detect(_ question: String) -> QuestionType {
        let q = question.lowercased()

        // Check for follow-up indicators
        if q.contains("tell me more") || q.contains("those emails") ||
           q.contains("that email") || q.contains("more about") ||
           q.starts(with: "what about") || q.starts(with: "and ") {
            return .followUp
        }

        // Statistics questions
        if q.contains("how many") || q.contains("count") || q.contains("total") ||
           q.contains("number of") {
            return .statistics
        }

        // Top/ranking questions
        if q.contains("who sent") || q.contains("most frequent") ||
           q.contains("top sender") || q.contains("sent the most") {
            return .topList
        }

        // Date questions
        if q.contains("when") || q.contains("date range") ||
           q.contains("oldest") || q.contains("newest") || q.contains("first email") ||
           q.contains("last email") || q.contains("what year") {
            return .dateRange
        }

        // Summary questions
        if q.contains("summarize") || q.contains("summary") || q.contains("overview") ||
           q.contains("themes") || q.contains("main topics") {
            return .summary
        }

        // Default to content search
        return .contentSearch
    }
}

/// RAG Pipeline Result
struct RAGResult {
    let answer: String
    let promptSent: String
    let systemPromptUsed: String
    let sourcesUsed: [SearchResult]
    let questionType: QuestionType
    let processingTime: TimeInterval
}

/// Local LLM manager using AI Backend (Ollama or MLX) with RAG Pipeline
class LocalLLM: ObservableObject {
    @Published var isAvailable = false
    @Published var isProcessing = false
    @Published var lastResponse = ""
    @Published var lastPromptSent = ""  // For debug mode
    @Published var lastSystemPrompt = ""
    @Published var conversationHistory: [RAGConversationTurn] = []

    // Custom system prompt (user-editable)
    @Published var customSystemPrompt: String {
        didSet {
            UserDefaults.standard.set(customSystemPrompt, forKey: "LocalLLM_CustomSystemPrompt")
        }
    }

    // Debug mode
    @Published var debugMode: Bool {
        didSet {
            UserDefaults.standard.set(debugMode, forKey: "LocalLLM_DebugMode")
        }
    }

    // Conversation memory settings
    @Published var useConversationMemory: Bool {
        didSet {
            UserDefaults.standard.set(useConversationMemory, forKey: "LocalLLM_UseConversationMemory")
        }
    }

    @Published var maxConversationHistory: Int {
        didSet {
            UserDefaults.standard.set(maxConversationHistory, forKey: "LocalLLM_MaxConversationHistory")
        }
    }

    private let aiBackend = AIBackendManager.shared

    static let defaultSystemPrompt = """
    You are an email archive assistant analyzing a user's MBOX email archive.

    IMPORTANT RULES:
    1. ONLY use information from the provided MAILBOX STATISTICS and EMAILS below
    2. DO NOT invent names, dates, or content that isn't explicitly shown
    3. If asked about statistics (counts, dates, senders), use the MAILBOX STATISTICS section
    4. If asked about specific content or topics, use the EMAILS section
    5. If you cannot answer from the provided data, say "I don't have enough information to answer that based on the emails provided"
    6. Be concise and cite specific emails (by sender/subject) when relevant
    7. When referencing emails, mention the sender and subject line
    """

    init() {
        // Load saved settings
        self.customSystemPrompt = UserDefaults.standard.string(forKey: "LocalLLM_CustomSystemPrompt") ?? Self.defaultSystemPrompt
        self.debugMode = UserDefaults.standard.bool(forKey: "LocalLLM_DebugMode")
        self.useConversationMemory = UserDefaults.standard.object(forKey: "LocalLLM_UseConversationMemory") as? Bool ?? true
        self.maxConversationHistory = UserDefaults.standard.object(forKey: "LocalLLM_MaxConversationHistory") as? Int ?? 10

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

    /// Clear conversation history
    func clearConversation() {
        conversationHistory.removeAll()
    }

    /// Reset system prompt to default
    func resetSystemPrompt() {
        customSystemPrompt = Self.defaultSystemPrompt
    }

    /// Enhanced RAG Pipeline for email Q&A
    /// Returns full RAGResult with debug info
    func askQuestionRAG(_ question: String, context: [SearchResult], metadata: EmailMetadata? = nil) async -> RAGResult {
        let startTime = Date()
        let questionType = QuestionType.detect(question)

        guard isAvailable else {
            let basicAnswer = generateBasicAnswer(question, context: context)
            return RAGResult(
                answer: "AI Backend not available. Using basic context extraction:\n\n" + basicAnswer,
                promptSent: "",
                systemPromptUsed: "",
                sourcesUsed: context,
                questionType: questionType,
                processingTime: Date().timeIntervalSince(startTime)
            )
        }

        await MainActor.run {
            isProcessing = true
        }
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Step 1: Build metadata context (statistics about the mailbox)
        var metadataContext = ""
        if let meta = metadata {
            metadataContext = """
            MAILBOX STATISTICS:
            - Total emails: \(meta.totalEmails)
            - Date range: \(meta.dateRange)
            - Total threads: \(meta.threadCount)
            - Unique senders: \(meta.uniqueSenders)
            - Top senders: \(meta.topSenders.prefix(10).map { "\($0.name) (\($0.count) emails)" }.joined(separator: ", "))

            """
        }

        // Step 2: Build conversation history context (if enabled)
        var conversationContext = ""
        if useConversationMemory && !conversationHistory.isEmpty {
            let recentHistory = conversationHistory.suffix(maxConversationHistory)
            conversationContext = """
            PREVIOUS CONVERSATION:
            \(recentHistory.map { msg in
                "\(msg.role.uppercased()): \(msg.content)"
            }.joined(separator: "\n"))

            """
        }

        // Step 3: Smart routing - adjust context based on question type
        var contextText: String
        var sourcesToUse = context

        switch questionType {
        case .statistics, .topList, .dateRange:
            // For statistics questions, metadata is primary, emails are secondary
            if context.isEmpty {
                contextText = "(Statistics question - answer from MAILBOX STATISTICS above)"
            } else {
                contextText = "SAMPLE EMAILS (for reference):\n" + context.prefix(5).map { result in
                    "• \(result.from): \"\(result.subject)\" (\(result.date))"
                }.joined(separator: "\n")
            }
            sourcesToUse = Array(context.prefix(5))

        case .followUp:
            // For follow-ups, include more context from previous answers
            if context.isEmpty {
                contextText = "(Follow-up question - refer to PREVIOUS CONVERSATION above)"
            } else {
                contextText = context.prefix(10).map { result in
                    """
                    From: \(result.from)
                    Subject: \(result.subject)
                    Date: \(result.date)
                    Content: \(result.snippet)
                    ---
                    """
                }.joined(separator: "\n")
            }

        case .summary:
            // For summaries, include more emails
            contextText = context.prefix(15).map { result in
                """
                From: \(result.from)
                Subject: \(result.subject)
                Date: \(result.date)
                Preview: \(String(result.snippet.prefix(150)))
                ---
                """
            }.joined(separator: "\n")
            sourcesToUse = Array(context.prefix(15))

        case .contentSearch:
            // For content search, include full snippets
            if context.isEmpty {
                contextText = "(No emails matched this search query)"
            } else {
                contextText = context.prefix(10).map { result in
                    """
                    From: \(result.from)
                    Subject: \(result.subject)
                    Date: \(result.date)
                    Content: \(result.snippet)
                    ---
                    """
                }.joined(separator: "\n")
            }
            sourcesToUse = Array(context.prefix(10))
        }

        // Step 4: Build the full prompt
        let systemPrompt = customSystemPrompt

        let userPrompt = """
        \(metadataContext)\(conversationContext)RETRIEVED EMAILS:
        \(contextText)

        USER QUESTION: \(question)

        Answer based ONLY on the information above. Do not make up any information.
        """

        // Store for debug mode
        await MainActor.run {
            lastPromptSent = userPrompt
            lastSystemPrompt = systemPrompt
        }

        // Step 5: Generate response using AI Backend
        do {
            let response = try await aiBackend.generate(
                prompt: userPrompt,
                systemPrompt: systemPrompt,
                temperature: aiBackend.questionTemperature
            )

            // Add to conversation history
            await MainActor.run {
                lastResponse = response

                if useConversationMemory {
                    conversationHistory.append(RAGConversationTurn(role: "user", content: question))
                    conversationHistory.append(RAGConversationTurn(role: "assistant", content: response, sourcesUsed: sourcesToUse.count))

                    // Trim history if too long
                    if conversationHistory.count > maxConversationHistory * 2 {
                        conversationHistory = Array(conversationHistory.suffix(maxConversationHistory * 2))
                    }
                }
            }

            return RAGResult(
                answer: response,
                promptSent: userPrompt,
                systemPromptUsed: systemPrompt,
                sourcesUsed: sourcesToUse,
                questionType: questionType,
                processingTime: Date().timeIntervalSince(startTime)
            )
        } catch {
            let errorMessage = "AI Backend error: \(error.localizedDescription)"
            print(errorMessage)
            return RAGResult(
                answer: errorMessage + "\n\nFalling back to basic extraction:\n\n" + generateBasicAnswer(question, context: context),
                promptSent: userPrompt,
                systemPromptUsed: systemPrompt,
                sourcesUsed: sourcesToUse,
                questionType: questionType,
                processingTime: Date().timeIntervalSince(startTime)
            )
        }
    }

    /// Simplified method that returns just the answer string
    func askQuestion(_ question: String, context: [SearchResult], metadata: EmailMetadata? = nil) async -> String {
        let result = await askQuestionRAG(question, context: context, metadata: metadata)
        return result.answer
    }

    /// Legacy method for backward compatibility
    func askQuestion(_ question: String, context: [SearchResult]) async -> String {
        return await askQuestion(question, context: context, metadata: nil)
    }

    /// Export conversation to markdown
    func exportConversation() -> String {
        var markdown = "# Email Archive Q&A Session\n\n"
        markdown += "Exported: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        markdown += "---\n\n"

        for message in conversationHistory {
            if message.role == "user" {
                markdown += "## 🙋 Question\n\n"
                markdown += "\(message.content)\n\n"
            } else {
                markdown += "## 🤖 Answer\n\n"
                markdown += "\(message.content)\n\n"
                if message.sourcesUsed > 0 {
                    markdown += "*Based on \(message.sourcesUsed) emails*\n\n"
                }
            }
            markdown += "---\n\n"
        }

        return markdown
    }

    /// Export conversation to JSON
    func exportConversationJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(conversationHistory)
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
