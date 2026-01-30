//
//  SmartSuggestions.swift
//  MBox Explorer
//
//  Provides proactive AI-powered suggestions while browsing emails
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Generates proactive suggestions based on email context
@MainActor
class SmartSuggestionsEngine: ObservableObject {
    static let shared = SmartSuggestionsEngine()

    @Published var activeSuggestions: [SmartSuggestion] = []
    @Published var isAnalyzing = false

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared

    private init() {}

    // MARK: - Suggestion Generation

    /// Generate suggestions for a selected email
    func generateSuggestions(for email: Email, allEmails: [Email]) async -> [SmartSuggestion] {
        isAnalyzing = true
        var suggestions: [SmartSuggestion] = []

        // Check for long thread
        if let threadSuggestion = checkForLongThread(email, allEmails) {
            suggestions.append(threadSuggestion)
        }

        // Check for similar discussions
        if let similarSuggestion = await checkForSimilarDiscussions(email, allEmails) {
            suggestions.append(similarSuggestion)
        }

        // Check for tone changes
        if let toneSuggestion = await checkForToneChange(email, allEmails) {
            suggestions.append(toneSuggestion)
        }

        // Check for action items
        if let actionSuggestion = checkForActionItems(email) {
            suggestions.append(actionSuggestion)
        }

        // Check for follow-up needed
        if let followUpSuggestion = checkForFollowUpNeeded(email, allEmails) {
            suggestions.append(followUpSuggestion)
        }

        // Check for duplicate discussions
        if let duplicateSuggestion = checkForDuplicateDiscussion(email, allEmails) {
            suggestions.append(duplicateSuggestion)
        }

        activeSuggestions = suggestions
        isAnalyzing = false

        return suggestions
    }

    /// Generate suggestions for a thread
    func generateThreadSuggestions(thread: [Email]) async -> [SmartSuggestion] {
        var suggestions: [SmartSuggestion] = []

        // Thread summary suggestion for long threads
        if thread.count >= 10 {
            suggestions.append(SmartSuggestion(
                suggestionType: .summarize,
                title: "Long thread detected",
                description: "This thread has \(thread.count) messages. Would you like a summary?",
                actionLabel: "Summarize Thread",
                relatedEmailIds: thread.map { $0.id.uuidString },
                confidence: 0.9
            ))
        }

        // Multiple action items
        let actionItemCount = thread.filter { hasActionItems($0) }.count
        if actionItemCount >= 3 {
            suggestions.append(SmartSuggestion(
                suggestionType: .actionItems,
                title: "Multiple action items",
                description: "Found potential action items in \(actionItemCount) messages",
                actionLabel: "Extract Action Items",
                relatedEmailIds: thread.map { $0.id.uuidString },
                confidence: 0.8
            ))
        }

        return suggestions
    }

    /// Dismiss a suggestion
    func dismissSuggestion(_ suggestion: SmartSuggestion) {
        if let index = activeSuggestions.firstIndex(where: { $0.id == suggestion.id }) {
            activeSuggestions[index].isDismissed = true
            activeSuggestions.remove(at: index)
        }
    }

    // MARK: - Individual Suggestion Checks

    private func checkForLongThread(_ email: Email, _ allEmails: [Email]) -> SmartSuggestion? {
        // Find thread members
        let normalizedSubject = normalizeSubject(email.subject)
        let threadEmails = allEmails.filter { normalizeSubject($0.subject) == normalizedSubject }

        if threadEmails.count >= 15 {
            return SmartSuggestion(
                suggestionType: .summarize,
                title: "Long conversation thread",
                description: "This thread has \(threadEmails.count) messages. Would you like a summary?",
                actionLabel: "Summarize",
                relatedEmailIds: threadEmails.map { $0.id.uuidString },
                confidence: 0.9
            )
        }

        return nil
    }

    private func checkForSimilarDiscussions(_ email: Email, _ allEmails: [Email]) async -> SmartSuggestion? {
        // Find emails with similar topics
        let keywords = extractKeywords(from: email.subject + " " + email.body.prefix(200).description)

        guard keywords.count >= 2 else { return nil }

        var similarEmails: [Email] = []
        for otherEmail in allEmails {
            guard otherEmail.id != email.id else { continue }

            let otherKeywords = extractKeywords(from: otherEmail.subject + " " + otherEmail.body.prefix(200).description)
            let overlap = Set(keywords).intersection(Set(otherKeywords))

            if overlap.count >= 2 {
                // Check if dates are different enough to be separate discussions
                if let date1 = email.dateObject, let date2 = otherEmail.dateObject {
                    let daysBetween = abs(Calendar.current.dateComponents([.day], from: date1, to: date2).day ?? 0)
                    if daysBetween >= 30 { // At least a month apart
                        similarEmails.append(otherEmail)
                    }
                }
            }
        }

        if !similarEmails.isEmpty {
            let oldestSimilar = similarEmails.min { ($0.dateObject ?? Date()) < ($1.dateObject ?? Date()) }
            let dateText = oldestSimilar?.dateObject.map { formatMonth($0) } ?? "earlier"

            return SmartSuggestion(
                suggestionType: .compare,
                title: "Similar discussion found",
                description: "A similar discussion happened in \(dateText). Would you like to compare?",
                actionLabel: "Compare Discussions",
                relatedEmailIds: [email.id.uuidString] + similarEmails.prefix(3).map { $0.id.uuidString },
                confidence: 0.7
            )
        }

        return nil
    }

    private func checkForToneChange(_ email: Email, _ allEmails: [Email]) async -> SmartSuggestion? {
        let sender = normalizeEmail(email.from)

        // Get recent emails from same sender
        let senderEmails = allEmails.filter { normalizeEmail($0.from) == sender }
            .sorted { ($0.dateObject ?? Date()) < ($1.dateObject ?? Date()) }

        guard senderEmails.count >= 5 else { return nil }

        // Simple sentiment analysis
        let recentEmails = senderEmails.suffix(3)
        let olderEmails = senderEmails.prefix(senderEmails.count - 3)

        let recentSentiment = recentEmails.map { analyzeSentiment($0.body) }.reduce(0, +) / Double(recentEmails.count)
        let olderSentiment = olderEmails.map { analyzeSentiment($0.body) }.reduce(0, +) / Double(olderEmails.count)

        let change = recentSentiment - olderSentiment

        if abs(change) >= 0.4 {
            let direction = change > 0 ? "more positive" : "more formal/distant"
            return SmartSuggestion(
                suggestionType: .toneChange,
                title: "Tone change detected",
                description: "This sender's recent emails seem \(direction) than usual",
                actionLabel: "Analyze Relationship",
                relatedEmailIds: senderEmails.suffix(5).map { $0.id.uuidString },
                confidence: 0.6
            )
        }

        return nil
    }

    private func checkForActionItems(_ email: Email) -> SmartSuggestion? {
        let actionPhrases = ["please", "can you", "could you", "would you", "need you to",
                            "action required", "todo", "deadline", "by friday", "asap"]

        let lowerBody = email.body.lowercased()
        let matchCount = actionPhrases.filter { lowerBody.contains($0) }.count

        if matchCount >= 2 {
            return SmartSuggestion(
                suggestionType: .actionItems,
                title: "Action items detected",
                description: "\(matchCount) potential action items found in this email",
                actionLabel: "Extract Actions",
                relatedEmailIds: [email.id.uuidString],
                confidence: Double(matchCount) / 10.0 + 0.5
            )
        }

        return nil
    }

    private func checkForFollowUpNeeded(_ email: Email, _ allEmails: [Email]) -> SmartSuggestion? {
        let lowerBody = email.body.lowercased()

        // Check if this email asks for a response
        let responseNeeded = lowerBody.contains("let me know") ||
                            lowerBody.contains("please respond") ||
                            lowerBody.contains("waiting for") ||
                            lowerBody.contains("your thoughts")

        guard responseNeeded, let emailDate = email.dateObject else { return nil }

        // Check if there's a reply in the thread
        let normalizedSubject = normalizeSubject(email.subject)
        let laterEmails = allEmails.filter { otherEmail in
            guard let otherDate = otherEmail.dateObject else { return false }
            return otherDate > emailDate && normalizeSubject(otherEmail.subject) == normalizedSubject
        }

        // If no reply in 3+ days, suggest follow-up
        let daysSince = Calendar.current.dateComponents([.day], from: emailDate, to: Date()).day ?? 0

        if laterEmails.isEmpty && daysSince >= 3 {
            return SmartSuggestion(
                suggestionType: .followUp,
                title: "Follow-up may be needed",
                description: "This email asked for a response \(daysSince) days ago with no visible reply",
                actionLabel: "Draft Follow-up",
                relatedEmailIds: [email.id.uuidString],
                confidence: 0.7
            )
        }

        return nil
    }

    private func checkForDuplicateDiscussion(_ email: Email, _ allEmails: [Email]) -> SmartSuggestion? {
        let keywords = extractKeywords(from: email.subject)
        guard keywords.count >= 2 else { return nil }

        // Find other threads with very similar subjects
        var seenSubjects: Set<String> = []
        var duplicates: [Email] = []

        for otherEmail in allEmails {
            guard otherEmail.id != email.id else { continue }

            let otherKeywords = extractKeywords(from: otherEmail.subject)
            let overlap = Set(keywords).intersection(Set(otherKeywords))

            if overlap.count >= 2 {
                let normalizedOther = normalizeSubject(otherEmail.subject)
                let normalizedCurrent = normalizeSubject(email.subject)

                // Check if different thread (not just Re: chain)
                if normalizedOther != normalizedCurrent && !seenSubjects.contains(normalizedOther) {
                    seenSubjects.insert(normalizedOther)
                    duplicates.append(otherEmail)
                }
            }
        }

        if duplicates.count >= 2 {
            return SmartSuggestion(
                suggestionType: .duplicate,
                title: "Multiple related threads",
                description: "Found \(duplicates.count) other threads on similar topics",
                actionLabel: "View Related",
                relatedEmailIds: [email.id.uuidString] + duplicates.prefix(3).map { $0.id.uuidString },
                confidence: 0.6
            )
        }

        return nil
    }

    // MARK: - Helpers

    private func hasActionItems(_ email: Email) -> Bool {
        let lowerBody = email.body.lowercased()
        return lowerBody.contains("please") || lowerBody.contains("todo") ||
               lowerBody.contains("action") || lowerBody.contains("deadline")
    }

    private func normalizeSubject(_ subject: String) -> String {
        return subject
            .lowercased()
            .replacingOccurrences(of: #"^(re:|fw:|fwd:)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func normalizeEmail(_ email: String) -> String {
        if let emailMatch = email.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            return String(email[emailMatch]).lowercased()
        }
        return email.lowercased()
    }

    private func extractKeywords(from text: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
                             "re:", "fw:", "fwd:", "from", "is", "are", "was", "were", "be", "been"])

        return text
            .lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 && !stopWords.contains($0) }
    }

    private func analyzeSentiment(_ text: String) -> Double {
        let positiveWords = Set(["thank", "great", "excellent", "good", "appreciate", "happy", "pleased"])
        let negativeWords = Set(["disappointed", "concern", "problem", "issue", "urgent", "sorry"])

        let words = text.lowercased().components(separatedBy: .whitespaces)
        var score = 0.0

        for word in words {
            if positiveWords.contains(where: { word.contains($0) }) { score += 0.1 }
            if negativeWords.contains(where: { word.contains($0) }) { score -= 0.1 }
        }

        return max(-1, min(1, score))
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}
