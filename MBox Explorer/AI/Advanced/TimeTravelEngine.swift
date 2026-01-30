//
//  TimeTravelEngine.swift
//  MBox Explorer
//
//  Enables contextual time-based navigation through email history
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Enables "time travel" queries through email history
@MainActor
class TimeTravelEngine: ObservableObject {
    static let shared = TimeTravelEngine()

    @Published var currentPeriod: TimePeriod?
    @Published var periodSummary: PeriodSummary?
    @Published var isAnalyzing = false

    private let aiBackend = AIBackendManager.shared

    private init() {}

    // MARK: - Time-Based Queries

    /// Get emails from a specific time period
    func travelTo(period: TimePeriod, emails: [Email]) -> [Email] {
        currentPeriod = period

        return emails.filter { email in
            guard let date = email.dateObject else { return false }
            return date >= period.startDate && date <= period.endDate
        }
    }

    /// Parse natural language time reference
    func parseTimeReference(_ text: String) -> TimePeriod? {
        let lowerText = text.lowercased()

        // Month patterns
        let months = ["january", "february", "march", "april", "may", "june",
                     "july", "august", "september", "october", "november", "december"]

        for (index, month) in months.enumerated() {
            if lowerText.contains(month) {
                // Check for year
                if let yearMatch = text.range(of: #"20\d{2}"#, options: .regularExpression) {
                    let year = Int(text[yearMatch]) ?? Calendar.current.component(.year, from: Date())
                    return TimePeriod.month(month: index + 1, year: year)
                }
                // Default to current year or last year
                let currentYear = Calendar.current.component(.year, from: Date())
                let currentMonth = Calendar.current.component(.month, from: Date())
                let year = index + 1 <= currentMonth ? currentYear : currentYear - 1
                return TimePeriod.month(month: index + 1, year: year)
            }
        }

        // Quarter patterns
        if lowerText.contains("q1") || lowerText.contains("first quarter") {
            let year = extractYear(from: text)
            return TimePeriod.quarter(quarter: 1, year: year)
        }
        if lowerText.contains("q2") || lowerText.contains("second quarter") {
            let year = extractYear(from: text)
            return TimePeriod.quarter(quarter: 2, year: year)
        }
        if lowerText.contains("q3") || lowerText.contains("third quarter") {
            let year = extractYear(from: text)
            return TimePeriod.quarter(quarter: 3, year: year)
        }
        if lowerText.contains("q4") || lowerText.contains("fourth quarter") {
            let year = extractYear(from: text)
            return TimePeriod.quarter(quarter: 4, year: year)
        }

        // Relative patterns
        if lowerText.contains("last month") {
            return TimePeriod.lastMonth()
        }
        if lowerText.contains("last week") {
            return TimePeriod.lastWeek()
        }
        if lowerText.contains("last year") {
            return TimePeriod.lastYear()
        }
        if lowerText.contains("this month") {
            return TimePeriod.thisMonth()
        }
        if lowerText.contains("this week") {
            return TimePeriod.thisWeek()
        }
        if lowerText.contains("this year") {
            return TimePeriod.thisYear()
        }

        // "N days/weeks/months ago" patterns
        if let match = text.range(of: #"(\d+)\s+(days?|weeks?|months?)\s+ago"#, options: .regularExpression) {
            let matchText = String(text[match])
            if let numberMatch = matchText.range(of: #"\d+"#, options: .regularExpression) {
                let number = Int(matchText[numberMatch]) ?? 1

                if matchText.contains("day") {
                    return TimePeriod.daysAgo(number)
                } else if matchText.contains("week") {
                    return TimePeriod.weeksAgo(number)
                } else if matchText.contains("month") {
                    return TimePeriod.monthsAgo(number)
                }
            }
        }

        return nil
    }

    /// Get a summary of what was happening in a time period
    func summarizePeriod(_ period: TimePeriod, emails: [Email]) async -> PeriodSummary {
        isAnalyzing = true

        let periodEmails = travelTo(period: period, emails: emails)

        // Basic statistics
        let emailCount = periodEmails.count
        let senders = Set(periodEmails.map { normalizeEmail($0.from) })
        let threads = countThreads(periodEmails)

        // Top topics
        let topics = extractTopTopics(from: periodEmails)

        // Key events (from AI)
        let keyEvents = await identifyKeyEvents(periodEmails)

        let summary = PeriodSummary(
            period: period,
            emailCount: emailCount,
            uniqueSenders: senders.count,
            threadCount: threads,
            topTopics: topics,
            keyEvents: keyEvents
        )

        periodSummary = summary
        isAnalyzing = false

        return summary
    }

    /// Compare two time periods
    func comparePeriods(_ period1: TimePeriod, _ period2: TimePeriod, emails: [Email]) async -> PeriodComparison {
        let emails1 = travelTo(period: period1, emails: emails)
        let emails2 = travelTo(period: period2, emails: emails)

        let topics1 = Set(extractTopTopics(from: emails1))
        let topics2 = Set(extractTopTopics(from: emails2))

        let senders1 = Set(emails1.map { normalizeEmail($0.from) })
        let senders2 = Set(emails2.map { normalizeEmail($0.from) })

        return PeriodComparison(
            period1: period1,
            period2: period2,
            emailCount1: emails1.count,
            emailCount2: emails2.count,
            volumeChange: calculatePercentChange(from: emails1.count, to: emails2.count),
            commonTopics: Array(topics1.intersection(topics2)),
            newTopicsInPeriod2: Array(topics2.subtracting(topics1)),
            droppedTopics: Array(topics1.subtracting(topics2)),
            newSenders: Array(senders2.subtracting(senders1)).prefix(10).map { $0 },
            inactiveSenders: Array(senders1.subtracting(senders2)).prefix(10).map { $0 }
        )
    }

    /// Ask AI what was happening at a specific time
    func askAboutPeriod(_ query: String, period: TimePeriod, emails: [Email]) async -> String {
        let periodEmails = travelTo(period: period, emails: emails)

        guard !periodEmails.isEmpty else {
            return "No emails found for \(period.description)."
        }

        let emailContext = periodEmails.prefix(15).map { email in
            """
            From: \(email.from)
            Subject: \(email.subject)
            Date: \(email.date)
            \(email.body.prefix(200))
            """
        }.joined(separator: "\n---\n")

        let prompt = """
        Context: The user is asking about emails from \(period.description)

        EMAILS FROM THIS PERIOD:
        \(emailContext)

        Total emails in period: \(periodEmails.count)

        USER QUESTION: \(query)

        Provide a helpful answer focusing on what was happening during this time period.
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You help users understand their email history by answering questions about specific time periods."
            )
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Identify what changed after a specific event
    func whatChangedAfter(event: String, date: Date, emails: [Email]) async -> String {
        let before = emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            let weekBefore = Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date
            return emailDate >= weekBefore && emailDate < date
        }

        let after = emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            let weekAfter = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
            return emailDate > date && emailDate <= weekAfter
        }

        let prompt = """
        Analyze changes in email communication before and after "\(event)" on \(formatDate(date)):

        EMAILS WEEK BEFORE (\(before.count) emails):
        \(before.prefix(5).map { "- \($0.subject) from \($0.from)" }.joined(separator: "\n"))

        EMAILS WEEK AFTER (\(after.count) emails):
        \(after.prefix(5).map { "- \($0.subject) from \($0.from)" }.joined(separator: "\n"))

        What changes do you observe in:
        1. Communication volume
        2. Topics discussed
        3. Participants involved
        4. Tone or urgency
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You analyze changes in communication patterns around significant events."
            )
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func extractYear(from text: String) -> Int {
        if let yearMatch = text.range(of: #"20\d{2}"#, options: .regularExpression) {
            return Int(text[yearMatch]) ?? Calendar.current.component(.year, from: Date())
        }
        return Calendar.current.component(.year, from: Date())
    }

    private func normalizeEmail(_ email: String) -> String {
        if let emailMatch = email.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            return String(email[emailMatch]).lowercased()
        }
        return email.lowercased()
    }

    private func countThreads(_ emails: [Email]) -> Int {
        let subjects = Set(emails.map { normalizeSubject($0.subject) })
        return subjects.count
    }

    private func normalizeSubject(_ subject: String) -> String {
        return subject.lowercased()
            .replacingOccurrences(of: #"^(re:|fw:|fwd:)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func extractTopTopics(from emails: [Email]) -> [String] {
        var wordCounts: [String: Int] = [:]
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "re:", "fw:", "fwd:"])

        for email in emails {
            let words = email.subject.lowercased()
                .components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 3 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key.capitalized }
    }

    private func identifyKeyEvents(_ emails: [Email]) async -> [String] {
        guard !emails.isEmpty else { return [] }

        let subjects = emails.prefix(20).map { $0.subject }
        let uniqueSubjects = Set(subjects)

        // Look for high-activity subjects
        var subjectCounts: [String: Int] = [:]
        for subject in subjects {
            let normalized = normalizeSubject(subject)
            subjectCounts[normalized, default: 0] += 1
        }

        return subjectCounts
            .filter { $0.value >= 3 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { "Discussion: \($0.key.prefix(50).capitalized)" }
    }

    private func calculatePercentChange(from old: Int, to new: Int) -> Double {
        guard old > 0 else { return new > 0 ? 100.0 : 0.0 }
        return (Double(new - old) / Double(old)) * 100.0
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct TimePeriod: Equatable {
    let startDate: Date
    let endDate: Date
    let description: String

    static func month(month: Int, year: Int) -> TimePeriod {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        let startDate = Calendar.current.date(from: components) ?? Date()
        let endDate = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let description = formatter.string(from: startDate)

        return TimePeriod(startDate: startDate, endDate: endDate, description: description)
    }

    static func quarter(quarter: Int, year: Int) -> TimePeriod {
        let startMonth = (quarter - 1) * 3 + 1
        var components = DateComponents()
        components.year = year
        components.month = startMonth
        components.day = 1

        let startDate = Calendar.current.date(from: components) ?? Date()
        let endDate = Calendar.current.date(byAdding: DateComponents(month: 3, day: -1), to: startDate) ?? Date()

        return TimePeriod(startDate: startDate, endDate: endDate, description: "Q\(quarter) \(year)")
    }

    static func lastMonth() -> TimePeriod {
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -1, to: Calendar.current.startOfDay(for: today)) ?? today
        let endDate = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: today)) ?? today
        return TimePeriod(startDate: startDate, endDate: endDate, description: "Last Month")
    }

    static func lastWeek() -> TimePeriod {
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
        return TimePeriod(startDate: startDate, endDate: today, description: "Last Week")
    }

    static func lastYear() -> TimePeriod {
        let year = Calendar.current.component(.year, from: Date()) - 1
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1

        var endComponents = DateComponents()
        endComponents.year = year
        endComponents.month = 12
        endComponents.day = 31

        let startDate = Calendar.current.date(from: startComponents) ?? Date()
        let endDate = Calendar.current.date(from: endComponents) ?? Date()

        return TimePeriod(startDate: startDate, endDate: endDate, description: "Last Year (\(year))")
    }

    static func thisMonth() -> TimePeriod {
        let today = Date()
        let startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: today)) ?? today
        return TimePeriod(startDate: startDate, endDate: today, description: "This Month")
    }

    static func thisWeek() -> TimePeriod {
        let today = Date()
        let startOfWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) ?? today
        return TimePeriod(startDate: startOfWeek, endDate: today, description: "This Week")
    }

    static func thisYear() -> TimePeriod {
        let today = Date()
        let year = Calendar.current.component(.year, from: today)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1

        let startDate = Calendar.current.date(from: startComponents) ?? today
        return TimePeriod(startDate: startDate, endDate: today, description: "This Year")
    }

    static func daysAgo(_ days: Int) -> TimePeriod {
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: today) ?? today
        return TimePeriod(startDate: startDate, endDate: today, description: "\(days) days ago")
    }

    static func weeksAgo(_ weeks: Int) -> TimePeriod {
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -weeks * 7, to: today) ?? today
        return TimePeriod(startDate: startDate, endDate: today, description: "\(weeks) weeks ago")
    }

    static func monthsAgo(_ months: Int) -> TimePeriod {
        let today = Date()
        let startDate = Calendar.current.date(byAdding: .month, value: -months, to: today) ?? today
        return TimePeriod(startDate: startDate, endDate: today, description: "\(months) months ago")
    }
}

struct PeriodSummary {
    let period: TimePeriod
    let emailCount: Int
    let uniqueSenders: Int
    let threadCount: Int
    let topTopics: [String]
    let keyEvents: [String]
}

struct PeriodComparison {
    let period1: TimePeriod
    let period2: TimePeriod
    let emailCount1: Int
    let emailCount2: Int
    let volumeChange: Double
    let commonTopics: [String]
    let newTopicsInPeriod2: [String]
    let droppedTopics: [String]
    let newSenders: [String]
    let inactiveSenders: [String]
}
