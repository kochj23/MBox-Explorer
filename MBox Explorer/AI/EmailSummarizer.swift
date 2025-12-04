//
//  EmailSummarizer.swift
//  MBox Explorer
//
//  AI-powered email summarization
//  Author: Jordan Koch
//  Date: 2025-12-03
//

import Foundation

/// AI-powered email and thread summarization
class EmailSummarizer: ObservableObject {
    @Published var isProcessing = false
    @Published var lastSummary = ""

    private let llm: LocalLLM

    init(llm: LocalLLM) {
        self.llm = llm
    }

    /// Summarize a single email
    func summarizeEmail(_ email: Email) async -> EmailSummary {
        isProcessing = true
        defer { isProcessing = false }

        let summary = await llm.summarize(content: email.body)

        let actionItems = extractActionItems(from: email.body)
        let keyPoints = extractKeyPoints(from: email.body)

        return EmailSummary(
            email: email,
            summary: summary,
            actionItems: actionItems,
            keyPoints: keyPoints,
            sentiment: analyzeSentiment(email.body)
        )
    }

    /// Summarize an email thread
    func summarizeThread(_ emails: [Email]) async -> ThreadSummary {
        isProcessing = true
        defer { isProcessing = false }

        // Combine all emails in thread
        let combinedContent = emails.map { email in
            "From: \(email.from)\nDate: \(email.date)\nSubject: \(email.subject)\n\n\(email.body)"
        }.joined(separator: "\n\n---\n\n")

        let summary = await llm.summarize(content: combinedContent)

        let participants = Set(emails.map { $0.from })
        let dateRange = (emails.map { $0.date }.min()!, emails.map { $0.date }.max()!)

        return ThreadSummary(
            threadSubject: emails.first?.subject ?? "Unknown",
            summary: summary,
            participants: Array(participants),
            emailCount: emails.count,
            dateRange: dateRange,
            keyDecisions: extractDecisions(from: combinedContent)
        )
    }

    /// Generate daily digest
    func generateDailyDigest(emails: [Email], date: Date) async -> DailyDigest {
        let emailsForDay = emails.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }

        let summaries = await withTaskGroup(of: String.self) { group in
            for email in emailsForDay.prefix(20) {  // Limit to avoid overwhelming
                group.addTask {
                    await self.llm.summarize(content: email.body)
                }
            }

            var results: [String] = []
            for await summary in group {
                results.append(summary)
            }
            return results
        }

        return DailyDigest(
            date: date,
            emailCount: emailsForDay.count,
            topSenders: topSenders(from: emailsForDay, count: 5),
            summaries: summaries,
            actionItems: extractActionItems(from: emailsForDay.map { $0.body }.joined(separator: "\n"))
        )
    }

    // MARK: - Private Helpers

    private func extractActionItems(from text: String) -> [String] {
        var items: [String] = []

        // Look for common action item patterns
        let patterns = [
            "TODO:",
            "Action item:",
            "Next steps:",
            "Please ",
            "Could you ",
            "Need to ",
            "Must "
        ]

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for pattern in patterns {
                if trimmed.lowercased().contains(pattern.lowercased()) && trimmed.count < 200 {
                    items.append(trimmed)
                    break
                }
            }
        }

        return Array(items.prefix(10))  // Limit to 10
    }

    private func extractKeyPoints(from text: String) -> [String] {
        // Simple key point extraction (can be enhanced with NLP)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 20 && $0.count < 200 }

        return Array(sentences.prefix(5))
    }

    private func extractDecisions(from text: String) -> [String] {
        var decisions: [String] = []

        let decisionWords = ["decided", "agreed", "approved", "confirmed", "concluded"]
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let lower = line.lowercased()
            for word in decisionWords {
                if lower.contains(word) && line.count < 200 {
                    decisions.append(line.trimmingCharacters(in: .whitespaces))
                    break
                }
            }
        }

        return Array(decisions.prefix(5))
    }

    private func analyzeSentiment(_ text: String) -> Sentiment {
        // Simple sentiment analysis (can be enhanced with ML)
        let lowerText = text.lowercased()

        let positiveWords = ["great", "excellent", "good", "happy", "pleased", "wonderful", "fantastic"]
        let negativeWords = ["bad", "terrible", "awful", "problem", "issue", "concern", "disappointed"]
        let urgentWords = ["urgent", "asap", "immediately", "critical", "emergency"]

        let positiveCount = positiveWords.filter { lowerText.contains($0) }.count
        let negativeCount = negativeWords.filter { lowerText.contains($0) }.count
        let urgentCount = urgentWords.filter { lowerText.contains($0) }.count

        if urgentCount > 0 {
            return .urgent
        } else if positiveCount > negativeCount + 1 {
            return .positive
        } else if negativeCount > positiveCount + 1 {
            return .negative
        } else {
            return .neutral
        }
    }

    private func topSenders(from emails: [Email], count: Int) -> [(String, Int)] {
        let senderCounts = Dictionary(grouping: emails, by: { $0.from })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }

        return Array(senderCounts.prefix(count))
    }
}

// MARK: - Data Models

struct EmailSummary: Identifiable {
    let id = UUID()
    let email: Email
    let summary: String
    let actionItems: [String]
    let keyPoints: [String]
    let sentiment: Sentiment
}

struct ThreadSummary: Identifiable {
    let id = UUID()
    let threadSubject: String
    let summary: String
    let participants: [String]
    let emailCount: Int
    let dateRange: (Date, Date)
    let keyDecisions: [String]
}

struct DailyDigest: Identifiable {
    let id = UUID()
    let date: Date
    let emailCount: Int
    let topSenders: [(String, Int)]
    let summaries: [String]
    let actionItems: [String]
}

enum Sentiment: String {
    case positive = "Positive"
    case negative = "Negative"
    case neutral = "Neutral"
    case urgent = "Urgent"

    var color: Color {
        switch self {
        case .positive: return .green
        case .negative: return .red
        case .neutral: return .gray
        case .urgent: return .orange
        }
    }

    var icon: String {
        switch self {
        case .positive: return "hand.thumbsup.fill"
        case .negative: return "hand.thumbsdown.fill"
        case .neutral: return "minus.circle.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
}

import SwiftUI
