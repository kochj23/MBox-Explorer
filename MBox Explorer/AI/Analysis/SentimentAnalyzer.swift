//
//  SentimentAnalyzer.swift
//  MBox Explorer
//
//  Tracks emotional tone and sentiment over time
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Analyzes sentiment in email communications
@MainActor
class SentimentAnalyzer: ObservableObject {
    static let shared = SentimentAnalyzer()

    @Published var sentimentTimeline: [SentimentDataPoint] = []
    @Published var relationshipHealth: [String: RelationshipHealth] = [:]
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared

    // Sentiment keywords
    private let positiveWords = Set([
        "thank", "thanks", "appreciate", "great", "excellent", "wonderful", "amazing",
        "good", "love", "fantastic", "perfect", "happy", "pleased", "delighted",
        "excited", "congratulations", "awesome", "brilliant", "helpful", "grateful"
    ])

    private let negativeWords = Set([
        "disappointed", "frustrat", "angry", "upset", "concern", "problem", "issue",
        "unfortunately", "sorry", "apologize", "mistake", "error", "fail", "wrong",
        "terrible", "awful", "horrible", "urgent", "asap", "immediately", "complain"
    ])

    private let urgencyWords = Set([
        "urgent", "asap", "immediately", "critical", "emergency", "deadline", "overdue",
        "priority", "important", "now", "today", "eod", "eow"
    ])

    private init() {}

    // MARK: - Analysis

    /// Analyze sentiment across all emails
    func analyzeEmails(_ emails: [Email]) async {
        isAnalyzing = true
        analysisProgress = 0
        sentimentTimeline = []

        var dataPoints: [SentimentDataPoint] = []

        for (index, email) in emails.enumerated() {
            let sentiment = analyzeSentiment(text: email.body + " " + email.subject)
            let keywords = extractSentimentKeywords(from: email.body)

            let dataPoint = SentimentDataPoint(
                date: email.dateObject ?? Date(),
                sentiment: sentiment,
                emailId: email.id.uuidString,
                subject: email.subject,
                participant: normalizeEmail(email.from),
                keywords: keywords
            )

            dataPoints.append(dataPoint)
            database.saveSentimentDataPoint(dataPoint)

            analysisProgress = Double(index + 1) / Double(emails.count)
        }

        sentimentTimeline = dataPoints.sorted { $0.date < $1.date }

        // Calculate relationship health
        calculateRelationshipHealth()

        isAnalyzing = false
    }

    /// Analyze sentiment for a specific participant
    func analyzeSentimentFor(participant: String, emails: [Email]) async -> ParticipantSentimentAnalysis {
        let normalized = normalizeEmail(participant)

        let relevantEmails = emails.filter { email in
            normalizeEmail(email.from) == normalized ||
            (email.to?.lowercased().contains(normalized) ?? false)
        }

        var dataPoints: [SentimentDataPoint] = []

        for email in relevantEmails {
            let sentiment = analyzeSentiment(text: email.body)
            let keywords = extractSentimentKeywords(from: email.body)

            let dataPoint = SentimentDataPoint(
                date: email.dateObject ?? Date(),
                sentiment: sentiment,
                emailId: email.id.uuidString,
                subject: email.subject,
                participant: normalized,
                keywords: keywords
            )
            dataPoints.append(dataPoint)
        }

        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        let averageSentiment = sortedPoints.isEmpty ? 0 : sortedPoints.map { $0.sentiment }.reduce(0, +) / Double(sortedPoints.count)

        // Detect inflection points (significant sentiment changes)
        let inflectionPoints = detectInflectionPoints(in: sortedPoints)

        // Detect trend
        let trend = detectTrend(in: sortedPoints)

        return ParticipantSentimentAnalysis(
            participant: participant,
            averageSentiment: averageSentiment,
            dataPoints: sortedPoints,
            inflectionPoints: inflectionPoints,
            trend: trend
        )
    }

    /// Get sentiment timeline for a relationship
    func getRelationshipSentiment(person1: String, person2: String, emails: [Email]) async -> RelationshipSentimentAnalysis {
        let p1 = normalizeEmail(person1)
        let p2 = normalizeEmail(person2)

        let relevantEmails = emails.filter { email in
            let from = normalizeEmail(email.from)
            let to = normalizeEmail(email.to ?? "")
            return (from == p1 && to.contains(p2)) || (from == p2 && to.contains(p1))
        }

        var dataPoints: [SentimentDataPoint] = []

        for email in relevantEmails {
            let sentiment = analyzeSentiment(text: email.body)
            let dataPoint = SentimentDataPoint(
                date: email.dateObject ?? Date(),
                sentiment: sentiment,
                emailId: email.id.uuidString,
                subject: email.subject,
                participant: normalizeEmail(email.from)
            )
            dataPoints.append(dataPoint)
        }

        let sortedPoints = dataPoints.sorted { $0.date < $1.date }
        let healthScore = calculateHealthScore(from: sortedPoints)
        let trend = detectTrend(in: sortedPoints)
        let escalations = detectTensionEscalation(in: sortedPoints)

        return RelationshipSentimentAnalysis(
            person1: person1,
            person2: person2,
            dataPoints: sortedPoints,
            healthScore: healthScore,
            trend: trend,
            tensionEscalations: escalations
        )
    }

    /// Use AI to get detailed sentiment analysis
    func getAISentimentAnalysis(for emails: [Email], topic: String? = nil) async -> String {
        let emailContext = emails.prefix(15).map { email in
            """
            From: \(email.from)
            Subject: \(email.subject)
            Date: \(email.date)
            ---
            \(email.body.prefix(300))
            """
        }.joined(separator: "\n\n")

        var prompt = """
        Analyze the emotional tone and sentiment in these email communications:

        \(emailContext)

        Please provide:
        1. Overall sentiment assessment (positive, negative, neutral)
        2. Specific emotional markers detected
        3. Any tension or escalation patterns
        4. Recommendations for communication improvement
        """

        if let topic = topic {
            prompt += "\n\nFocus particularly on discussions related to: \(topic)"
        }

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert at analyzing emotional tone and sentiment in professional communication."
            )
        } catch {
            return "Error analyzing sentiment: \(error.localizedDescription)"
        }
    }

    // MARK: - Sentiment Calculation

    private func analyzeSentiment(text: String) -> Double {
        let words = text.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        var positiveCount = 0
        var negativeCount = 0
        var urgencyCount = 0

        for word in words {
            if positiveWords.contains(where: { word.contains($0) }) {
                positiveCount += 1
            }
            if negativeWords.contains(where: { word.contains($0) }) {
                negativeCount += 1
            }
            if urgencyWords.contains(where: { word.contains($0) }) {
                urgencyCount += 1
            }
        }

        // Check for exclamation marks (can indicate strong emotion)
        let exclamationCount = text.filter { $0 == "!" }.count

        // Check for ALL CAPS words (can indicate strong emotion)
        let capsWords = words.filter { $0.count > 2 && $0 == $0.uppercased() }.count

        // Calculate base sentiment
        let totalSentimentWords = positiveCount + negativeCount
        var sentiment: Double = 0

        if totalSentimentWords > 0 {
            sentiment = Double(positiveCount - negativeCount) / Double(totalSentimentWords)
        }

        // Adjust for urgency (can indicate stress)
        if urgencyCount > 2 {
            sentiment -= 0.1
        }

        // Adjust for exclamation marks
        if exclamationCount > 3 {
            sentiment = sentiment > 0 ? sentiment + 0.1 : sentiment - 0.1
        }

        // Adjust for CAPS
        if capsWords > 2 {
            sentiment -= 0.1
        }

        // Clamp to -1 to 1
        return max(-1, min(1, sentiment))
    }

    private func extractSentimentKeywords(from text: String) -> [String] {
        let words = text.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 }

        var keywords: [String] = []

        for word in words {
            if positiveWords.contains(where: { word.contains($0) }) ||
               negativeWords.contains(where: { word.contains($0) }) ||
               urgencyWords.contains(where: { word.contains($0) }) {
                keywords.append(word)
            }
        }

        return Array(Set(keywords)).prefix(10).map { $0 }
    }

    private func detectInflectionPoints(in dataPoints: [SentimentDataPoint]) -> [SentimentInflectionPoint] {
        var inflectionPoints: [SentimentInflectionPoint] = []

        guard dataPoints.count > 2 else { return [] }

        let windowSize = 3
        var previousAvg: Double?

        for i in windowSize..<dataPoints.count {
            let windowStart = i - windowSize
            let windowPoints = Array(dataPoints[windowStart..<i])
            let currentAvg = windowPoints.map { $0.sentiment }.reduce(0, +) / Double(windowSize)

            if let prev = previousAvg {
                let change = currentAvg - prev

                // Significant change threshold
                if abs(change) > 0.3 {
                    let direction: SentimentDirection = change > 0 ? .improving : .declining
                    let inflection = SentimentInflectionPoint(
                        date: dataPoints[i].date,
                        previousSentiment: prev,
                        newSentiment: currentAvg,
                        direction: direction,
                        triggerEmailId: dataPoints[i].emailId
                    )
                    inflectionPoints.append(inflection)
                }
            }

            previousAvg = currentAvg
        }

        return inflectionPoints
    }

    private func detectTrend(in dataPoints: [SentimentDataPoint]) -> SentimentTrend {
        guard dataPoints.count > 3 else { return .stable }

        let recentPoints = dataPoints.suffix(min(10, dataPoints.count))
        let sentiments = recentPoints.map { $0.sentiment }

        // Simple linear regression
        let n = Double(sentiments.count)
        let sumX = (0..<Int(n)).map { Double($0) }.reduce(0, +)
        let sumY = sentiments.reduce(0, +)
        let sumXY = (0..<Int(n)).map { Double($0) * sentiments[$0] }.reduce(0, +)
        let sumX2 = (0..<Int(n)).map { Double($0) * Double($0) }.reduce(0, +)

        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)

        if slope > 0.05 {
            return .improving
        } else if slope < -0.05 {
            return .declining
        } else {
            return .stable
        }
    }

    private func detectTensionEscalation(in dataPoints: [SentimentDataPoint]) -> [TensionEscalation] {
        var escalations: [TensionEscalation] = []

        for i in 1..<dataPoints.count {
            let prev = dataPoints[i - 1]
            let current = dataPoints[i]

            // Significant negative shift
            if current.sentiment < prev.sentiment - 0.4 && current.sentiment < -0.3 {
                escalations.append(TensionEscalation(
                    date: current.date,
                    emailId: current.emailId,
                    subject: current.subject,
                    severityChange: prev.sentiment - current.sentiment
                ))
            }
        }

        return escalations
    }

    private func calculateHealthScore(from dataPoints: [SentimentDataPoint]) -> Double {
        guard !dataPoints.isEmpty else { return 0.5 }

        let avgSentiment = dataPoints.map { $0.sentiment }.reduce(0, +) / Double(dataPoints.count)
        let recentSentiment: Double

        if dataPoints.count > 5 {
            let recent = dataPoints.suffix(5)
            recentSentiment = recent.map { $0.sentiment }.reduce(0, +) / Double(recent.count)
        } else {
            recentSentiment = avgSentiment
        }

        // Health is combination of average and recent (weighted toward recent)
        return (avgSentiment * 0.3 + recentSentiment * 0.7 + 1) / 2
    }

    private func calculateRelationshipHealth() {
        // Group sentiment data by participant pairs
        var pairSentiments: [String: [SentimentDataPoint]] = [:]

        for point in sentimentTimeline {
            pairSentiments[point.participant, default: []].append(point)
        }

        for (participant, points) in pairSentiments {
            let score = calculateHealthScore(from: points)
            let trend = detectTrend(in: points)

            relationshipHealth[participant] = RelationshipHealth(
                participant: participant,
                score: score,
                trend: trend,
                lastUpdated: Date()
            )
        }
    }

    private func normalizeEmail(_ email: String) -> String {
        if let emailMatch = email.range(of: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#, options: .regularExpression) {
            return String(email[emailMatch]).lowercased()
        }
        return email.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Supporting Types

struct ParticipantSentimentAnalysis {
    let participant: String
    let averageSentiment: Double
    let dataPoints: [SentimentDataPoint]
    let inflectionPoints: [SentimentInflectionPoint]
    let trend: SentimentTrend

    var sentimentDescription: String {
        switch averageSentiment {
        case 0.3...1.0: return "Positive"
        case -0.3..<0.3: return "Neutral"
        default: return "Negative"
        }
    }
}

struct RelationshipSentimentAnalysis {
    let person1: String
    let person2: String
    let dataPoints: [SentimentDataPoint]
    let healthScore: Double
    let trend: SentimentTrend
    let tensionEscalations: [TensionEscalation]

    var healthDescription: String {
        switch healthScore {
        case 0.7...1.0: return "Healthy"
        case 0.4..<0.7: return "Moderate"
        default: return "Strained"
        }
    }
}

struct SentimentInflectionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let previousSentiment: Double
    let newSentiment: Double
    let direction: SentimentDirection
    let triggerEmailId: String
}

struct TensionEscalation: Identifiable {
    let id = UUID()
    let date: Date
    let emailId: String
    let subject: String
    let severityChange: Double
}

struct RelationshipHealth {
    let participant: String
    let score: Double
    let trend: SentimentTrend
    let lastUpdated: Date
}

enum SentimentTrend: String {
    case improving = "Improving"
    case stable = "Stable"
    case declining = "Declining"
}

enum SentimentDirection: String {
    case improving = "Improving"
    case declining = "Declining"
}
