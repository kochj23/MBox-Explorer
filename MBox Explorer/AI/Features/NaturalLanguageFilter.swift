//
//  NaturalLanguageFilter.swift
//  MBox Explorer
//
//  Natural language query parsing for email filters
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Parses natural language queries into email filters
class NaturalLanguageFilter: ObservableObject {
    static let shared = NaturalLanguageFilter()

    @Published var lastParsedQuery: ParsedFilter?

    private let llm = LocalLLM.shared

    // MARK: - Parse Query

    func parseQuery(_ query: String) async throws -> ParsedFilter {
        // First try rule-based parsing for common patterns
        if let ruleBasedResult = parseWithRules(query) {
            await MainActor.run {
                self.lastParsedQuery = ruleBasedResult
            }
            return ruleBasedResult
        }

        // Fall back to AI parsing for complex queries
        return try await parseWithAI(query)
    }

    // MARK: - Rule-Based Parsing

    private func parseWithRules(_ query: String) -> ParsedFilter? {
        let lowered = query.lowercased()
        var filter = ParsedFilter(originalQuery: query)
        var matched = false

        // Date patterns
        if let dateFilter = parseDateExpression(lowered) {
            filter.dateFilter = dateFilter
            matched = true
        }

        // Sender patterns
        if let fromPattern = lowered.range(of: "from\\s+([\\w.@]+)", options: .regularExpression) {
            let match = String(lowered[fromPattern])
            let sender = match.replacingOccurrences(of: "from ", with: "")
            filter.fromFilter = sender
            matched = true
        }

        // Subject patterns
        if let aboutPattern = lowered.range(of: "(about|regarding|re:|subject:?)\\s+(.+?)($|\\s+from|\\s+to|\\s+last|\\s+this)", options: .regularExpression) {
            let match = String(lowered[aboutPattern])
            let topic = match
                .replacingOccurrences(of: "about ", with: "")
                .replacingOccurrences(of: "regarding ", with: "")
                .replacingOccurrences(of: "re: ", with: "")
                .replacingOccurrences(of: "subject: ", with: "")
                .replacingOccurrences(of: " from", with: "")
                .replacingOccurrences(of: " to", with: "")
                .trimmingCharacters(in: .whitespaces)
            filter.subjectFilter = topic
            matched = true
        }

        // Attachment patterns
        if lowered.contains("with attachment") || lowered.contains("has attachment") {
            filter.hasAttachment = true
            matched = true
        }
        if lowered.contains("without attachment") || lowered.contains("no attachment") {
            filter.hasAttachment = false
            matched = true
        }

        // Size patterns
        if let sizeFilter = parseSizeExpression(lowered) {
            filter.sizeFilter = sizeFilter
            matched = true
        }

        // Unread patterns
        if lowered.contains("unread") {
            filter.isUnread = true
            matched = true
        }

        // Starred/important
        if lowered.contains("starred") || lowered.contains("important") || lowered.contains("flagged") {
            filter.isStarred = true
            matched = true
        }

        // Limit patterns
        if let limitMatch = lowered.range(of: "(top|first|last)\\s+(\\d+)", options: .regularExpression) {
            let match = String(lowered[limitMatch])
            if let num = match.split(separator: " ").last.flatMap({ Int($0) }) {
                filter.limit = num
                matched = true
            }
        }

        return matched ? filter : nil
    }

    private func parseDateExpression(_ query: String) -> DateFilter? {
        let calendar = Calendar.current
        let now = Date()

        // Today
        if query.contains("today") {
            return DateFilter(
                start: calendar.startOfDay(for: now),
                end: now,
                description: "Today"
            )
        }

        // Yesterday
        if query.contains("yesterday") {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return nil }
            return DateFilter(
                start: calendar.startOfDay(for: yesterday),
                end: calendar.startOfDay(for: now),
                description: "Yesterday"
            )
        }

        // This week
        if query.contains("this week") {
            guard let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return nil }
            return DateFilter(
                start: weekStart,
                end: now,
                description: "This week"
            )
        }

        // Last week
        if query.contains("last week") {
            guard let thisWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else { return nil }
            return DateFilter(
                start: lastWeekStart,
                end: thisWeekStart,
                description: "Last week"
            )
        }

        // This month
        if query.contains("this month") {
            guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return nil }
            return DateFilter(
                start: monthStart,
                end: now,
                description: "This month"
            )
        }

        // Last month
        if query.contains("last month") {
            guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) else { return nil }
            return DateFilter(
                start: lastMonthStart,
                end: thisMonthStart,
                description: "Last month"
            )
        }

        // Last N days
        if let daysMatch = query.range(of: "last\\s+(\\d+)\\s+days?", options: .regularExpression) {
            let match = String(query[daysMatch])
            if let num = match.split(separator: " ").dropFirst().first.flatMap({ Int($0) }),
               let startDate = calendar.date(byAdding: .day, value: -num, to: now) {
                return DateFilter(
                    start: startDate,
                    end: now,
                    description: "Last \(num) days"
                )
            }
        }

        // Specific year
        if let yearMatch = query.range(of: "\\b(20\\d{2})\\b", options: .regularExpression) {
            let yearStr = String(query[yearMatch])
            if let year = Int(yearStr) {
                var startComponents = DateComponents()
                startComponents.year = year
                startComponents.month = 1
                startComponents.day = 1

                var endComponents = DateComponents()
                endComponents.year = year
                endComponents.month = 12
                endComponents.day = 31

                if let start = calendar.date(from: startComponents),
                   let end = calendar.date(from: endComponents) {
                    return DateFilter(
                        start: start,
                        end: end,
                        description: "Year \(year)"
                    )
                }
            }
        }

        return nil
    }

    private func parseSizeExpression(_ query: String) -> SizeFilter? {
        // "larger than 5mb", "bigger than 1 mb", "over 10mb"
        if let match = query.range(of: "(larger|bigger|over|more than)\\s+(\\d+)\\s*(mb|kb|gb)?", options: .regularExpression) {
            let matchStr = String(query[match])
            if let size = extractSize(from: matchStr) {
                return SizeFilter(minSize: size, maxSize: nil, description: "Larger than \(formatSize(size))")
            }
        }

        // "smaller than 1mb", "under 500kb"
        if let match = query.range(of: "(smaller|under|less than)\\s+(\\d+)\\s*(mb|kb|gb)?", options: .regularExpression) {
            let matchStr = String(query[match])
            if let size = extractSize(from: matchStr) {
                return SizeFilter(minSize: nil, maxSize: size, description: "Smaller than \(formatSize(size))")
            }
        }

        return nil
    }

    private func extractSize(from text: String) -> Int? {
        guard let numMatch = text.range(of: "\\d+", options: .regularExpression) else { return nil }
        let numStr = String(text[numMatch])
        guard let num = Int(numStr) else { return nil }

        let lowered = text.lowercased()
        if lowered.contains("gb") {
            return num * 1024 * 1024 * 1024
        } else if lowered.contains("mb") {
            return num * 1024 * 1024
        } else if lowered.contains("kb") {
            return num * 1024
        }

        // Default to MB
        return num * 1024 * 1024
    }

    private func formatSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - AI-Based Parsing

    private func parseWithAI(_ query: String) async throws -> ParsedFilter {
        let prompt = """
        Parse this natural language email filter query into structured components.

        Query: "\(query)"

        Extract these fields (leave blank if not specified):
        - FROM: sender email or name
        - TO: recipient email or name
        - SUBJECT: subject keywords
        - BODY: body content keywords
        - DATE_START: start date (YYYY-MM-DD)
        - DATE_END: end date (YYYY-MM-DD)
        - HAS_ATTACHMENT: true/false
        - MIN_SIZE: minimum size in bytes
        - MAX_SIZE: maximum size in bytes
        - LIMIT: max number of results

        Format as key: value pairs, one per line.

        Parsed Filter:
        """

        let response = await llm.summarize(content: prompt)
        return parseAIResponse(response, originalQuery: query)
    }

    private func parseAIResponse(_ response: String, originalQuery: String) -> ParsedFilter {
        var filter = ParsedFilter(originalQuery: originalQuery)

        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }

            let key = parts[0].uppercased()
            let value = parts[1]

            switch key {
            case "FROM":
                filter.fromFilter = value
            case "TO":
                filter.toFilter = value
            case "SUBJECT":
                filter.subjectFilter = value
            case "BODY":
                filter.bodyFilter = value
            case "DATE_START":
                filter.dateFilter = DateFilter(
                    start: parseDate(value) ?? Date.distantPast,
                    end: filter.dateFilter?.end ?? Date(),
                    description: "Custom date range"
                )
            case "DATE_END":
                filter.dateFilter = DateFilter(
                    start: filter.dateFilter?.start ?? Date.distantPast,
                    end: parseDate(value) ?? Date(),
                    description: "Custom date range"
                )
            case "HAS_ATTACHMENT":
                filter.hasAttachment = value.lowercased() == "true"
            case "MIN_SIZE":
                if let size = Int(value) {
                    filter.sizeFilter = SizeFilter(minSize: size, maxSize: filter.sizeFilter?.maxSize, description: "Size filter")
                }
            case "MAX_SIZE":
                if let size = Int(value) {
                    filter.sizeFilter = SizeFilter(minSize: filter.sizeFilter?.minSize, maxSize: size, description: "Size filter")
                }
            case "LIMIT":
                filter.limit = Int(value)
            default:
                break
            }
        }

        return filter
    }

    private func parseDate(_ string: String) -> Date? {
        let formatters = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }

    // MARK: - Apply Filter

    func applyFilter(_ filter: ParsedFilter, to emails: [Email]) -> [Email] {
        var filtered = emails

        // From filter
        if let from = filter.fromFilter {
            filtered = filtered.filter { $0.from.lowercased().contains(from.lowercased()) }
        }

        // To filter
        if let to = filter.toFilter {
            filtered = filtered.filter { $0.to?.lowercased().contains(to.lowercased()) == true }
        }

        // Subject filter
        if let subject = filter.subjectFilter {
            filtered = filtered.filter { $0.subject.lowercased().contains(subject.lowercased()) }
        }

        // Body filter
        if let body = filter.bodyFilter {
            filtered = filtered.filter { $0.body.lowercased().contains(body.lowercased()) }
        }

        // Date filter
        if let dateFilter = filter.dateFilter {
            filtered = filtered.filter { email in
                guard let date = email.dateObject else { return false }
                return date >= dateFilter.start && date <= dateFilter.end
            }
        }

        // Attachment filter
        if let hasAttachment = filter.hasAttachment {
            filtered = filtered.filter { ($0.attachments?.isEmpty ?? true) != hasAttachment }
        }

        // Size filter
        if let sizeFilter = filter.sizeFilter {
            filtered = filtered.filter { email in
                let size = email.body.utf8.count // Approximate size
                if let min = sizeFilter.minSize, size < min { return false }
                if let max = sizeFilter.maxSize, size > max { return false }
                return true
            }
        }

        // Limit
        if let limit = filter.limit {
            filtered = Array(filtered.prefix(limit))
        }

        return filtered
    }
}

// MARK: - Models

struct ParsedFilter {
    let originalQuery: String
    var fromFilter: String?
    var toFilter: String?
    var subjectFilter: String?
    var bodyFilter: String?
    var dateFilter: DateFilter?
    var hasAttachment: Bool?
    var isUnread: Bool?
    var isStarred: Bool?
    var sizeFilter: SizeFilter?
    var limit: Int?

    var description: String {
        var parts: [String] = []
        if let from = fromFilter { parts.append("from: \(from)") }
        if let to = toFilter { parts.append("to: \(to)") }
        if let subject = subjectFilter { parts.append("subject: \(subject)") }
        if let date = dateFilter { parts.append("date: \(date.description)") }
        if let hasAtt = hasAttachment { parts.append(hasAtt ? "has attachment" : "no attachment") }
        if let size = sizeFilter { parts.append("size: \(size.description)") }
        if let limit = limit { parts.append("limit: \(limit)") }
        return parts.isEmpty ? originalQuery : parts.joined(separator: ", ")
    }

    var isEmpty: Bool {
        fromFilter == nil && toFilter == nil && subjectFilter == nil && bodyFilter == nil &&
        dateFilter == nil && hasAttachment == nil && sizeFilter == nil && limit == nil
    }
}

struct DateFilter {
    let start: Date
    let end: Date
    let description: String
}

struct SizeFilter {
    let minSize: Int?
    let maxSize: Int?
    let description: String
}
