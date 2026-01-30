//
//  EmailSearchAgent.swift
//  MBox Explorer
//
//  Intelligent agent for complex multi-step email searches
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Intelligent agent for complex email search queries
@MainActor
class EmailSearchAgent: ObservableObject {
    static let shared = EmailSearchAgent()

    @Published var lastSearch: AgentSearchResult?
    @Published var isSearching = false
    @Published var searchProgress: String = ""

    private let aiBackend = AIBackendManager.shared
    private var vectorDB: VectorDatabase?

    private init() {}

    func setVectorDatabase(_ db: VectorDatabase) {
        self.vectorDB = db
    }

    // MARK: - Complex Searches

    /// Execute a complex natural language search query
    func search(query: String, emails: [Email]) async -> AgentSearchResult {
        isSearching = true
        searchProgress = "Analyzing query..."

        // Understand the query intent
        let intent = await analyzeQueryIntent(query)

        searchProgress = "Searching \(intent.searchStrategy.rawValue)..."

        // Execute search based on intent
        let results: [Email]

        switch intent.searchStrategy {
        case .semantic:
            results = await semanticSearch(query: query, emails: emails)
        case .criteria:
            results = criteriaSearch(criteria: intent.extractedCriteria, emails: emails)
        case .behavioral:
            results = await behavioralSearch(behavior: intent.behaviorPattern ?? "", emails: emails)
        case .comparative:
            results = await comparativeSearch(comparison: intent.comparison ?? "", emails: emails)
        }

        searchProgress = "Generating summary..."

        // Generate summary of results
        let summary = await generateSearchSummary(query: query, results: results)

        let result = AgentSearchResult(
            query: query,
            intent: intent,
            results: results.prefix(50).map { $0 },
            summary: summary,
            timestamp: Date()
        )

        lastSearch = result
        isSearching = false
        searchProgress = ""

        return result
    }

    /// Search for specific patterns like "emails where promises weren't kept"
    func searchForPattern(pattern: SearchPattern, emails: [Email]) async -> AgentSearchResult {
        isSearching = true
        searchProgress = "Searching for pattern: \(pattern.description)..."

        var results: [Email] = []

        switch pattern {
        case .unkeptPromises:
            results = await findUnkeptPromises(in: emails)
        case .sentimentDecline:
            results = await findSentimentDecline(in: emails)
        case .ignoredRequests:
            results = await findIgnoredRequests(in: emails)
        case .escalatingTension:
            results = await findEscalatingTension(in: emails)
        case .recurringTopics:
            results = findRecurringTopics(in: emails)
        case .deadlinesMissed:
            results = findMissedDeadlines(in: emails)
        }

        let summary = await generatePatternSummary(pattern: pattern, results: results)

        let intent = SearchIntent(
            searchStrategy: .behavioral,
            extractedCriteria: [:],
            behaviorPattern: pattern.rawValue,
            comparison: nil
        )

        let result = AgentSearchResult(
            query: pattern.description,
            intent: intent,
            results: results,
            summary: summary,
            timestamp: Date()
        )

        lastSearch = result
        isSearching = false
        searchProgress = ""

        return result
    }

    // MARK: - Query Analysis

    private func analyzeQueryIntent(_ query: String) async -> SearchIntent {
        let lowerQuery = query.lowercased()

        // Check for behavioral patterns
        let behavioralPatterns = [
            "promised", "didn't deliver", "ignored", "unanswered",
            "started positive", "turned negative", "escalated"
        ]

        if behavioralPatterns.contains(where: { lowerQuery.contains($0) }) {
            return SearchIntent(
                searchStrategy: .behavioral,
                extractedCriteria: [:],
                behaviorPattern: query,
                comparison: nil
            )
        }

        // Check for comparisons
        if lowerQuery.contains("compare") || lowerQuery.contains("versus") || lowerQuery.contains("vs") {
            return SearchIntent(
                searchStrategy: .comparative,
                extractedCriteria: [:],
                behaviorPattern: nil,
                comparison: query
            )
        }

        // Check for specific criteria
        var criteria: [String: String] = [:]

        // Extract sender
        if let senderMatch = query.range(of: #"from\s+(\w+)"#, options: .regularExpression) {
            let match = String(query[senderMatch])
            criteria["from"] = match.replacingOccurrences(of: "from ", with: "")
        }

        // Extract date
        let datePatterns = ["last week", "last month", "this week", "yesterday", "today"]
        for pattern in datePatterns {
            if lowerQuery.contains(pattern) {
                criteria["date"] = pattern
                break
            }
        }

        // Extract topic
        if let aboutMatch = query.range(of: #"about\s+(.+?)(\s+from|\s+with|$)"#, options: .regularExpression) {
            let match = String(query[aboutMatch])
            criteria["topic"] = match.replacingOccurrences(of: "about ", with: "")
                .replacingOccurrences(of: " from", with: "")
                .replacingOccurrences(of: " with", with: "")
        }

        if !criteria.isEmpty {
            return SearchIntent(
                searchStrategy: .criteria,
                extractedCriteria: criteria,
                behaviorPattern: nil,
                comparison: nil
            )
        }

        // Default to semantic search
        return SearchIntent(
            searchStrategy: .semantic,
            extractedCriteria: [:],
            behaviorPattern: nil,
            comparison: nil
        )
    }

    // MARK: - Search Implementations

    private func semanticSearch(query: String, emails: [Email]) async -> [Email] {
        if let vectorDB = vectorDB {
            let results = await vectorDB.search(query: query)
            let emailIds = Set(results.map { $0.emailId })
            return emails.filter { emailIds.contains($0.id.uuidString) }
        }

        // Fallback to keyword search
        let keywords = extractKeywords(from: query)
        return emails.filter { email in
            let content = (email.subject + " " + email.body).lowercased()
            return keywords.contains { content.contains($0.lowercased()) }
        }
    }

    private func criteriaSearch(criteria: [String: String], emails: [Email]) -> [Email] {
        var filtered = emails

        if let from = criteria["from"] {
            filtered = filtered.filter { $0.from.lowercased().contains(from.lowercased()) }
        }

        if let topic = criteria["topic"] {
            filtered = filtered.filter { email in
                email.subject.lowercased().contains(topic.lowercased()) ||
                email.body.lowercased().contains(topic.lowercased())
            }
        }

        if let dateFilter = criteria["date"] {
            let now = Date()
            let calendar = Calendar.current

            var startDate: Date?
            switch dateFilter {
            case "today":
                startDate = calendar.startOfDay(for: now)
            case "yesterday":
                startDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
            case "this week":
                startDate = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
            case "last week":
                startDate = calendar.date(byAdding: .day, value: -7, to: now)
            case "last month":
                startDate = calendar.date(byAdding: .month, value: -1, to: now)
            default:
                break
            }

            if let start = startDate {
                filtered = filtered.filter { email in
                    guard let date = email.dateObject else { return false }
                    return date >= start
                }
            }
        }

        return filtered
    }

    private func behavioralSearch(behavior: String, emails: [Email]) async -> [Email] {
        // Use AI to identify emails matching behavioral pattern
        let sampleEmails = emails.prefix(100).map { email in
            "[\(email.id.uuidString)] From: \(email.from) | Subject: \(email.subject)"
        }.joined(separator: "\n")

        let prompt = """
        Find emails matching this behavioral pattern: "\(behavior)"

        EMAILS:
        \(sampleEmails)

        Return ONLY the IDs (in brackets) of emails that match, one per line.
        If none match, return "NONE".
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You identify emails matching behavioral patterns. Only return email IDs."
            )

            let matchedIds = response.components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    if let match = line.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
                        return String(line[match])
                            .replacingOccurrences(of: "[", with: "")
                            .replacingOccurrences(of: "]", with: "")
                    }
                    return nil
                }

            let matchedIdSet = Set(matchedIds)
            return emails.filter { matchedIdSet.contains($0.id.uuidString) }
        } catch {
            return []
        }
    }

    private func comparativeSearch(comparison: String, emails: [Email]) async -> [Email] {
        // For comparative searches, return both sets of emails for comparison
        let keywords = extractKeywords(from: comparison)
        return emails.filter { email in
            let content = (email.subject + " " + email.body).lowercased()
            return keywords.contains { content.contains($0.lowercased()) }
        }
    }

    // MARK: - Pattern Searches

    private func findUnkeptPromises(in emails: [Email]) async -> [Email] {
        let promiseIndicators = ["will send", "i'll get", "will have", "promise", "by friday", "by monday"]

        return emails.filter { email in
            let lowerBody = email.body.lowercased()
            return promiseIndicators.contains { lowerBody.contains($0) }
        }
    }

    private func findSentimentDecline(in emails: [Email]) async -> [Email] {
        // Find emails where tone became more negative
        let negativeIndicators = ["disappointed", "concerned", "frustrated", "issue", "problem"]

        return emails.filter { email in
            let lowerBody = email.body.lowercased()
            return negativeIndicators.filter { lowerBody.contains($0) }.count >= 2
        }
    }

    private func findIgnoredRequests(in emails: [Email]) async -> [Email] {
        let requestIndicators = ["please respond", "waiting for", "need your", "can you confirm", "let me know"]

        return emails.filter { email in
            let lowerBody = email.body.lowercased()
            return requestIndicators.contains { lowerBody.contains($0) }
        }
    }

    private func findEscalatingTension(in emails: [Email]) async -> [Email] {
        let tensionIndicators = ["escalate", "unacceptable", "final notice", "immediately", "urgent"]

        return emails.filter { email in
            let content = (email.subject + " " + email.body).lowercased()
            return tensionIndicators.contains { content.contains($0) }
        }
    }

    private func findRecurringTopics(in emails: [Email]) -> [Email] {
        // Find subjects that appear frequently
        var subjectCounts: [String: [Email]] = [:]

        for email in emails {
            let normalizedSubject = normalizeSubject(email.subject)
            subjectCounts[normalizedSubject, default: []].append(email)
        }

        return subjectCounts.filter { $0.value.count >= 5 }.flatMap { $0.value }
    }

    private func findMissedDeadlines(in emails: [Email]) -> [Email] {
        let deadlineIndicators = ["overdue", "missed deadline", "late", "past due", "was due"]

        return emails.filter { email in
            let content = (email.subject + " " + email.body).lowercased()
            return deadlineIndicators.contains { content.contains($0) }
        }
    }

    // MARK: - Summary Generation

    private func generateSearchSummary(query: String, results: [Email]) async -> String {
        guard !results.isEmpty else {
            return "No emails found matching your search."
        }

        let resultSummary = results.prefix(10).map { email in
            "- \(email.subject) (from \(extractName(from: email.from)), \(email.date))"
        }.joined(separator: "\n")

        let prompt = """
        Summarize these search results for the query: "\(query)"

        Found \(results.count) emails:
        \(resultSummary)

        Provide a 2-3 sentence summary of what was found.
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You summarize email search results concisely."
            )
        } catch {
            return "Found \(results.count) emails matching your search."
        }
    }

    private func generatePatternSummary(pattern: SearchPattern, results: [Email]) async -> String {
        guard !results.isEmpty else {
            return "No emails found matching the pattern: \(pattern.description)"
        }

        return "Found \(results.count) emails matching '\(pattern.description)'. Most recent from \(extractName(from: results.first!.from))."
    }

    // MARK: - Helpers

    private func extractKeywords(from text: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
                             "find", "search", "show", "get", "me", "emails", "email", "all"])

        return text.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !stopWords.contains($0) }
    }

    private func normalizeSubject(_ subject: String) -> String {
        return subject.lowercased()
            .replacingOccurrences(of: #"^(re:|fw:|fwd:)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func extractName(from email: String) -> String {
        if let nameMatch = email.range(of: #"^[^<]+"#, options: .regularExpression) {
            let name = String(email[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name
            }
        }
        return email
    }
}

// MARK: - Supporting Types

struct SearchIntent {
    let searchStrategy: SearchStrategy
    let extractedCriteria: [String: String]
    let behaviorPattern: String?
    let comparison: String?
}

enum SearchStrategy: String {
    case semantic = "Semantic Search"
    case criteria = "Criteria-Based Search"
    case behavioral = "Behavioral Pattern Search"
    case comparative = "Comparative Analysis"
}

enum SearchPattern: String, CaseIterable {
    case unkeptPromises = "unkept_promises"
    case sentimentDecline = "sentiment_decline"
    case ignoredRequests = "ignored_requests"
    case escalatingTension = "escalating_tension"
    case recurringTopics = "recurring_topics"
    case deadlinesMissed = "missed_deadlines"

    var description: String {
        switch self {
        case .unkeptPromises: return "Promises that weren't kept"
        case .sentimentDecline: return "Conversations that turned negative"
        case .ignoredRequests: return "Requests that were ignored"
        case .escalatingTension: return "Escalating tension"
        case .recurringTopics: return "Recurring discussion topics"
        case .deadlinesMissed: return "Missed deadlines"
        }
    }
}

struct AgentSearchResult: Identifiable {
    let id = UUID()
    let query: String
    let intent: SearchIntent
    let results: [Email]
    let summary: String
    let timestamp: Date
}
