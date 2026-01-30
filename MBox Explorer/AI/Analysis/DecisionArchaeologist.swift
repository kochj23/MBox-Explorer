//
//  DecisionArchaeologist.swift
//  MBox Explorer
//
//  Traces decisions through email threads
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Traces and documents decisions made through email conversations
@MainActor
class DecisionArchaeologist: ObservableObject {
    static let shared = DecisionArchaeologist()

    @Published var decisions: [TracedDecision] = []
    @Published var isAnalyzing = false

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared

    // Decision indicators
    private let decisionPhrases = [
        "we decided", "we've decided", "decision is", "final decision",
        "going with", "we're going with", "chose to", "chosen",
        "approved", "signed off", "green light", "moving forward with",
        "agreed to", "consensus is", "voted for", "selected"
    ]

    private let alternativePhrases = [
        "instead of", "rather than", "other option", "alternative",
        "considered", "evaluated", "compared to", "versus", "vs"
    ]

    private let proPhrases = [
        "advantage", "pro", "benefit", "upside", "strength",
        "in favor", "positive", "good thing", "better because"
    ]

    private let conPhrases = [
        "disadvantage", "con", "drawback", "downside", "weakness",
        "against", "negative", "concern", "risk", "issue with"
    ]

    private init() {
        loadDecisions()
    }

    // MARK: - Analysis

    /// Trace decisions in email threads
    func traceDecisions(in emails: [Email]) async -> [TracedDecision] {
        isAnalyzing = true

        // Group emails by thread
        let threads = groupIntoThreads(emails)

        var tracedDecisions: [TracedDecision] = []

        for thread in threads {
            if let decision = await analyzeThreadForDecision(thread) {
                tracedDecisions.append(decision)
                database.saveDecision(decision)
            }
        }

        decisions = tracedDecisions
        isAnalyzing = false

        return tracedDecisions
    }

    /// Ask AI to trace a specific decision
    func traceDecision(topic: String, in emails: [Email]) async -> TracedDecision? {
        // Find relevant emails
        let relevantEmails = emails.filter { email in
            email.subject.lowercased().contains(topic.lowercased()) ||
            email.body.lowercased().contains(topic.lowercased())
        }

        guard !relevantEmails.isEmpty else { return nil }

        let emailContext = relevantEmails.prefix(15).map { email in
            """
            From: \(email.from)
            Subject: \(email.subject)
            Date: \(email.date)
            ---
            \(email.body.prefix(500))
            """
        }.joined(separator: "\n\n===\n\n")

        let prompt = """
        Analyze these emails to trace the decision-making process about "\(topic)".

        Extract:
        1. What was the final decision?
        2. Who were the key decision makers?
        3. What alternatives were considered?
        4. What were the pros mentioned for the chosen option?
        5. What were the cons or concerns?
        6. When was the decision made?
        7. How confident are you in this analysis (0-1)?

        Format your response as:
        DECISION: [final decision]
        DECISION_MAKERS: [comma-separated names/emails]
        ALTERNATIVES: [comma-separated alternatives]
        PROS: [comma-separated pros]
        CONS: [comma-separated cons]
        DATE: [approximate date]
        CONFIDENCE: [0-1]

        EMAILS:
        \(emailContext)
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are an expert at analyzing decision-making processes in professional email threads."
            )

            return parseDecisionResponse(response, topic: topic, emails: relevantEmails)
        } catch {
            print("Error tracing decision: \(error)")
            return nil
        }
    }

    /// Get the story of how a decision was made
    func getDecisionStory(for decision: TracedDecision, emails: [Email]) async -> String {
        let supportingEmails = emails.filter { email in
            decision.supportingEmails.contains(email.id.uuidString)
        }.sorted { ($0.dateObject ?? Date()) < ($1.dateObject ?? Date()) }

        let emailContext = supportingEmails.map { email in
            """
            From: \(email.from)
            Date: \(email.date)
            Subject: \(email.subject)
            ---
            \(email.body.prefix(400))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Create a narrative summary of how this decision was made:

        Topic: \(decision.topic)
        Final Decision: \(decision.decision)
        Decision Makers: \(decision.decisionMakers.joined(separator: ", "))
        Alternatives: \(decision.alternatives.joined(separator: ", "))
        Pros: \(decision.pros.joined(separator: ", "))
        Cons: \(decision.cons.joined(separator: ", "))

        Email Thread:
        \(emailContext)

        Write a clear, chronological story of how this decision unfolded, including:
        - Initial discussion or proposal
        - Key arguments and debates
        - Turning points
        - Final conclusion
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are a business analyst creating clear decision documentation."
            )
        } catch {
            return "Unable to generate decision story: \(error.localizedDescription)"
        }
    }

    /// Find decisions by topic
    func findDecisions(containing topic: String) -> [TracedDecision] {
        return decisions.filter { decision in
            decision.topic.lowercased().contains(topic.lowercased()) ||
            decision.decision.lowercased().contains(topic.lowercased())
        }
    }

    /// Compare two decisions
    func compareDecisions(_ decision1: TracedDecision, _ decision2: TracedDecision) async -> String {
        let prompt = """
        Compare these two decisions:

        Decision 1:
        - Topic: \(decision1.topic)
        - Decision: \(decision1.decision)
        - Date: \(formatDate(decision1.decisionDate))
        - Makers: \(decision1.decisionMakers.joined(separator: ", "))
        - Pros: \(decision1.pros.joined(separator: ", "))
        - Cons: \(decision1.cons.joined(separator: ", "))

        Decision 2:
        - Topic: \(decision2.topic)
        - Decision: \(decision2.decision)
        - Date: \(formatDate(decision2.decisionDate))
        - Makers: \(decision2.decisionMakers.joined(separator: ", "))
        - Pros: \(decision2.pros.joined(separator: ", "))
        - Cons: \(decision2.cons.joined(separator: ", "))

        Analyze:
        1. How are these decisions related?
        2. Were similar factors considered?
        3. Did one influence the other?
        4. Are there any contradictions?
        """

        do {
            return try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You are a business analyst comparing strategic decisions."
            )
        } catch {
            return "Unable to compare decisions: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    func loadDecisions() {
        decisions = database.getDecisions()
    }

    private func groupIntoThreads(_ emails: [Email]) -> [[Email]] {
        var threads: [String: [Email]] = [:]

        for email in emails {
            // Normalize subject for threading
            var threadKey = email.subject
                .lowercased()
                .replacingOccurrences(of: #"^(re:|fw:|fwd:)\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            threads[threadKey, default: []].append(email)
        }

        // Filter to threads with potential decisions (multiple participants, multiple emails)
        return threads.values
            .filter { thread in
                thread.count >= 2 &&
                Set(thread.map { $0.from }).count >= 2 &&
                containsDecisionIndicator(thread)
            }
            .map { $0.sorted { ($0.dateObject ?? Date()) < ($1.dateObject ?? Date()) } }
    }

    private func containsDecisionIndicator(_ emails: [Email]) -> Bool {
        let combinedText = emails.map { $0.body.lowercased() }.joined(separator: " ")
        return decisionPhrases.contains { combinedText.contains($0) }
    }

    private func analyzeThreadForDecision(_ thread: [Email]) async -> TracedDecision? {
        let combinedText = thread.map { $0.body.lowercased() }.joined(separator: " ")

        // Check if this thread contains a decision
        guard decisionPhrases.contains(where: { combinedText.contains($0) }) else {
            return nil
        }

        // Use AI for better extraction
        let emailContext = thread.prefix(10).map { email in
            """
            From: \(email.from)
            Subject: \(email.subject)
            Date: \(email.date)
            ---
            \(email.body.prefix(400))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Analyze this email thread and extract any decision that was made.

        EMAILS:
        \(emailContext)

        If a decision was made, provide:
        TOPIC: [what the decision was about]
        DECISION: [what was decided]
        DECISION_MAKERS: [who made/approved the decision]
        ALTERNATIVES: [other options that were considered]
        PROS: [reasons for the decision]
        CONS: [concerns or drawbacks mentioned]
        CONFIDENCE: [0-1, how clear is this decision]

        If no clear decision was made, respond with: NO_DECISION
        """

        do {
            let response = try await aiBackend.generate(
                prompt: prompt,
                systemPrompt: "You extract decisions from email threads. Be precise and only identify clear decisions."
            )

            if response.contains("NO_DECISION") {
                return nil
            }

            return parseDecisionResponse(response, topic: thread.first?.subject ?? "Unknown", emails: thread)
        } catch {
            return nil
        }
    }

    private func parseDecisionResponse(_ response: String, topic: String, emails: [Email]) -> TracedDecision? {
        var data: [String: String] = [:]

        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                data[parts[0].uppercased()] = parts[1]
            }
        }

        guard let decision = data["DECISION"], !decision.isEmpty else {
            return nil
        }

        let parsedTopic = data["TOPIC"] ?? topic
        let decisionMakers = data["DECISION_MAKERS"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let alternatives = data["ALTERNATIVES"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let pros = data["PROS"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let cons = data["CONS"]?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let confidence = Double(data["CONFIDENCE"] ?? "0.5") ?? 0.5

        // Find decision date (latest email in thread)
        let decisionDate = emails.compactMap { $0.dateObject }.max() ?? Date()

        return TracedDecision(
            topic: parsedTopic,
            decision: decision,
            decisionMakers: decisionMakers,
            decisionDate: decisionDate,
            pros: pros,
            cons: cons,
            alternatives: alternatives,
            supportingEmails: emails.map { $0.id.uuidString },
            attachments: extractAttachmentNames(from: emails),
            confidence: confidence
        )
    }

    private func extractAttachmentNames(from emails: [Email]) -> [String] {
        return emails.flatMap { email in
            email.attachments?.map { $0.filename } ?? []
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
