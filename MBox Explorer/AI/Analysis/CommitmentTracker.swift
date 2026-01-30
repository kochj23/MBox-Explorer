//
//  CommitmentTracker.swift
//  MBox Explorer
//
//  Extracts and tracks commitments/action items from emails
//  Author: Jordan Koch
//  Date: 2026-01-29
//

import Foundation

/// Tracks commitments and action items from email conversations
@MainActor
class CommitmentTracker: ObservableObject {
    static let shared = CommitmentTracker()

    @Published var commitments: [Commitment] = []
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0

    private let database = ConversationDatabase.shared
    private let aiBackend = AIBackendManager.shared

    // Commitment patterns
    private let commitmentPhrases = [
        "i will", "i'll", "will send", "will do", "will get", "will have",
        "i promise", "i commit", "you have my word",
        "will be done", "will complete", "will finish",
        "let me", "let me get", "i can", "i'm going to",
        "action item", "todo", "to do", "to-do",
        "by friday", "by monday", "by end of", "by eod", "by eow",
        "next week", "this week", "tomorrow", "asap"
    ]

    private let deadlinePatterns = [
        (pattern: #"by\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)"#, type: "weekday"),
        (pattern: #"by\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\s+\d{1,2}"#, type: "date"),
        (pattern: #"by\s+(\d{1,2}/\d{1,2})"#, type: "date"),
        (pattern: #"by\s+(eod|end\s+of\s+day)"#, type: "eod"),
        (pattern: #"by\s+(eow|end\s+of\s+week)"#, type: "eow"),
        (pattern: #"(next|this)\s+(week|month)"#, type: "relative"),
        (pattern: #"(tomorrow|asap|immediately)"#, type: "urgent")
    ]

    private init() {
        loadCommitments()
    }

    // MARK: - Analysis

    /// Analyze emails to extract commitments
    func analyzeEmails(_ emails: [Email]) async {
        isAnalyzing = true
        analysisProgress = 0

        var newCommitments: [Commitment] = []

        for (index, email) in emails.enumerated() {
            let extracted = extractCommitments(from: email)
            newCommitments.append(contentsOf: extracted)

            analysisProgress = Double(index + 1) / Double(emails.count)
        }

        // Save and deduplicate
        for commitment in newCommitments {
            if !isDuplicate(commitment) {
                database.saveCommitment(commitment)
            }
        }

        loadCommitments()
        isAnalyzing = false
    }

    /// Extract commitments from a single email
    func extractCommitments(from email: Email) -> [Commitment] {
        var commitments: [Commitment] = []

        let sentences = email.body
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for sentence in sentences {
            let lowerSentence = sentence.lowercased()

            // Check for commitment phrases
            for phrase in commitmentPhrases {
                if lowerSentence.contains(phrase) {
                    // Extract deadline if present
                    let (deadline, deadlineText) = extractDeadline(from: sentence, emailDate: email.dateObject)

                    // Determine who is making the commitment
                    let committer = lowerSentence.hasPrefix("i") || lowerSentence.contains("i will") || lowerSentence.contains("i'll")
                        ? email.from
                        : "Unknown"

                    let commitment = Commitment(
                        description: cleanCommitmentDescription(sentence),
                        committer: committer,
                        recipient: email.to,
                        deadline: deadline,
                        deadlineText: deadlineText,
                        sourceEmailId: email.id.uuidString,
                        sourceSubject: email.subject,
                        sourceDate: email.dateObject ?? Date()
                    )

                    commitments.append(commitment)
                    break // Only one commitment per sentence
                }
            }
        }

        return commitments
    }

    /// Use AI to extract commitments with better understanding
    func extractCommitmentsWithAI(from emails: [Email]) async -> [Commitment] {
        var allCommitments: [Commitment] = []

        // Process in batches
        let batchSize = 10
        for batchStart in stride(from: 0, to: emails.count, by: batchSize) {
            let batch = Array(emails[batchStart..<min(batchStart + batchSize, emails.count)])

            let emailContext = batch.map { email in
                """
                EMAIL_ID: \(email.id.uuidString)
                From: \(email.from)
                To: \(email.to ?? "Unknown")
                Subject: \(email.subject)
                Date: \(email.date)
                ---
                \(email.body.prefix(500))
                """
            }.joined(separator: "\n\n===\n\n")

            let prompt = """
            Extract all commitments, promises, and action items from these emails.

            For each commitment found, provide:
            1. The commitment description
            2. Who made the commitment (email address)
            3. Who it was made to (if clear)
            4. Any deadline mentioned (exact text)
            5. The EMAIL_ID where it was found

            Format each as:
            COMMITMENT: [description]
            COMMITTER: [email]
            RECIPIENT: [email or "Unknown"]
            DEADLINE: [text or "None"]
            EMAIL_ID: [id]
            ---

            EMAILS:
            \(emailContext)
            """

            do {
                let response = try await aiBackend.generate(
                    prompt: prompt,
                    systemPrompt: "You are an expert at identifying commitments and action items in emails."
                )

                let parsed = parseAICommitments(response, emails: batch)
                allCommitments.append(contentsOf: parsed)
            } catch {
                print("Error extracting commitments with AI: \(error)")
            }
        }

        return allCommitments
    }

    // MARK: - Commitment Management

    func loadCommitments() {
        commitments = database.commitments
    }

    func getPendingCommitments() -> [Commitment] {
        return commitments.filter { $0.status == .pending }
    }

    func getOverdueCommitments() -> [Commitment] {
        return commitments.filter { $0.isOverdue }
    }

    func getCommitmentsWithUpcomingDeadlines(within days: Int = 7) -> [Commitment] {
        let futureDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return commitments.filter { commitment in
            guard let deadline = commitment.deadline else { return false }
            return commitment.status == .pending && deadline <= futureDate && deadline >= Date()
        }
    }

    func getCommitmentsByPerson(_ email: String) -> [Commitment] {
        let normalized = email.lowercased()
        return commitments.filter { commitment in
            commitment.committer.lowercased().contains(normalized) ||
            (commitment.recipient?.lowercased().contains(normalized) ?? false)
        }
    }

    func markCommitmentComplete(_ commitment: Commitment) {
        database.updateCommitmentStatus(commitment, status: .completed)
        loadCommitments()
    }

    func markCommitmentCancelled(_ commitment: Commitment) {
        database.updateCommitmentStatus(commitment, status: .cancelled)
        loadCommitments()
    }

    func deferCommitment(_ commitment: Commitment) {
        database.updateCommitmentStatus(commitment, status: .deferred)
        loadCommitments()
    }

    // MARK: - Reminders

    /// Get reminder message for overdue commitments
    func getOverdueReminder() -> String? {
        let overdue = getOverdueCommitments()
        guard !overdue.isEmpty else { return nil }

        if overdue.count == 1 {
            let c = overdue[0]
            return "Reminder: You committed to \"\(c.description.prefix(50))\" which was due \(formatDeadline(c.deadline))"
        } else {
            return "Reminder: You have \(overdue.count) overdue commitments that need attention"
        }
    }

    /// Get upcoming deadline reminders
    func getUpcomingReminders(days: Int = 3) -> [String] {
        let upcoming = getCommitmentsWithUpcomingDeadlines(within: days)
        return upcoming.map { commitment in
            let daysText = commitment.daysUntilDeadline.map { "\($0) day(s)" } ?? "soon"
            return "\"\(commitment.description.prefix(40))\" is due in \(daysText)"
        }
    }

    // MARK: - Helpers

    private func extractDeadline(from text: String, emailDate: Date?) -> (Date?, String?) {
        let lowerText = text.lowercased()

        for pattern in deadlinePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern.pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowerText, range: NSRange(lowerText.startIndex..., in: lowerText)) {

                let matchRange = Range(match.range, in: lowerText)!
                let deadlineText = String(lowerText[matchRange])

                // Try to convert to actual date
                let deadline = parseDeadline(deadlineText, type: pattern.type, referenceDate: emailDate ?? Date())
                return (deadline, deadlineText)
            }
        }

        return (nil, nil)
    }

    private func parseDeadline(_ text: String, type: String, referenceDate: Date) -> Date? {
        let calendar = Calendar.current

        switch type {
        case "weekday":
            let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
                           "thursday": 5, "friday": 6, "saturday": 7]
            for (day, weekday) in weekdays {
                if text.contains(day) {
                    var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
                    components.weekday = weekday
                    var date = calendar.date(from: components)
                    // If the day has passed this week, move to next week
                    if let d = date, d < referenceDate {
                        date = calendar.date(byAdding: .day, value: 7, to: d)
                    }
                    return date
                }
            }

        case "eod":
            return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: referenceDate)

        case "eow":
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            components.weekday = 6 // Friday
            return calendar.date(from: components)

        case "urgent":
            if text.contains("tomorrow") {
                return calendar.date(byAdding: .day, value: 1, to: referenceDate)
            } else {
                return calendar.date(byAdding: .hour, value: 4, to: referenceDate)
            }

        case "relative":
            if text.contains("next week") {
                return calendar.date(byAdding: .day, value: 7, to: referenceDate)
            } else if text.contains("this week") {
                var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
                components.weekday = 6
                return calendar.date(from: components)
            } else if text.contains("next month") {
                return calendar.date(byAdding: .month, value: 1, to: referenceDate)
            }

        default:
            break
        }

        return nil
    }

    private func cleanCommitmentDescription(_ text: String) -> String {
        var cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^(i will|i'll|will|let me|i'm going to)\\s+", with: "", options: .regularExpression)

        // Capitalize first letter
        if let first = cleaned.first {
            cleaned = first.uppercased() + cleaned.dropFirst()
        }

        // Limit length
        if cleaned.count > 200 {
            cleaned = String(cleaned.prefix(200)) + "..."
        }

        return cleaned
    }

    private func isDuplicate(_ commitment: Commitment) -> Bool {
        return commitments.contains { existing in
            existing.description.lowercased() == commitment.description.lowercased() &&
            existing.sourceEmailId == commitment.sourceEmailId
        }
    }

    private func parseAICommitments(_ response: String, emails: [Email]) -> [Commitment] {
        var commitments: [Commitment] = []

        let blocks = response.components(separatedBy: "---")

        for block in blocks {
            let lines = block.components(separatedBy: .newlines)
            var commitmentData: [String: String] = [:]

            for line in lines {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 {
                    commitmentData[parts[0].uppercased()] = parts[1]
                }
            }

            if let description = commitmentData["COMMITMENT"],
               let committer = commitmentData["COMMITTER"],
               let emailId = commitmentData["EMAIL_ID"],
               let email = emails.first(where: { $0.id.uuidString == emailId }) {

                let recipient = commitmentData["RECIPIENT"]
                let deadlineText = commitmentData["DEADLINE"]
                let (deadline, _) = deadlineText.flatMap { text in
                    text == "None" ? nil : extractDeadline(from: text, emailDate: email.dateObject)
                } ?? (nil, nil)

                let commitment = Commitment(
                    description: description,
                    committer: committer,
                    recipient: recipient == "Unknown" ? nil : recipient,
                    deadline: deadline,
                    deadlineText: deadlineText == "None" ? nil : deadlineText,
                    sourceEmailId: emailId,
                    sourceSubject: email.subject,
                    sourceDate: email.dateObject ?? Date()
                )

                commitments.append(commitment)
            }
        }

        return commitments
    }

    private func formatDeadline(_ date: Date?) -> String {
        guard let date = date else { return "an unspecified date" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
