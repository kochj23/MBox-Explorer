//
//  SimilarEmailFinder.swift
//  MBox Explorer
//
//  Finds similar emails, duplicates, and template detection
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Finds similar emails, duplicates across mailboxes, and detects form letters
class SimilarEmailFinder: ObservableObject {
    static let shared = SimilarEmailFinder()

    @Published var isProcessing = false
    @Published var progress: Double = 0

    private let embeddingManager = EmbeddingManager.shared

    // MARK: - Find Similar Emails

    func findSimilar(to email: Email, in emails: [Email], limit: Int = 10) async -> [SimilarityResult] {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let targetText = normalizeText("\(email.subject) \(email.body)")
        let targetWords = tokenize(targetText)

        var results: [SimilarityResult] = []

        for candidate in emails where candidate.id != email.id {
            let candidateText = normalizeText("\(candidate.subject) \(candidate.body)")
            let candidateWords = tokenize(candidateText)

            // Calculate multiple similarity metrics
            let jaccardSim = jaccardSimilarity(targetWords, candidateWords)
            let cosineSim = cosineSimilarity(targetWords, candidateWords)
            let subjectSim = stringSimilarity(email.subject, candidate.subject)

            // Weighted combination
            let overallScore = (jaccardSim * 0.3) + (cosineSim * 0.4) + (subjectSim * 0.3)

            if overallScore > 0.15 {
                results.append(SimilarityResult(
                    email: candidate,
                    overallScore: overallScore,
                    subjectSimilarity: subjectSim,
                    contentSimilarity: cosineSim,
                    matchType: categorizeMatch(overallScore, subjectSim)
                ))
            }
        }

        return results
            .sorted { $0.overallScore > $1.overallScore }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Find Duplicates

    func findDuplicates(in emails: [Email], threshold: Double = 0.9) async -> [[Email]] {
        await MainActor.run {
            isProcessing = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        var duplicateGroups: [[Email]] = []
        var processed = Set<UUID>()

        for (index, email) in emails.enumerated() {
            guard !processed.contains(email.id) else { continue }

            var group = [email]
            processed.insert(email.id)

            for candidate in emails where !processed.contains(candidate.id) {
                let similarity = calculateSimilarity(email, candidate)
                if similarity >= threshold {
                    group.append(candidate)
                    processed.insert(candidate.id)
                }
            }

            if group.count > 1 {
                duplicateGroups.append(group)
            }

            await MainActor.run {
                self.progress = Double(index + 1) / Double(emails.count)
            }
        }

        return duplicateGroups.sorted { $0.count > $1.count }
    }

    // MARK: - Cross-Mailbox Duplicates

    func findCrossMailboxDuplicates(mailbox1: [Email], mailbox2: [Email], threshold: Double = 0.85) async -> [DuplicatePair] {
        await MainActor.run {
            isProcessing = true
            progress = 0
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        var pairs: [DuplicatePair] = []
        let total = mailbox1.count

        for (index, email1) in mailbox1.enumerated() {
            for email2 in mailbox2 {
                let similarity = calculateSimilarity(email1, email2)
                if similarity >= threshold {
                    pairs.append(DuplicatePair(
                        email1: email1,
                        email2: email2,
                        similarity: similarity
                    ))
                }
            }

            await MainActor.run {
                self.progress = Double(index + 1) / Double(total)
            }
        }

        return pairs.sorted { $0.similarity > $1.similarity }
    }

    // MARK: - Detect Form Letters / Templates

    func detectFormLetters(in emails: [Email], minOccurrences: Int = 3) async -> [FormLetterTemplate] {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Group emails by normalized body structure
        var templateGroups: [String: [Email]] = [:]

        for email in emails {
            let normalized = normalizeForTemplate(email.body)
            let hash = generateTemplateHash(normalized)
            templateGroups[hash, default: []].append(email)
        }

        // Filter to groups with minimum occurrences
        let templates = templateGroups.filter { $0.value.count >= minOccurrences }

        return templates.map { (hash, emails) in
            let representative = emails.first!
            let senders = Set(emails.map { $0.from })

            return FormLetterTemplate(
                id: UUID(),
                templateHash: hash,
                subject: representative.subject,
                bodyPreview: String(representative.body.prefix(500)),
                occurrences: emails.count,
                uniqueSenders: senders.count,
                dateRange: getDateRange(emails),
                emailIds: emails.map { $0.id }
            )
        }.sorted { $0.occurrences > $1.occurrences }
    }

    // MARK: - Similarity Calculations

    private func calculateSimilarity(_ email1: Email, _ email2: Email) -> Double {
        // Quick checks first
        if email1.messageId == email2.messageId && email1.messageId != nil {
            return 1.0 // Exact duplicate
        }

        let text1 = normalizeText("\(email1.subject) \(email1.body)")
        let text2 = normalizeText("\(email2.subject) \(email2.body)")

        let words1 = tokenize(text1)
        let words2 = tokenize(text2)

        return cosineSimilarity(words1, words2)
    }

    private func jaccardSimilarity(_ set1: Set<String>, _ set2: Set<String>) -> Double {
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }

    private func cosineSimilarity(_ words1: Set<String>, _ words2: Set<String>) -> Double {
        // Create word frequency vectors
        let allWords = words1.union(words2)

        var vec1 = [Double]()
        var vec2 = [Double]()

        for word in allWords {
            vec1.append(words1.contains(word) ? 1.0 : 0.0)
            vec2.append(words2.contains(word) ? 1.0 : 0.0)
        }

        // Calculate cosine similarity
        let dotProduct = zip(vec1, vec2).map(*).reduce(0, +)
        let mag1 = sqrt(vec1.map { $0 * $0 }.reduce(0, +))
        let mag2 = sqrt(vec2.map { $0 * $0 }.reduce(0, +))

        return mag1 > 0 && mag2 > 0 ? dotProduct / (mag1 * mag2) : 0
    }

    private func stringSimilarity(_ str1: String, _ str2: String) -> Double {
        let s1 = str1.lowercased()
        let s2 = str2.lowercased()

        if s1 == s2 { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        // Levenshtein-based similarity
        let distance = levenshteinDistance(s1, s2)
        let maxLen = max(s1.count, s2.count)

        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - Helpers

    private func normalizeText(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func tokenize(_ text: String) -> Set<String> {
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "be", "been", "have", "has", "had", "do", "does", "did", "will", "would", "could", "should", "may", "might", "must", "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "and", "or", "but", "if", "then", "so", "than", "too", "very", "just", "also", "not", "no", "yes", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "only", "own", "same", "this", "that", "these", "those", "what", "which", "who", "whom", "how", "when", "where", "why", "here", "there", "now", "then"])

        return Set(text.split(separator: " ")
            .map { String($0) }
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    private func normalizeForTemplate(_ body: String) -> String {
        var normalized = body

        // Remove names, emails, dates, numbers (potential personalization)
        normalized = normalized.replacingOccurrences(of: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}", with: "[EMAIL]", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b", with: "[DATE]", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\$[\\d,]+(\\.\\d{2})?", with: "[AMOUNT]", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\b\\d{5,}\\b", with: "[NUMBER]", options: .regularExpression)

        // Normalize whitespace
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateTemplateHash(_ normalizedBody: String) -> String {
        // Create a hash based on structure
        let words = normalizedBody.split(separator: " ").prefix(50)
        let structure = words.map { word -> String in
            if word == "[EMAIL]" || word == "[DATE]" || word == "[AMOUNT]" || word == "[NUMBER]" {
                return String(word)
            }
            return String(word.prefix(3))
        }.joined()

        // Simple hash
        var hash = 5381
        for char in structure.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(char)
        }

        return String(format: "%08x", abs(hash))
    }

    private func categorizeMatch(_ overallScore: Double, _ subjectSim: Double) -> MatchType {
        if overallScore > 0.9 {
            return .nearDuplicate
        } else if subjectSim > 0.8 && overallScore > 0.7 {
            return .sameThread
        } else if overallScore > 0.5 {
            return .relatedTopic
        } else {
            return .loosleyRelated
        }
    }

    private func getDateRange(_ emails: [Email]) -> (Date?, Date?) {
        let dates = emails.compactMap { $0.dateObject }.sorted()
        return (dates.first, dates.last)
    }
}

// MARK: - Models

struct SimilarityResult {
    let email: Email
    let overallScore: Double
    let subjectSimilarity: Double
    let contentSimilarity: Double
    let matchType: MatchType

    var scorePercent: Int {
        Int(overallScore * 100)
    }
}

enum MatchType: String {
    case nearDuplicate = "Near Duplicate"
    case sameThread = "Same Thread"
    case relatedTopic = "Related Topic"
    case loosleyRelated = "Loosely Related"

    var icon: String {
        switch self {
        case .nearDuplicate: return "doc.on.doc.fill"
        case .sameThread: return "bubble.left.and.bubble.right"
        case .relatedTopic: return "link"
        case .loosleyRelated: return "arrow.triangle.branch"
        }
    }
}

struct DuplicatePair {
    let email1: Email
    let email2: Email
    let similarity: Double
}

struct FormLetterTemplate: Identifiable {
    let id: UUID
    let templateHash: String
    let subject: String
    let bodyPreview: String
    let occurrences: Int
    let uniqueSenders: Int
    let dateRange: (Date?, Date?)
    let emailIds: [UUID]
}
