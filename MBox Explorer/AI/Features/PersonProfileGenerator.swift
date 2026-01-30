//
//  PersonProfileGenerator.swift
//  MBox Explorer
//
//  Auto-generates contact profiles from email history
//  Author: Jordan Koch
//  Date: 2026-01-30
//

import Foundation

/// Generates comprehensive contact profiles from email history
class PersonProfileGenerator: ObservableObject {
    static let shared = PersonProfileGenerator()

    @Published var isProcessing = false
    @Published var profiles: [String: PersonProfile] = [:]

    private let llm = LocalLLM.shared

    // MARK: - Generate Profile

    func generateProfile(for emailAddress: String, from emails: [Email]) async throws -> PersonProfile {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        let normalizedEmail = emailAddress.lowercased()

        // Find all emails involving this person
        let sentByPerson = emails.filter { $0.from.lowercased().contains(normalizedEmail) }
        let sentToPerson = emails.filter { $0.to?.lowercased().contains(normalizedEmail) == true }
        let allRelated = sentByPerson + sentToPerson

        guard !allRelated.isEmpty else {
            throw ProfileError.noEmailsFound
        }

        // Extract name from email headers
        let name = extractName(from: sentByPerson.first?.from ?? emailAddress)

        // Calculate statistics
        let stats = calculateStats(sent: sentByPerson, received: sentToPerson)

        // Get communication patterns
        let patterns = analyzePatterns(emails: allRelated)

        // Sample recent emails for context
        let recentEmails = allRelated
            .sorted { ($0.dateObject ?? .distantPast) > ($1.dateObject ?? .distantPast) }
            .prefix(20)

        let emailSamples = recentEmails.map { email in
            """
            Subject: \(email.subject)
            Date: \(email.date)
            Preview: \(String(email.body.prefix(200)).replacingOccurrences(of: "\n", with: " "))
            """
        }.joined(separator: "\n---\n")

        // Generate AI summary
        let prompt = """
        Create a profile summary for this email correspondent.

        Name/Email: \(name) <\(emailAddress)>

        Statistics:
        - Emails from them: \(sentByPerson.count)
        - Emails to them: \(sentToPerson.count)
        - First contact: \(stats.firstContact.map { formatDate($0) } ?? "Unknown")
        - Last contact: \(stats.lastContact.map { formatDate($0) } ?? "Unknown")

        Recent email samples:
        \(emailSamples)

        Based on the email history, describe:
        1. Likely relationship (colleague, client, friend, vendor, etc.)
        2. Main topics of communication
        3. Communication style (formal/informal, frequent/occasional)
        4. Any notable patterns or observations
        5. One sentence "who is this person" summary

        Profile:
        """

        let aiSummary = await llm.summarize(content: prompt)

        // Extract topics from subjects
        let topics = extractTopics(from: allRelated)

        let profile = PersonProfile(
            id: UUID(),
            email: emailAddress,
            name: name,
            stats: stats,
            patterns: patterns,
            topics: topics,
            aiSummary: aiSummary.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            generatedAt: Date()
        )

        await MainActor.run {
            self.profiles[emailAddress.lowercased()] = profile
        }

        return profile
    }

    // MARK: - Batch Generation

    func generateAllProfiles(from emails: [Email], minEmails: Int = 3) async throws -> [PersonProfile] {
        await MainActor.run {
            isProcessing = true
        }

        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }

        // Group by email address
        let byPerson = Dictionary(grouping: emails) { extractEmail(from: $0.from) }

        // Filter to those with minimum emails
        let significantPeople = byPerson.filter { $0.value.count >= minEmails }
            .sorted { $0.value.count > $1.value.count }
            .prefix(50) // Limit to top 50

        var profiles: [PersonProfile] = []

        for (email, _) in significantPeople {
            do {
                let profile = try await generateProfile(for: email, from: emails)
                profiles.append(profile)
            } catch {
                print("Error generating profile for \(email): \(error.localizedDescription)")
            }
        }

        return profiles
    }

    // MARK: - Quick Lookup

    func quickLookup(email: String, from emails: [Email]) -> QuickPersonInfo {
        let normalizedEmail = email.lowercased()

        let sentByPerson = emails.filter { $0.from.lowercased().contains(normalizedEmail) }
        let sentToPerson = emails.filter { $0.to?.lowercased().contains(normalizedEmail) == true }

        let name = extractName(from: sentByPerson.first?.from ?? email)

        let sortedByDate = (sentByPerson + sentToPerson)
            .sorted { ($0.dateObject ?? .distantPast) > ($1.dateObject ?? .distantPast) }

        let recentSubjects = sortedByDate.prefix(5).map { $0.subject }

        return QuickPersonInfo(
            email: email,
            name: name,
            emailCount: sentByPerson.count + sentToPerson.count,
            sentCount: sentByPerson.count,
            receivedCount: sentToPerson.count,
            lastContact: sortedByDate.first?.dateObject,
            recentSubjects: recentSubjects
        )
    }

    // MARK: - Helpers

    private func extractName(from emailString: String) -> String {
        // Try to extract name from "Name <email>" format
        if let nameMatch = emailString.range(of: "^[^<]+", options: .regularExpression) {
            let name = String(emailString[nameMatch]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("@") {
                return name.replacingOccurrences(of: "\"", with: "")
            }
        }

        // Extract from email address
        if let atIndex = emailString.firstIndex(of: "@") {
            let localPart = String(emailString[..<atIndex])
                .replacingOccurrences(of: "<", with: "")

            // Convert john.doe to John Doe
            let parts = localPart.split(separator: ".").map { $0.capitalized }
            if parts.count >= 2 {
                return parts.joined(separator: " ")
            }
            return localPart.capitalized
        }

        return emailString
    }

    private func extractEmail(from emailString: String) -> String {
        // Extract email from "Name <email>" format
        if let start = emailString.firstIndex(of: "<"),
           let end = emailString.firstIndex(of: ">") {
            return String(emailString[emailString.index(after: start)..<end]).lowercased()
        }
        return emailString.lowercased()
    }

    private func calculateStats(sent: [Email], received: [Email]) -> PersonStats {
        let all = sent + received
        let sorted = all.compactMap { $0.dateObject }.sorted()

        // Calculate average response time (simplified)
        var responseTimes: [TimeInterval] = []
        // This would need thread analysis for accurate response times

        return PersonStats(
            emailsSent: sent.count,
            emailsReceived: received.count,
            firstContact: sorted.first,
            lastContact: sorted.last,
            averageResponseTime: responseTimes.isEmpty ? nil : responseTimes.reduce(0, +) / Double(responseTimes.count)
        )
    }

    private func analyzePatterns(emails: [Email]) -> CommunicationPatterns {
        let calendar = Calendar.current

        // Hour distribution
        var hourCounts = [Int: Int]()
        for email in emails {
            if let date = email.dateObject {
                let hour = calendar.component(.hour, from: date)
                hourCounts[hour, default: 0] += 1
            }
        }

        // Day of week distribution
        var dayOfWeekCounts = [Int: Int]()
        for email in emails {
            if let date = email.dateObject {
                let weekday = calendar.component(.weekday, from: date)
                dayOfWeekCounts[weekday, default: 0] += 1
            }
        }

        // Find peak hour
        let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key

        // Find peak day
        let peakDay = dayOfWeekCounts.max(by: { $0.value < $1.value })?.key

        return CommunicationPatterns(
            peakHour: peakHour,
            peakDayOfWeek: peakDay,
            hourDistribution: hourCounts,
            dayDistribution: dayOfWeekCounts,
            isWeekendActive: (dayOfWeekCounts[1, default: 0] + dayOfWeekCounts[7, default: 0]) > 0
        )
    }

    private func extractTopics(from emails: [Email]) -> [String] {
        // Simple topic extraction from subjects
        var wordCounts = [String: Int]()
        let stopWords = Set(["re:", "fwd:", "fw:", "the", "a", "an", "is", "are", "was", "were", "be", "been", "being", "and", "or", "but", "for", "with", "about", "your", "our", "their"])

        for email in emails {
            let words = email.subject.lowercased()
                .components(separatedBy: .alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        return wordCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key.capitalized }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Models

struct PersonProfile: Identifiable, Codable {
    let id: UUID
    let email: String
    let name: String
    let stats: PersonStats
    let patterns: CommunicationPatterns
    let topics: [String]
    let aiSummary: String
    let generatedAt: Date
}

struct PersonStats: Codable {
    let emailsSent: Int
    let emailsReceived: Int
    let firstContact: Date?
    let lastContact: Date?
    let averageResponseTime: TimeInterval?

    var totalEmails: Int { emailsSent + emailsReceived }
}

struct CommunicationPatterns: Codable {
    let peakHour: Int?
    let peakDayOfWeek: Int?
    let hourDistribution: [Int: Int]
    let dayDistribution: [Int: Int]
    let isWeekendActive: Bool

    var peakHourFormatted: String? {
        guard let hour = peakHour else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        guard let date = Calendar.current.date(from: components) else { return nil }
        return formatter.string(from: date)
    }

    var peakDayFormatted: String? {
        guard let day = peakDayOfWeek else { return nil }
        let formatter = DateFormatter()
        return formatter.weekdaySymbols[day - 1]
    }
}

struct QuickPersonInfo {
    let email: String
    let name: String
    let emailCount: Int
    let sentCount: Int
    let receivedCount: Int
    let lastContact: Date?
    let recentSubjects: [String]
}

enum ProfileError: LocalizedError {
    case noEmailsFound
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noEmailsFound: return "No emails found for this person"
        case .generationFailed(let reason): return "Profile generation failed: \(reason)"
        }
    }
}
