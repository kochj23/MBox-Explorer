//
//  ActionItemExtractor.swift
//  MBox Explorer
//
//  Extracts action items, commitments, and deadlines from emails
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Extracts action items, commitments, and deadlines from emails
class ActionItemExtractor: ObservableObject {
    static let shared = ActionItemExtractor()

    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var extractedItems: [ActionItem] = []

    private let llm = LocalLLM.shared

    // Common action phrases for quick detection
    private let actionPhrases = [
        "i will", "i'll", "i am going to", "i'm going to",
        "please", "could you", "can you", "would you",
        "need to", "have to", "must", "should",
        "by tomorrow", "by friday", "by end of", "deadline",
        "asap", "urgent", "priority", "action required",
        "follow up", "get back to", "let me know",
        "send me", "send you", "attach", "forward",
        "schedule", "meeting", "call", "discuss"
    ]

    // MARK: - Extract from Single Email

    func extractActionItems(from email: Email) async throws -> [ActionItem] {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let prompt = """
        Extract all action items, commitments, and deadlines from this email.

        For each item found, identify:
        - The action/task description
        - Who is responsible (sender, recipient, or specific person)
        - Any deadline or timeframe mentioned
        - Priority level (high/medium/low based on language)
        - Type: TASK, COMMITMENT, DEADLINE, FOLLOW_UP, MEETING, or REQUEST

        From: \(email.from)
        To: \(email.to ?? "")
        Subject: \(email.subject)
        Date: \(email.date)

        Content:
        \(email.body.prefix(4000))

        Return as a structured list. If no action items found, say "NO_ACTION_ITEMS".

        Format each item as:
        TYPE: [type]
        ACTION: [description]
        OWNER: [who is responsible]
        DEADLINE: [date/timeframe or "none"]
        PRIORITY: [high/medium/low]
        ---

        Action Items:
        """

        let response = await llm.summarize(content: prompt)

        if response.contains("NO_ACTION_ITEMS") {
            return []
        }

        return parseActionItems(from: response, email: email)
    }

    // MARK: - Batch Extraction

    func extractAllActionItems(from emails: [Email], progressCallback: ((Double) -> Void)? = nil) async throws -> [ActionItem] {
        await MainActor.run {
            isProcessing = true
            progress = 0
            extractedItems = []
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        var allItems: [ActionItem] = []

        // First pass: quick filter using keywords
        let potentialEmails = emails.filter { email in
            let content = "\(email.subject) \(email.body)".lowercased()
            return actionPhrases.contains { content.contains($0) }
        }

        for (index, email) in potentialEmails.enumerated() {
            do {
                let items = try await extractActionItems(from: email)
                allItems.append(contentsOf: items)

                let progressValue = Double(index + 1) / Double(potentialEmails.count)
                await MainActor.run {
                    self.progress = progressValue
                    self.extractedItems = allItems
                }
                progressCallback?(progressValue)
            } catch {
                // Continue with other emails
                print("Error extracting from email: \(error.localizedDescription)")
            }
        }

        return allItems
    }

    // MARK: - Find Commitments

    /// Find promises made by sender
    func findCommitmentsMade(in emails: [Email], by person: String) async throws -> [ActionItem] {
        let personEmails = emails.filter { $0.from.lowercased().contains(person.lowercased()) }
        let allItems = try await extractAllActionItems(from: personEmails)
        return allItems.filter { $0.type == .commitment }
    }

    /// Find requests made to recipient
    func findRequestsReceived(in emails: [Email], by person: String) async throws -> [ActionItem] {
        let personEmails = emails.filter {
            $0.to?.lowercased().contains(person.lowercased()) == true
        }
        let allItems = try await extractAllActionItems(from: personEmails)
        return allItems.filter { $0.type == .request || $0.type == .task }
    }

    // MARK: - Find Deadlines

    func findUpcomingDeadlines(in emails: [Email], within days: Int = 7) async throws -> [ActionItem] {
        let allItems = try await extractAllActionItems(from: emails)
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now

        return allItems.filter { item in
            guard let deadline = item.deadline else { return false }
            return deadline >= now && deadline <= cutoff
        }.sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    func findOverdueItems(in emails: [Email]) async throws -> [ActionItem] {
        let allItems = try await extractAllActionItems(from: emails)
        let now = Date()

        return allItems.filter { item in
            guard let deadline = item.deadline else { return false }
            return deadline < now
        }.sorted { ($0.deadline ?? .distantPast) > ($1.deadline ?? .distantPast) }
    }

    // MARK: - Export

    func exportToReminders(items: [ActionItem]) -> String {
        // Generate AppleScript for Reminders import
        var script = "tell application \"Reminders\"\n"
        script += "  set mboxList to list \"MBox Action Items\"\n"

        for item in items {
            let title = item.description.replacingOccurrences(of: "\"", with: "\\\"")
            script += "  make new reminder in mboxList with properties {name:\"\(title)\""
            if let deadline = item.deadline {
                let formatter = ISO8601DateFormatter()
                script += ", due date:date \"\(formatter.string(from: deadline))\""
            }
            script += "}\n"
        }

        script += "end tell"
        return script
    }

    func exportToCSV(items: [ActionItem]) -> String {
        var csv = "Type,Description,Owner,Deadline,Priority,Source Email,Source Date\n"

        let formatter = DateFormatter()
        formatter.dateStyle = .short

        for item in items {
            let deadline = item.deadline.map { formatter.string(from: $0) } ?? ""
            let row = [
                item.type.rawValue,
                "\"\(item.description.replacingOccurrences(of: "\"", with: "\"\""))\"",
                "\"\(item.owner)\"",
                deadline,
                item.priority.rawValue,
                "\"\(item.sourceSubject)\"",
                item.sourceDate
            ].joined(separator: ",")
            csv += row + "\n"
        }

        return csv
    }

    // MARK: - Parsing

    private func parseActionItems(from response: String, email: Email) -> [ActionItem] {
        var items: [ActionItem] = []
        let blocks = response.components(separatedBy: "---")

        for block in blocks {
            guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            var type: ActionItemType = .task
            var description = ""
            var owner = ""
            var deadlineStr = ""
            var priority: ActionItemPriority = .medium

            let lines = block.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }

                let key = parts[0].uppercased()
                let value = parts[1]

                switch key {
                case "TYPE":
                    type = ActionItemType(rawValue: value.uppercased()) ?? .task
                case "ACTION":
                    description = value
                case "OWNER":
                    owner = value
                case "DEADLINE":
                    deadlineStr = value
                case "PRIORITY":
                    priority = ActionItemPriority(rawValue: value.lowercased()) ?? .medium
                default:
                    break
                }
            }

            guard !description.isEmpty else { continue }

            let item = ActionItem(
                id: UUID(),
                type: type,
                description: description,
                owner: owner.isEmpty ? "Unknown" : owner,
                deadline: parseDeadline(deadlineStr, referenceDate: email.dateObject ?? Date()),
                priority: priority,
                sourceEmailId: email.id,
                sourceSubject: email.subject,
                sourceDate: email.date,
                sourceFrom: email.from,
                extractedAt: Date()
            )
            items.append(item)
        }

        return items
    }

    private func parseDeadline(_ string: String, referenceDate: Date) -> Date? {
        let lowered = string.lowercased()

        if lowered == "none" || lowered.isEmpty {
            return nil
        }

        let calendar = Calendar.current

        // Relative dates
        if lowered.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: referenceDate)
        }
        if lowered.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: referenceDate)
        }
        if lowered.contains("end of week") || lowered.contains("friday") {
            // Find next Friday
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            components.weekday = 6 // Friday
            return calendar.date(from: components)
        }
        if lowered.contains("end of month") {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: referenceDate) else { return nil }
            let components = calendar.dateComponents([.year, .month], from: nextMonth)
            guard let firstOfNext = calendar.date(from: components) else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: firstOfNext)
        }

        // Try parsing as date
        let formatters = [
            "MM/dd/yyyy", "MM-dd-yyyy", "yyyy-MM-dd",
            "MMM d, yyyy", "MMMM d, yyyy", "MMM d"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }
}

// MARK: - Models

struct ActionItem: Identifiable, Codable {
    let id: UUID
    let type: ActionItemType
    let description: String
    let owner: String
    let deadline: Date?
    let priority: ActionItemPriority
    let sourceEmailId: UUID
    let sourceSubject: String
    let sourceDate: String
    let sourceFrom: String
    let extractedAt: Date

    var isOverdue: Bool {
        guard let deadline = deadline else { return false }
        return deadline < Date()
    }

    var isDueSoon: Bool {
        guard let deadline = deadline else { return false }
        let threeDays = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return deadline <= threeDays && deadline >= Date()
    }
}

enum ActionItemType: String, Codable, CaseIterable {
    case task = "TASK"
    case commitment = "COMMITMENT"
    case deadline = "DEADLINE"
    case followUp = "FOLLOW_UP"
    case meeting = "MEETING"
    case request = "REQUEST"

    var icon: String {
        switch self {
        case .task: return "checkmark.circle"
        case .commitment: return "hand.raised"
        case .deadline: return "clock"
        case .followUp: return "arrow.uturn.right"
        case .meeting: return "person.2"
        case .request: return "envelope"
        }
    }
}

enum ActionItemPriority: String, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var color: String {
        switch self {
        case .high: return "red"
        case .medium: return "orange"
        case .low: return "gray"
        }
    }
}
