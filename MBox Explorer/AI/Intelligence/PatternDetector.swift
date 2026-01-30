//
//  PatternDetector.swift
//  MBox Explorer
//
//  Detects recurring patterns in email communications
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Detects patterns and anomalies in email communications
@MainActor
class PatternDetector: ObservableObject {
    static let shared = PatternDetector()

    @Published var detectedPatterns: [EmailPattern] = []
    @Published var anomalies: [EmailAnomaly] = []
    @Published var isAnalyzing = false

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared

    private init() {
        loadPatterns()
    }

    // MARK: - Pattern Detection

    /// Analyze emails for patterns
    func analyzePatterns(in emails: [Email]) async {
        isAnalyzing = true

        var patterns: [EmailPattern] = []
        var foundAnomalies: [EmailAnomaly] = []

        // Detect recurring topics
        let topicPatterns = detectRecurringTopics(in: emails)
        patterns.append(contentsOf: topicPatterns)

        // Detect seasonal patterns
        let seasonalPatterns = detectSeasonalPatterns(in: emails)
        patterns.append(contentsOf: seasonalPatterns)

        // Detect communication spikes
        let (spikePatterns, spikeAnomalies) = detectCommunicationSpikes(in: emails)
        patterns.append(contentsOf: spikePatterns)
        foundAnomalies.append(contentsOf: spikeAnomalies)

        // Detect response delay patterns
        let delayPatterns = detectResponseDelays(in: emails)
        patterns.append(contentsOf: delayPatterns)

        // Detect long thread patterns
        let threadPatterns = detectLongThreadPatterns(in: emails)
        patterns.append(contentsOf: threadPatterns)

        // Save patterns
        for pattern in patterns {
            database.savePattern(pattern)
        }

        detectedPatterns = patterns
        anomalies = foundAnomalies
        isAnalyzing = false
    }

    /// Ask AI about patterns
    func askAboutPatterns(topic: String, in emails: [Email]) async -> String {
        let relevantEmails = emails.filter { email in
            email.subject.lowercased().contains(topic.lowercased()) ||
            email.body.lowercased().contains(topic.lowercased())
        }

        guard !relevantEmails.isEmpty else {
            return "No emails found related to '\(topic)'."
        }

        // Group by time period
        var periodCounts: [String: Int] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"

        for email in relevantEmails {
            if let date = email.dateObject {
                let period = dateFormatter.string(from: date)
                periodCounts[period, default: 0] += 1
            }
        }

        let sortedPeriods = periodCounts.sorted { $0.key < $1.key }
        let periodData = sortedPeriods.map { "\($0.key): \($0.value) emails" }.joined(separator: "\n")

        let prompt = """
        Analyze the pattern of emails about "\(topic)":

        Monthly Distribution:
        \(periodData)

        Total emails: \(relevantEmails.count)
        Time span: \(sortedPeriods.first?.key ?? "?") to \(sortedPeriods.last?.key ?? "?")

        Identify:
        1. Is this a recurring topic?
        2. What frequency pattern do you see (weekly, monthly, quarterly, annual)?
        3. Are there any anomalies or spikes?
        4. When is activity typically highest?
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert at identifying communication patterns."
            )
        } catch {
            return "Error analyzing patterns: \(error.localizedDescription)"
        }
    }

    // MARK: - Pattern Detection Methods

    private func detectRecurringTopics(in emails: [Email]) -> [EmailPattern] {
        var topicOccurrences: [String: [(date: Date, emailId: String, participants: [String])] ] = [:]

        // Extract topics from subjects
        for email in emails {
            let topics = extractTopics(from: email.subject)

            for topic in topics {
                let entry = (
                    date: email.dateObject ?? Date(),
                    emailId: email.id.uuidString,
                    participants: [email.from] + (email.to?.components(separatedBy: ",") ?? [])
                )
                topicOccurrences[topic, default: []].append(entry)
            }
        }

        // Find topics that recur regularly
        var patterns: [EmailPattern] = []

        for (topic, occurrences) in topicOccurrences where occurrences.count >= 3 {
            // Calculate frequency
            let frequency = calculateFrequency(occurrences.map { $0.date })

            if let frequency = frequency {
                let allParticipants = Set(occurrences.flatMap { $0.participants })

                let pattern = EmailPattern(
                    patternType: .recurringTopic,
                    description: "Recurring discussion about '\(topic)'",
                    frequency: frequency,
                    lastOccurrence: occurrences.map { $0.date }.max() ?? Date(),
                    occurrences: occurrences.count,
                    examples: occurrences.prefix(5).map { $0.emailId },
                    participants: Array(allParticipants).prefix(10).map { $0 },
                    topics: [topic]
                )
                patterns.append(pattern)
            }
        }

        return patterns
    }

    private func detectSeasonalPatterns(in emails: [Email]) -> [EmailPattern] {
        var monthCounts: [Int: [Email]] = [:]

        for email in emails {
            if let date = email.dateObject {
                let month = Calendar.current.component(.month, from: date)
                monthCounts[month, default: []].append(email)
            }
        }

        var patterns: [EmailPattern] = []

        // Find months with significantly higher activity
        let avgCount = Double(emails.count) / 12.0

        for (month, monthEmails) in monthCounts {
            if Double(monthEmails.count) > avgCount * 1.5 {
                let monthName = DateFormatter().monthSymbols[month - 1]

                let pattern = EmailPattern(
                    patternType: .seasonalActivity,
                    description: "Higher email activity in \(monthName)",
                    frequency: "Annual",
                    lastOccurrence: monthEmails.compactMap { $0.dateObject }.max() ?? Date(),
                    occurrences: monthEmails.count,
                    examples: monthEmails.prefix(5).map { $0.id.uuidString },
                    participants: Array(Set(monthEmails.map { $0.from })).prefix(10).map { $0 },
                    topics: extractCommonTopics(from: monthEmails)
                )
                patterns.append(pattern)
            }
        }

        return patterns
    }

    private func detectCommunicationSpikes(in emails: [Email]) -> ([EmailPattern], [EmailAnomaly]) {
        var patterns: [EmailPattern] = []
        var anomalies: [EmailAnomaly] = []

        // Group by day
        var dailyCounts: [String: [Email]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for email in emails {
            if let date = email.dateObject {
                let key = dateFormatter.string(from: date)
                dailyCounts[key, default: []].append(email)
            }
        }

        // Calculate statistics
        let counts = dailyCounts.values.map { $0.count }
        let avgCount = Double(counts.reduce(0, +)) / Double(max(counts.count, 1))
        let stdDev = calculateStdDev(counts.map { Double($0) }, mean: avgCount)

        // Find spikes (> 2 standard deviations)
        for (dateKey, dayEmails) in dailyCounts {
            let count = Double(dayEmails.count)
            if count > avgCount + 2 * stdDev && count > 5 {
                let date = dateFormatter.date(from: dateKey) ?? Date()

                let pattern = EmailPattern(
                    patternType: .communicationSpike,
                    description: "Communication spike on \(dateKey) (\(dayEmails.count) emails)",
                    frequency: "One-time",
                    lastOccurrence: date,
                    occurrences: dayEmails.count,
                    examples: dayEmails.prefix(5).map { $0.id.uuidString },
                    participants: Array(Set(dayEmails.map { $0.from })).prefix(10).map { $0 },
                    topics: extractCommonTopics(from: dayEmails)
                )
                patterns.append(pattern)

                let anomaly = EmailAnomaly(
                    date: date,
                    description: "Unusual communication spike: \(dayEmails.count) emails (avg: \(Int(avgCount)))",
                    severity: count / avgCount,
                    relatedEmailIds: dayEmails.prefix(5).map { $0.id.uuidString }
                )
                anomalies.append(anomaly)
            }
        }

        return (patterns, anomalies)
    }

    private func detectResponseDelays(in emails: [Email]) -> [EmailPattern] {
        // This would require tracking conversations and responses
        // For now, return empty array
        return []
    }

    private func detectLongThreadPatterns(in emails: [Email]) -> [EmailPattern] {
        var threadCounts: [String: [Email]] = [:]

        for email in emails {
            let normalizedSubject = normalizeSubject(email.subject)
            threadCounts[normalizedSubject, default: []].append(email)
        }

        var patterns: [EmailPattern] = []

        // Find consistently long threads
        for (subject, threadEmails) in threadCounts where threadEmails.count >= 20 {
            let participants = Set(threadEmails.map { $0.from })

            let pattern = EmailPattern(
                patternType: .threadLength,
                description: "Long thread: '\(subject.prefix(50))' (\(threadEmails.count) messages)",
                frequency: "N/A",
                lastOccurrence: threadEmails.compactMap { $0.dateObject }.max() ?? Date(),
                occurrences: threadEmails.count,
                examples: threadEmails.prefix(5).map { $0.id.uuidString },
                participants: Array(participants).prefix(10).map { $0 },
                topics: [subject]
            )
            patterns.append(pattern)
        }

        return patterns
    }

    // MARK: - Helpers

    func loadPatterns() {
        detectedPatterns = database.patterns
    }

    private func extractTopics(from text: String) -> [String] {
        let stopWords = Set(["re:", "fw:", "fwd:", "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of"])

        let words = text
            .lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 && !stopWords.contains($0) }

        // Return significant words as topics
        return words.filter { $0.count >= 4 }
    }

    private func extractCommonTopics(from emails: [Email]) -> [String] {
        var wordCounts: [String: Int] = [:]

        for email in emails {
            let words = extractTopics(from: email.subject)
            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    private func calculateFrequency(_ dates: [Date]) -> String? {
        guard dates.count >= 3 else { return nil }

        let sortedDates = dates.sorted()
        var intervals: [TimeInterval] = []

        for i in 1..<sortedDates.count {
            intervals.append(sortedDates[i].timeIntervalSince(sortedDates[i-1]))
        }

        let avgInterval = intervals.reduce(0, +) / Double(intervals.count)
        let days = avgInterval / (24 * 60 * 60)

        switch days {
        case 0..<8: return "Weekly"
        case 8..<20: return "Bi-weekly"
        case 20..<45: return "Monthly"
        case 45..<100: return "Quarterly"
        case 100..<200: return "Semi-annual"
        default: return "Annual"
        }
    }

    private func calculateStdDev(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let sumOfSquaredDiffs = values.map { pow($0 - mean, 2) }.reduce(0, +)
        return sqrt(sumOfSquaredDiffs / Double(values.count - 1))
    }

    private func normalizeSubject(_ subject: String) -> String {
        return subject
            .lowercased()
            .replacingOccurrences(of: #"^(re:|fw:|fwd:)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Supporting Types

struct EmailAnomaly: Identifiable {
    let id = UUID()
    let date: Date
    let description: String
    let severity: Double
    let relatedEmailIds: [String]
}
