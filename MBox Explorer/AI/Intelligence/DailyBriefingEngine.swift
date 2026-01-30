//
//  DailyBriefingEngine.swift
//  MBox Explorer
//
//  Generates AI-powered daily briefings about email activity
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Generates intelligent daily briefings about email activity
@MainActor
class DailyBriefingEngine: ObservableObject {
    static let shared = DailyBriefingEngine()

    @Published var currentBriefing: DailyBriefing?
    @Published var isGenerating = false

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared
    private let commitmentTracker = CommitmentTracker.shared
    private let sentimentAnalyzer = SentimentAnalyzer.shared

    private init() {}

    // MARK: - Briefing Generation

    /// Generate a daily briefing based on email analysis
    func generateBriefing(emails: [Email], userEmail: String? = nil) async -> DailyBriefing {
        isGenerating = true

        let today = Date()
        let calendar = Calendar.current

        // Get recent emails (last 24 hours for daily, last 7 days for context)
        let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        let recentEmails = emails.filter { email in
            guard let date = email.dateObject else { return false }
            return date >= oneDayAgo
        }

        let weekEmails = emails.filter { email in
            guard let date = email.dateObject else { return false }
            return date >= sevenDaysAgo
        }

        // Generate each section
        async let needsResponse = identifyNeedsResponse(recentEmails, userEmail: userEmail)
        async let upcomingDeadlines = identifyUpcomingDeadlines()
        async let unusualActivity = identifyUnusualActivity(recentEmails, weekEmails)
        async let trendingTopics = identifyTrendingTopics(weekEmails)
        async let summary = generateSummary(recentEmails)

        let briefing = DailyBriefing(
            date: today,
            needsResponse: await needsResponse,
            upcomingDeadlines: await upcomingDeadlines,
            unusualActivity: await unusualActivity,
            trendingTopics: await trendingTopics,
            summary: await summary
        )

        currentBriefing = briefing
        isGenerating = false

        return briefing
    }

    /// Get a formatted text version of the briefing
    func getFormattedBriefing() -> String {
        guard let briefing = currentBriefing else {
            return "No briefing available. Generate one first."
        }

        var text = "# Daily Email Briefing\n"
        text += "**Generated:** \(formatDate(briefing.generatedAt))\n\n"

        // Summary
        if !briefing.summary.isEmpty {
            text += "## Summary\n\(briefing.summary)\n\n"
        }

        // Needs Response
        if !briefing.needsResponse.isEmpty {
            text += "## Emails Needing Response (\(briefing.needsResponse.count))\n"
            for item in briefing.needsResponse {
                let priority = item.priority == .high ? "[HIGH]" : ""
                text += "- \(priority) \(item.title): \(item.description)\n"
            }
            text += "\n"
        }

        // Upcoming Deadlines
        if !briefing.upcomingDeadlines.isEmpty {
            text += "## Upcoming Deadlines (\(briefing.upcomingDeadlines.count))\n"
            for item in briefing.upcomingDeadlines {
                text += "- \(item.title): \(item.description)\n"
            }
            text += "\n"
        }

        // Unusual Activity
        if !briefing.unusualActivity.isEmpty {
            text += "## Unusual Activity\n"
            for item in briefing.unusualActivity {
                text += "- \(item.title): \(item.description)\n"
            }
            text += "\n"
        }

        // Trending Topics
        if !briefing.trendingTopics.isEmpty {
            text += "## Trending Topics\n"
            text += briefing.trendingTopics.joined(separator: ", ") + "\n"
        }

        return text
    }

    // MARK: - Section Generators

    private func identifyNeedsResponse(_ emails: [Email], userEmail: String?) -> [BriefingItem] {
        var items: [BriefingItem] = []

        // Find emails that look like they need a response
        let responseIndicators = [
            "please respond", "please reply", "let me know", "your thoughts",
            "what do you think", "can you", "could you", "would you",
            "asap", "urgent", "?", "waiting for", "awaiting"
        ]

        for email in emails {
            let body = email.body.lowercased()
            let subject = email.subject.lowercased()

            // Skip if this is from the user
            if let userEmail = userEmail,
               email.from.lowercased().contains(userEmail.lowercased()) {
                continue
            }

            // Check for response indicators
            let needsResponse = responseIndicators.contains { indicator in
                body.contains(indicator) || subject.contains(indicator)
            }

            if needsResponse {
                let priority: BriefingPriority = subject.contains("urgent") || body.contains("asap") ? .high : .medium

                items.append(BriefingItem(
                    title: email.subject.prefix(50).description,
                    description: "From \(extractName(from: email.from)) - appears to need a response",
                    emailId: email.id.uuidString,
                    priority: priority,
                    actionRequired: true
                ))
            }
        }

        return items.sorted { $0.priority == .high && $1.priority != .high }
    }

    private func identifyUpcomingDeadlines() -> [BriefingItem] {
        let upcoming = commitmentTracker.getCommitmentsWithUpcomingDeadlines(within: 7)
        let overdue = commitmentTracker.getOverdueCommitments()

        var items: [BriefingItem] = []

        // Add overdue first (high priority)
        for commitment in overdue.prefix(5) {
            items.append(BriefingItem(
                title: "OVERDUE: \(commitment.description.prefix(40))",
                description: "Was due \(formatRelativeDate(commitment.deadline))",
                emailId: commitment.sourceEmailId,
                priority: .high,
                actionRequired: true
            ))
        }

        // Add upcoming
        for commitment in upcoming.prefix(5) {
            let daysText = commitment.daysUntilDeadline.map { "in \($0) day(s)" } ?? "soon"
            items.append(BriefingItem(
                title: commitment.description.prefix(40).description,
                description: "Due \(daysText)",
                emailId: commitment.sourceEmailId,
                priority: commitment.daysUntilDeadline ?? 7 <= 2 ? .high : .medium,
                actionRequired: true
            ))
        }

        return items
    }

    private func identifyUnusualActivity(_ recentEmails: [Email], _ weekEmails: [Email]) -> [BriefingItem] {
        var items: [BriefingItem] = []

        // Calculate daily averages
        let avgDailyCount = Double(weekEmails.count) / 7.0

        // Check if today is unusual
        if Double(recentEmails.count) > avgDailyCount * 1.5 {
            items.append(BriefingItem(
                title: "High email volume",
                description: "\(recentEmails.count) emails in last 24 hours (avg: \(Int(avgDailyCount)))",
                priority: .medium,
                actionRequired: false
            ))
        }

        // Check for unusual senders
        var senderCounts: [String: Int] = [:]
        for email in weekEmails {
            let sender = normalizeEmail(email.from)
            senderCounts[sender, default: 0] += 1
        }

        var recentSenderCounts: [String: Int] = [:]
        for email in recentEmails {
            let sender = normalizeEmail(email.from)
            recentSenderCounts[sender, default: 0] += 1
        }

        // Find senders with unusually high recent activity
        for (sender, recentCount) in recentSenderCounts {
            let weeklyCount = senderCounts[sender] ?? 0
            let avgDaily = Double(weeklyCount) / 7.0

            if Double(recentCount) > avgDaily * 3 && recentCount >= 3 {
                items.append(BriefingItem(
                    title: "Unusual activity from \(extractName(from: sender))",
                    description: "\(recentCount) emails today (usually ~\(Int(avgDaily))/day)",
                    priority: .low,
                    actionRequired: false
                ))
            }
        }

        // Check for missed responses (people waiting for reply)
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        var potentiallyWaiting: [String] = []

        for email in weekEmails {
            guard let date = email.dateObject, date < threeDaysAgo else { continue }
            let body = email.body.lowercased()
            if body.contains("let me know") || body.contains("please respond") || body.contains("waiting") {
                potentiallyWaiting.append(email.from)
            }
        }

        if !potentiallyWaiting.isEmpty {
            let uniqueSenders = Set(potentiallyWaiting)
            items.append(BriefingItem(
                title: "Potential missed replies",
                description: "\(uniqueSenders.count) people may be waiting for a response",
                priority: .medium,
                actionRequired: true
            ))
        }

        return items
    }

    private func identifyTrendingTopics(_ emails: [Email]) -> [String] {
        var wordCounts: [String: Int] = [:]
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
                             "re:", "fw:", "fwd:", "from", "sent", "date", "subject", "is", "are", "was", "were",
                             "be", "been", "being", "have", "has", "had", "do", "does", "did", "will", "would",
                             "could", "should", "may", "might", "can", "this", "that", "these", "those"])

        for email in emails {
            let words = (email.subject + " " + email.body.prefix(200))
                .lowercased()
                .components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 3 && !stopWords.contains($0) && !$0.contains("@") }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        // Get top topics
        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private func generateSummary(_ emails: [Email]) async -> String {
        guard !emails.isEmpty else {
            return "No recent email activity."
        }

        // Quick summary without AI if few emails
        if emails.count <= 3 {
            return "You received \(emails.count) email(s) in the last 24 hours."
        }

        // Use AI for richer summary
        let senderCounts: [String: Int] = emails.reduce(into: [:]) { counts, email in
            counts[email.from, default: 0] += 1
        }

        let topSenders = senderCounts.sorted { $0.value > $1.value }.prefix(3)
        let topSubjects = emails.prefix(5).map { $0.subject }

        let context = """
        Email Statistics (Last 24 Hours):
        - Total emails: \(emails.count)
        - Top senders: \(topSenders.map { "\(extractName(from: $0.key)) (\($0.value))" }.joined(separator: ", "))
        - Recent subjects: \(topSubjects.joined(separator: "; "))
        """

        let prompt = """
        Write a brief (2-3 sentence) summary of this email activity:

        \(context)

        Focus on volume, key senders, and general themes. Be concise and informative.
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You write brief, professional email activity summaries.",
                temperature: 0.3
            )
        } catch {
            return "You received \(emails.count) emails in the last 24 hours from \(senderCounts.count) senders."
        }
    }

    // MARK: - Helpers

    private func normalizeEmail(_ email: String) -> String {
        if let emailMatch = email.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            return String(email[emailMatch]).lowercased()
        }
        return email.lowercased()
    }

    private func extractName(from email: String) -> String {
        if let nameMatch = email.range(of: #"^[^<]+"#, options: .regularExpression) {
            let name = String(email[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name
            }
        }
        if let atIndex = email.firstIndex(of: "@") {
            return String(email[..<atIndex]).replacingOccurrences(of: ".", with: " ").capitalized
        }
        return email
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "unknown date" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
