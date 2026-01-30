//
//  ThreadSummarizer.swift
//  MBox Explorer
//
//  Smart email thread and batch summarization
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Smart email summarization with thread awareness
class ThreadSummarizer: ObservableObject {
    static let shared = ThreadSummarizer()

    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var currentTask = ""

    private let llm = LocalLLM.shared

    // MARK: - Single Email Summary

    /// Generate a TL;DR for a single email
    func summarizeEmail(_ email: Email) async throws -> EmailSummary {
        await MainActor.run {
            isProcessing = true
            currentTask = "Summarizing email..."
        }

        defer {
            Task { @MainActor in
                isProcessing = false
                currentTask = ""
            }
        }

        let prompt = """
        Summarize this email in 2-3 sentences. Focus on:
        - Main topic/purpose
        - Key points or requests
        - Any action items

        From: \(email.from)
        Subject: \(email.subject)
        Date: \(email.date)

        Content:
        \(String(email.body.prefix(3000)))

        Summary:
        """

        let response = await llm.summarize(content: prompt)

        return EmailSummary(
            emailId: email.id,
            shortSummary: response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            keyPoints: extractKeyPoints(from: response),
            generatedAt: Date()
        )
    }

    // MARK: - Thread Summary

    /// Summarize an entire email thread
    func summarizeThread(_ emails: [Email]) async throws -> ThreadSummary {
        guard !emails.isEmpty else {
            throw SummaryError.emptyThread
        }

        await MainActor.run {
            isProcessing = true
            currentTask = "Summarizing thread (\(emails.count) emails)..."
        }

        defer {
            Task { @MainActor in
                isProcessing = false
                currentTask = ""
            }
        }

        // Sort by date
        let sortedEmails = emails.sorted { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }

        // Build thread context
        var threadContext = ""
        for (index, email) in sortedEmails.enumerated() {
            threadContext += """

            --- Email \(index + 1) of \(sortedEmails.count) ---
            From: \(email.from)
            Date: \(email.date)
            Subject: \(email.subject)

            \(String(email.body.prefix(1000)))

            """
        }

        let prompt = """
        Summarize this email thread conversation. Include:
        1. Main topic and context
        2. Key discussion points in order
        3. Decisions made or conclusions reached
        4. Outstanding questions or action items
        5. Participants and their roles

        Thread:
        \(threadContext.prefix(8000))

        Thread Summary:
        """

        let response = await llm.summarize(content: prompt)

        return ThreadSummary(
            threadId: sortedEmails.first?.messageId ?? UUID().uuidString,
            subject: sortedEmails.first?.subject ?? "Unknown",
            emailCount: emails.count,
            participants: Array(Set(emails.map { $0.from })),
            dateRange: DateRange(
                start: sortedEmails.first?.dateObject ?? Date(),
                end: sortedEmails.last?.dateObject ?? Date()
            ),
            summary: response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            keyPoints: extractKeyPoints(from: response),
            generatedAt: Date()
        )
    }

    // MARK: - Batch Summarization

    /// Generate daily digest from emails
    func generateDailyDigest(emails: [Email], date: Date) async throws -> DailyDigest {
        let calendar = Calendar.current
        let dayEmails = emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            return calendar.isDate(emailDate, inSameDayAs: date)
        }

        guard !dayEmails.isEmpty else {
            throw SummaryError.noEmailsForPeriod
        }

        await MainActor.run {
            isProcessing = true
            currentTask = "Generating daily digest..."
        }

        defer {
            Task { @MainActor in
                isProcessing = false
                currentTask = ""
            }
        }

        // Group by sender
        let bySender = Dictionary(grouping: dayEmails, by: { $0.from })

        var emailSummaries = ""
        for email in dayEmails.prefix(20) {
            emailSummaries += """
            • From: \(email.from)
              Subject: \(email.subject)
              Preview: \(String(email.body.prefix(200)).replacingOccurrences(of: "\n", with: " "))

            """
        }

        let prompt = """
        Create a daily email digest for \(formatDate(date)).

        Statistics:
        - Total emails: \(dayEmails.count)
        - Unique senders: \(bySender.count)

        Emails:
        \(emailSummaries)

        Create a brief digest with:
        1. Overview of the day's email activity
        2. Important/priority items
        3. Topics discussed
        4. Items that may need follow-up

        Daily Digest:
        """

        let response = await llm.summarize(content: prompt)

        return DailyDigest(
            date: date,
            totalEmails: dayEmails.count,
            uniqueSenders: bySender.count,
            topSenders: bySender.sorted { $0.value.count > $1.value.count }.prefix(5).map { ($0.key, $0.value.count) },
            summary: response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            generatedAt: Date()
        )
    }

    /// Generate weekly digest
    func generateWeeklyDigest(emails: [Email], weekOf: Date) async throws -> WeeklyDigest {
        let calendar = Calendar.current
        guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekOf)),
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            throw SummaryError.invalidDateRange
        }

        let weekEmails = emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            return emailDate >= weekStart && emailDate < weekEnd
        }

        await MainActor.run {
            isProcessing = true
            currentTask = "Generating weekly digest..."
            progress = 0
        }

        defer {
            Task { @MainActor in
                isProcessing = false
                currentTask = ""
            }
        }

        // Group by day
        let byDay = Dictionary(grouping: weekEmails) { email -> String in
            guard let date = email.dateObject else { return "Unknown" }
            return formatDate(date)
        }

        // Group by sender
        let bySender = Dictionary(grouping: weekEmails, by: { $0.from })

        // Extract subjects for topic analysis
        let subjects = weekEmails.map { $0.subject }.joined(separator: "\n")

        let prompt = """
        Create a weekly email digest for the week of \(formatDate(weekStart)).

        Statistics:
        - Total emails: \(weekEmails.count)
        - Days with activity: \(byDay.count)
        - Unique correspondents: \(bySender.count)

        Top subjects this week:
        \(subjects.prefix(2000))

        Create a comprehensive weekly summary with:
        1. Overview of the week
        2. Busiest days and why
        3. Main topics/themes discussed
        4. Key correspondents and context
        5. Notable items or follow-ups needed

        Weekly Digest:
        """

        let response = await llm.summarize(content: prompt)

        return WeeklyDigest(
            weekStart: weekStart,
            weekEnd: weekEnd,
            totalEmails: weekEmails.count,
            emailsByDay: byDay.mapValues { $0.count },
            topSenders: bySender.sorted { $0.value.count > $1.value.count }.prefix(10).map { ($0.key, $0.value.count) },
            summary: response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            generatedAt: Date()
        )
    }

    /// Executive summary of entire mailbox
    func generateExecutiveSummary(emails: [Email]) async throws -> ExecutiveSummary {
        guard !emails.isEmpty else {
            throw SummaryError.emptyMailbox
        }

        await MainActor.run {
            isProcessing = true
            currentTask = "Generating executive summary..."
        }

        defer {
            Task { @MainActor in
                isProcessing = false
                currentTask = ""
            }
        }

        let sortedEmails = emails.sorted { ($0.dateObject ?? .distantPast) < ($1.dateObject ?? .distantPast) }

        // Calculate statistics
        let bySender = Dictionary(grouping: emails, by: { $0.from })
        let dateRange = DateRange(
            start: sortedEmails.first?.dateObject ?? Date(),
            end: sortedEmails.last?.dateObject ?? Date()
        )

        // Sample emails for context
        let sampleEmails = emails.shuffled().prefix(30).map { email in
            "• \(email.from): \(email.subject)"
        }.joined(separator: "\n")

        let prompt = """
        Create an executive summary of this email archive.

        Archive Statistics:
        - Total emails: \(emails.count)
        - Date range: \(formatDate(dateRange.start)) to \(formatDate(dateRange.end))
        - Unique correspondents: \(bySender.count)
        - Top sender: \(bySender.max(by: { $0.value.count < $1.value.count })?.key ?? "Unknown") (\(bySender.max(by: { $0.value.count < $1.value.count })?.value.count ?? 0) emails)

        Sample of subjects:
        \(sampleEmails)

        Create an executive summary covering:
        1. Overall purpose/nature of this mailbox
        2. Key themes and topics
        3. Main correspondents and their roles
        4. Time period and activity patterns
        5. Notable observations

        Executive Summary:
        """

        let response = await llm.summarize(content: prompt)

        return ExecutiveSummary(
            totalEmails: emails.count,
            dateRange: dateRange,
            uniqueCorrespondents: bySender.count,
            topCorrespondents: bySender.sorted { $0.value.count > $1.value.count }.prefix(10).map { ($0.key, $0.value.count) },
            summary: response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            generatedAt: Date()
        )
    }

    // MARK: - Helpers

    private func extractKeyPoints(from text: String) -> [String] {
        // Extract bullet points or numbered items
        let lines = text.components(separatedBy: .newlines)
        return lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") ||
                   trimmed.first?.isNumber == true
        }.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Models

struct EmailSummary {
    let emailId: UUID
    let shortSummary: String
    let keyPoints: [String]
    let generatedAt: Date
}

struct ThreadSummary {
    let threadId: String
    let subject: String
    let emailCount: Int
    let participants: [String]
    let dateRange: DateRange
    let summary: String
    let keyPoints: [String]
    let generatedAt: Date
}

struct DateRange {
    let start: Date
    let end: Date
}

struct DailyDigest {
    let date: Date
    let totalEmails: Int
    let uniqueSenders: Int
    let topSenders: [(String, Int)]
    let summary: String
    let generatedAt: Date
}

struct WeeklyDigest {
    let weekStart: Date
    let weekEnd: Date
    let totalEmails: Int
    let emailsByDay: [String: Int]
    let topSenders: [(String, Int)]
    let summary: String
    let generatedAt: Date
}

struct ExecutiveSummary {
    let totalEmails: Int
    let dateRange: DateRange
    let uniqueCorrespondents: Int
    let topCorrespondents: [(String, Int)]
    let summary: String
    let generatedAt: Date
}

enum SummaryError: LocalizedError {
    case emptyThread
    case emptyMailbox
    case noEmailsForPeriod
    case invalidDateRange
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyThread: return "No emails in thread"
        case .emptyMailbox: return "No emails in mailbox"
        case .noEmailsForPeriod: return "No emails found for this period"
        case .invalidDateRange: return "Invalid date range"
        case .generationFailed(let reason): return "Summary generation failed: \(reason)"
        }
    }
}
