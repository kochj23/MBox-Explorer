//
//  AutoTagger.swift
//  MBox Explorer
//
//  ML-powered automatic email tagging
//  Author: Jordan Koch
//  Date: 2025-12-03
//

import Foundation

enum EmailCategory: String, CaseIterable {
    case work = "Work"
    case personal = "Personal"
    case finance = "Finance"
    case travel = "Travel"
    case legal = "Legal"
    case marketing = "Marketing"
    case support = "Support"
    case newsletter = "Newsletter"
    case receipts = "Receipts"
    case social = "Social"
}

enum EmailPriority: String {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

struct EmailTags {
    var categories: [EmailCategory] = []
    var priority: EmailPriority = .medium
    var sentiment: Sentiment = .neutral
    var hasActionItems: Bool = false
    var needsResponse: Bool = false
}

class AutoTagger: ObservableObject {
    @Published var isProcessing = false

    func tagEmail(_ email: Email) async -> EmailTags {
        var tags = EmailTags()

        // Categorize
        tags.categories = categorize(email)

        // Determine priority
        tags.priority = determinePriority(email)

        // Analyze sentiment
        tags.sentiment = analyzeSentiment(email.body)

        // Check for action items
        tags.hasActionItems = hasActionItems(email.body)

        // Check if needs response
        tags.needsResponse = needsResponse(email.body)

        return tags
    }

    func tagBatch(_ emails: [Email]) async -> [Email.ID: EmailTags] {
        await withTaskGroup(of: (Email.ID, EmailTags).self) { group in
            for email in emails {
                group.addTask {
                    let tags = await self.tagEmail(email)
                    return (email.id, tags)
                }
            }

            var results: [Email.ID: EmailTags] = [:]
            for await (id, tags) in group {
                results[id] = tags
            }
            return results
        }
    }

    private func categorize(_ email: Email) -> [EmailCategory] {
        var categories: [EmailCategory] = []

        let content = (email.subject + " " + email.body).lowercased()

        // Work
        if content.contains("meeting") || content.contains("project") || content.contains("deadline") {
            categories.append(.work)
        }

        // Finance
        if content.contains("invoice") || content.contains("payment") || content.contains("$") || content.contains("budget") {
            categories.append(.finance)
        }

        // Travel
        if content.contains("flight") || content.contains("hotel") || content.contains("reservation") || content.contains("booking") {
            categories.append(.travel)
        }

        // Legal
        if content.contains("contract") || content.contains("agreement") || content.contains("legal") || content.contains("nda") {
            categories.append(.legal)
        }

        // Newsletter
        if content.contains("unsubscribe") || email.from.contains("noreply") || email.from.contains("newsletter") {
            categories.append(.newsletter)
        }

        // Receipts
        if content.contains("receipt") || content.contains("order confirmation") || content.contains("purchase") {
            categories.append(.receipts)
        }

        return categories.isEmpty ? [.personal] : categories
    }

    private func determinePriority(_ email: Email) -> EmailPriority {
        let content = (email.subject + " " + email.body).lowercased()

        let highPriorityWords = ["urgent", "asap", "critical", "important", "deadline", "emergency"]
        let lowPriorityWords = ["fyi", "newsletter", "update", "notification"]

        for word in highPriorityWords {
            if content.contains(word) {
                return .high
            }
        }

        for word in lowPriorityWords {
            if content.contains(word) {
                return .low
            }
        }

        return .medium
    }

    private func analyzeSentiment(_ text: String) -> Sentiment {
        let lowerText = text.lowercased()

        let positiveWords = ["great", "excellent", "good", "happy", "pleased", "wonderful"]
        let negativeWords = ["bad", "terrible", "problem", "issue", "concern", "disappointed"]
        let urgentWords = ["urgent", "asap", "immediately", "critical"]

        let positiveCount = positiveWords.filter { lowerText.contains($0) }.count
        let negativeCount = negativeWords.filter { lowerText.contains($0) }.count
        let urgentCount = urgentWords.filter { lowerText.contains($0) }.count

        if urgentCount > 0 {
            return .urgent
        } else if positiveCount > negativeCount + 1 {
            return .positive
        } else if negativeCount > positiveCount + 1 {
            return .negative
        }
        return .neutral
    }

    private func hasActionItems(_ text: String) -> Bool {
        let patterns = ["TODO:", "Action item:", "Please ", "Could you ", "Need to "]
        return patterns.contains { text.contains($0) }
    }

    private func needsResponse(_ text: String) -> Bool {
        let indicators = ["?", "please respond", "let me know", "could you", "can you"]
        return indicators.contains { text.lowercased().contains($0) }
    }
}
