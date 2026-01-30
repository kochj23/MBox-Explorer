//
//  HypotheticalAnalyzer.swift
//  MBox Explorer
//
//  Analyzes hypothetical scenarios and traces implications
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Analyzes hypothetical scenarios based on email history
@MainActor
class HypotheticalAnalyzer: ObservableObject {
    static let shared = HypotheticalAnalyzer()

    @Published var lastAnalysis: HypotheticalAnalysis?
    @Published var isAnalyzing = false

    private let aiBackend = AIBackendManager.shared

    private init() {}

    // MARK: - Hypothetical Analysis

    /// Analyze a "what if" scenario
    func analyze(scenario: String, emails: [Email]) async -> HypotheticalAnalysis {
        isAnalyzing = true

        // Find relevant context for the scenario
        let relevantEmails = findRelevantEmails(for: scenario, in: emails)

        let prompt = """
        Analyze this hypothetical scenario based on the email history:

        SCENARIO: "\(scenario)"

        RELEVANT EMAIL CONTEXT:
        \(formatEmailContext(relevantEmails))

        Please analyze:
        1. What likely would have happened differently?
        2. Which people/discussions would have been affected?
        3. What downstream implications can you trace?
        4. Are there any email threads that directly relate to this decision point?
        5. Rate your confidence in this analysis (low/medium/high)

        Provide a structured analysis considering the actual email evidence available.
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an analyst who explores hypothetical scenarios based on documented communication history. Be thoughtful about what the emails actually show vs. speculation."
            )

            let analysis = HypotheticalAnalysis(
                scenario: scenario,
                analysis: response,
                relatedEmails: relevantEmails.map { $0.id.uuidString },
                confidence: extractConfidence(from: response),
                timestamp: Date()
            )

            lastAnalysis = analysis
            isAnalyzing = false

            return analysis
        } catch {
            let errorAnalysis = HypotheticalAnalysis(
                scenario: scenario,
                analysis: "Error analyzing scenario: \(error.localizedDescription)",
                relatedEmails: [],
                confidence: .low,
                timestamp: Date()
            )

            isAnalyzing = false
            return errorAnalysis
        }
    }

    /// Trace implications of a decision
    func traceImplications(of decision: String, madeOn date: Date, emails: [Email]) async -> ImplicationTrace {
        let beforeEmails = emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            let weekBefore = Calendar.current.date(byAdding: .day, value: -14, to: date) ?? date
            return emailDate >= weekBefore && emailDate < date
        }

        let afterEmails = emails.filter { email in
            guard let emailDate = email.dateObject else { return false }
            let monthAfter = Calendar.current.date(byAdding: .month, value: 1, to: date) ?? date
            return emailDate > date && emailDate <= monthAfter
        }

        let prompt = """
        Trace the implications of this decision:

        DECISION: "\(decision)"
        DATE: \(formatDate(date))

        CONTEXT BEFORE DECISION (\(beforeEmails.count) emails):
        \(formatEmailContext(Array(beforeEmails.prefix(10))))

        ACTIVITY AFTER DECISION (\(afterEmails.count) emails):
        \(formatEmailContext(Array(afterEmails.prefix(10))))

        Analyze:
        1. What was being discussed before this decision?
        2. How did discussions change after the decision?
        3. What new topics emerged?
        4. Which participants became more/less active?
        5. What downstream actions can be traced to this decision?
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You trace the implications of decisions through email communication patterns."
            )

            return ImplicationTrace(
                decision: decision,
                decisionDate: date,
                analysis: response,
                beforeContext: beforeEmails.prefix(5).map { $0.id.uuidString },
                afterEffects: afterEmails.prefix(5).map { $0.id.uuidString }
            )
        } catch {
            return ImplicationTrace(
                decision: decision,
                decisionDate: date,
                analysis: "Error: \(error.localizedDescription)",
                beforeContext: [],
                afterEffects: []
            )
        }
    }

    /// Compare what happened vs. what could have happened
    func compareOutcomes(actualDecision: String, alternative: String, emails: [Email]) async -> OutcomeComparison {
        let relevantEmails = findRelevantEmails(for: actualDecision, in: emails)

        let prompt = """
        Compare the actual outcome with a hypothetical alternative:

        ACTUAL DECISION: "\(actualDecision)"
        ALTERNATIVE: "\(alternative)"

        EMAIL EVIDENCE:
        \(formatEmailContext(relevantEmails))

        Analyze:
        1. What happened as a result of the actual decision (based on emails)?
        2. What might have happened with the alternative?
        3. What are the key differences in likely outcomes?
        4. Which stakeholders would have been affected differently?
        5. What evidence from the emails supports these conclusions?
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You compare actual outcomes with hypothetical alternatives based on email evidence."
            )

            return OutcomeComparison(
                actualDecision: actualDecision,
                alternative: alternative,
                analysis: response,
                relatedEmails: relevantEmails.map { $0.id.uuidString }
            )
        } catch {
            return OutcomeComparison(
                actualDecision: actualDecision,
                alternative: alternative,
                analysis: "Error: \(error.localizedDescription)",
                relatedEmails: []
            )
        }
    }

    /// Identify decision points that could have gone differently
    func identifyDecisionPoints(in emails: [Email]) async -> [DecisionPoint] {
        // Look for emails with decision indicators
        let decisionIndicators = ["decided", "agreed", "chose", "selected", "approved", "going with", "final"]

        var potentialDecisions: [Email] = []

        for email in emails {
            let lowerBody = email.body.lowercased()
            if decisionIndicators.contains(where: { lowerBody.contains($0) }) {
                potentialDecisions.append(email)
            }
        }

        // Group by topic and extract decision points
        var decisionPoints: [DecisionPoint] = []

        for email in potentialDecisions.prefix(20) {
            // Look for alternative mentions
            let alternatives = extractAlternatives(from: email.body)

            if !alternatives.isEmpty {
                decisionPoints.append(DecisionPoint(
                    date: email.dateObject ?? Date(),
                    topic: email.subject,
                    decision: extractDecision(from: email.body),
                    alternatives: alternatives,
                    emailId: email.id.uuidString
                ))
            }
        }

        return decisionPoints
    }

    // MARK: - Helpers

    private func findRelevantEmails(for scenario: String, in emails: [Email]) -> [Email] {
        let keywords = extractKeywords(from: scenario)

        return emails.filter { email in
            let content = (email.subject + " " + email.body).lowercased()
            return keywords.contains { keyword in
                content.contains(keyword.lowercased())
            }
        }
        .sorted { ($0.dateObject ?? Date()) > ($1.dateObject ?? Date()) }
        .prefix(15)
        .map { $0 }
    }

    private func extractKeywords(from text: String) -> [String] {
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
                             "what", "if", "had", "have", "been", "would", "could", "should", "not", "instead"])

        return text.lowercased()
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 3 && !stopWords.contains($0) }
    }

    private func formatEmailContext(_ emails: [Email]) -> String {
        if emails.isEmpty {
            return "No directly relevant emails found."
        }

        return emails.map { email in
            """
            From: \(email.from)
            Subject: \(email.subject)
            Date: \(email.date)
            \(email.body.prefix(300))
            """
        }.joined(separator: "\n---\n")
    }

    private func extractConfidence(from response: String) -> AnalysisConfidence {
        let lowerResponse = response.lowercased()
        if lowerResponse.contains("high confidence") || lowerResponse.contains("confident") {
            return .high
        } else if lowerResponse.contains("low confidence") || lowerResponse.contains("uncertain") || lowerResponse.contains("speculative") {
            return .low
        }
        return .medium
    }

    private func extractAlternatives(from text: String) -> [String] {
        let patterns = ["instead of", "rather than", "other option", "alternative", "or we could", "versus"]
        var alternatives: [String] = []

        let lowerText = text.lowercased()
        for pattern in patterns {
            if let range = lowerText.range(of: pattern) {
                let afterPattern = lowerText[range.upperBound...]
                let words = afterPattern.prefix(100).components(separatedBy: CharacterSet(charactersIn: ",.!?\n"))
                if let first = words.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty {
                    alternatives.append(first)
                }
            }
        }

        return alternatives
    }

    private func extractDecision(from text: String) -> String {
        let patterns = ["we decided", "decision is", "going with", "approved"]
        let lowerText = text.lowercased()

        for pattern in patterns {
            if let range = lowerText.range(of: pattern) {
                let afterPattern = lowerText[range.upperBound...]
                let sentence = afterPattern.prefix(200).components(separatedBy: CharacterSet(charactersIn: ".!?\n")).first ?? ""
                return sentence.trimmingCharacters(in: .whitespaces)
            }
        }

        return "Unknown decision"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct HypotheticalAnalysis: Identifiable {
    let id = UUID()
    let scenario: String
    let analysis: String
    let relatedEmails: [String]
    let confidence: AnalysisConfidence
    let timestamp: Date
}

struct ImplicationTrace: Identifiable {
    let id = UUID()
    let decision: String
    let decisionDate: Date
    let analysis: String
    let beforeContext: [String]
    let afterEffects: [String]
}

struct OutcomeComparison: Identifiable {
    let id = UUID()
    let actualDecision: String
    let alternative: String
    let analysis: String
    let relatedEmails: [String]
}

struct DecisionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let topic: String
    let decision: String
    let alternatives: [String]
    let emailId: String
}

enum AnalysisConfidence: String {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}
