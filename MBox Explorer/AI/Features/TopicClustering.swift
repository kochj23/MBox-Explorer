//
//  TopicClustering.swift
//  MBox Explorer
//
//  AI-powered topic clustering and categorization
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Auto-categorizes emails by topic using AI and clustering
class TopicClustering: ObservableObject {
    static let shared = TopicClustering()

    @Published var isProcessing = false
    @Published var progress: Double = 0
    @Published var clusters: [TopicCluster] = []
    @Published var emailTopics: [UUID: String] = [:] // emailId -> topic

    private let llm = LocalLLM.shared
    private let vectorDB = VectorDatabase()

    // Predefined categories for initial classification
    private let defaultCategories = [
        "Work/Business",
        "Personal",
        "Finance/Banking",
        "Shopping/Orders",
        "Travel",
        "Social/Events",
        "Newsletters/Marketing",
        "Technical/IT",
        "Legal/Contracts",
        "Healthcare",
        "Education",
        "Other"
    ]

    // MARK: - Cluster Emails

    func clusterEmails(_ emails: [Email]) async throws -> [TopicCluster] {
        await MainActor.run {
            isProcessing = true
            progress = 0
            clusters = []
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Step 1: Classify each email
        var emailClassifications: [(Email, String)] = []

        for (index, email) in emails.enumerated() {
            let topic = try await classifyEmail(email)
            emailClassifications.append((email, topic))

            await MainActor.run {
                self.emailTopics[email.id] = topic
                self.progress = Double(index + 1) / Double(emails.count) * 0.7
            }
        }

        // Step 2: Group by topic
        let grouped = Dictionary(grouping: emailClassifications, by: { $0.1 })

        // Step 3: Create clusters with summaries
        var topicClusters: [TopicCluster] = []

        for (topic, emailsInTopic) in grouped.sorted(by: { $0.value.count > $1.value.count }) {
            let clusterEmails = emailsInTopic.map { $0.0 }

            // Generate cluster summary
            let summary = try await generateClusterSummary(topic: topic, emails: clusterEmails)

            let cluster = TopicCluster(
                id: UUID(),
                name: topic,
                emailIds: clusterEmails.map { $0.id },
                emailCount: clusterEmails.count,
                summary: summary,
                keywords: extractKeywords(from: clusterEmails),
                dateRange: getDateRange(from: clusterEmails),
                topSenders: getTopSenders(from: clusterEmails)
            )

            topicClusters.append(cluster)
        }

        await MainActor.run {
            self.clusters = topicClusters
            self.progress = 1.0
        }

        return topicClusters
    }

    // MARK: - Classify Single Email

    func classifyEmail(_ email: Email) async throws -> String {
        let prompt = """
        Classify this email into ONE of these categories:
        \(defaultCategories.joined(separator: ", "))

        From: \(email.from)
        Subject: \(email.subject)
        Preview: \(String(email.body.prefix(500)))

        Respond with ONLY the category name, nothing else.

        Category:
        """

        let response = await llm.summarize(content: prompt)
        let category = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // Validate against known categories
        if let match = defaultCategories.first(where: { category.lowercased().contains($0.lowercased()) }) {
            return match
        }

        return "Other"
    }

    // MARK: - Discover Topics

    /// Discover topics without predefined categories
    func discoverTopics(_ emails: [Email], numTopics: Int = 10) async throws -> [DiscoveredTopic] {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Sample emails for topic discovery
        let sampleSize = min(100, emails.count)
        let samples = emails.shuffled().prefix(sampleSize)

        let subjectList = samples.map { "• \($0.subject)" }.joined(separator: "\n")

        let prompt = """
        Analyze these email subjects and discover the \(numTopics) main topics/themes.

        Email subjects:
        \(subjectList)

        For each topic, provide:
        1. A short descriptive name (2-4 words)
        2. Keywords associated with this topic
        3. Estimated percentage of emails

        Format:
        TOPIC: [name]
        KEYWORDS: [comma-separated keywords]
        PERCENTAGE: [X%]
        ---

        Discovered Topics:
        """

        let response = await llm.summarize(content: prompt)
        return parseDiscoveredTopics(from: response)
    }

    // MARK: - Find Similar Emails

    func findSimilarEmails(to email: Email, in emails: [Email], limit: Int = 10) async throws -> [Email] {
        // Use subject and body similarity
        let targetText = "\(email.subject) \(email.body.prefix(500))".lowercased()
        let targetWords = Set(targetText.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })

        var scores: [(Email, Double)] = []

        for candidate in emails where candidate.id != email.id {
            let candidateText = "\(candidate.subject) \(candidate.body.prefix(500))".lowercased()
            let candidateWords = Set(candidateText.components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })

            // Jaccard similarity
            let intersection = targetWords.intersection(candidateWords).count
            let union = targetWords.union(candidateWords).count
            let similarity = union > 0 ? Double(intersection) / Double(union) : 0

            if similarity > 0.1 {
                scores.append((candidate, similarity))
            }
        }

        return scores
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }

    // MARK: - Topic Trends

    func analyzeTopicTrends(_ emails: [Email]) async throws -> [TopicTrend] {
        if clusters.isEmpty {
            _ = try await clusterEmails(emails)
        }

        var trends: [TopicTrend] = []
        let calendar = Calendar.current

        for cluster in clusters {
            let clusterEmails = emails.filter { cluster.emailIds.contains($0.id) }

            // Group by month
            let byMonth = Dictionary(grouping: clusterEmails) { email -> String in
                guard let date = email.dateObject else { return "Unknown" }
                let components = calendar.dateComponents([.year, .month], from: date)
                return "\(components.year ?? 0)-\(String(format: "%02d", components.month ?? 0))"
            }

            let monthlyCounts = byMonth.mapValues { $0.count }.sorted { $0.key < $1.key }

            // Determine trend direction
            let recentMonths = monthlyCounts.suffix(3).map { $0.value }
            let olderMonths = monthlyCounts.dropLast(3).suffix(3).map { $0.value }

            let recentAvg = recentMonths.isEmpty ? 0 : Double(recentMonths.reduce(0, +)) / Double(recentMonths.count)
            let olderAvg = olderMonths.isEmpty ? 0 : Double(olderMonths.reduce(0, +)) / Double(olderMonths.count)

            let direction: TrendDirection
            if recentAvg > olderAvg * 1.2 {
                direction = .increasing
            } else if recentAvg < olderAvg * 0.8 {
                direction = .decreasing
            } else {
                direction = .stable
            }

            trends.append(TopicTrend(
                topic: cluster.name,
                monthlyCounts: monthlyCounts.map { ($0.key, $0.value) },
                direction: direction,
                changePercent: olderAvg > 0 ? ((recentAvg - olderAvg) / olderAvg) * 100 : 0
            ))
        }

        return trends
    }

    // MARK: - Helpers

    private func generateClusterSummary(topic: String, emails: [Email]) async throws -> String {
        let sampleSubjects = emails.prefix(10).map { "• \($0.subject)" }.joined(separator: "\n")

        let prompt = """
        Summarize this email cluster in 2-3 sentences.

        Topic: \(topic)
        Number of emails: \(emails.count)

        Sample subjects:
        \(sampleSubjects)

        Summary:
        """

        return await llm.summarize(content: prompt)
    }

    private func extractKeywords(from emails: [Email]) -> [String] {
        var wordCounts = [String: Int]()
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "shall", "can", "need", "dare", "ought", "used", "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into", "through", "during", "before", "after", "above", "below", "between", "under", "again", "further", "then", "once", "here", "there", "when", "where", "why", "how", "all", "each", "few", "more", "most", "other", "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than", "too", "very", "just", "and", "but", "if", "or", "because", "until", "while", "although", "though", "after", "before", "re", "fwd", "fw"])

        for email in emails {
            let text = "\(email.subject) \(email.body.prefix(200))".lowercased()
            let words = text.components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { $0.key }
    }

    private func getDateRange(from emails: [Email]) -> (Date?, Date?) {
        let dates = emails.compactMap { $0.dateObject }.sorted()
        return (dates.first, dates.last)
    }

    private func getTopSenders(from emails: [Email]) -> [(String, Int)] {
        let bySender = Dictionary(grouping: emails, by: { $0.from })
        return bySender
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .map { ($0.key, $0.value.count) }
    }

    private func parseDiscoveredTopics(from response: String) -> [DiscoveredTopic] {
        var topics: [DiscoveredTopic] = []
        let blocks = response.components(separatedBy: "---")

        for block in blocks {
            var name = ""
            var keywords: [String] = []
            var percentage = 0.0

            let lines = block.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }

                switch parts[0].uppercased() {
                case "TOPIC":
                    name = parts[1]
                case "KEYWORDS":
                    keywords = parts[1].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                case "PERCENTAGE":
                    let numStr = parts[1].replacingOccurrences(of: "%", with: "")
                    percentage = Double(numStr) ?? 0
                default:
                    break
                }
            }

            if !name.isEmpty {
                topics.append(DiscoveredTopic(name: name, keywords: keywords, estimatedPercentage: percentage))
            }
        }

        return topics
    }
}

// MARK: - Models

struct TopicCluster: Identifiable {
    let id: UUID
    let name: String
    let emailIds: [UUID]
    let emailCount: Int
    let summary: String
    let keywords: [String]
    let dateRange: (Date?, Date?)
    let topSenders: [(String, Int)]
}

struct DiscoveredTopic {
    let name: String
    let keywords: [String]
    let estimatedPercentage: Double
}

struct TopicTrend {
    let topic: String
    let monthlyCounts: [(String, Int)]
    let direction: TrendDirection
    let changePercent: Double
}

enum TrendDirection {
    case increasing
    case decreasing
    case stable

    var icon: String {
        switch self {
        case .increasing: return "arrow.up.right"
        case .decreasing: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var color: String {
        switch self {
        case .increasing: return "green"
        case .decreasing: return "red"
        case .stable: return "gray"
        }
    }
}
